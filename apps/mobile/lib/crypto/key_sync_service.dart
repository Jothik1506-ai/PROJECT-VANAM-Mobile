import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'e2ee_service.dart';

final keySyncService = KeySyncService(Supabase.instance.client);

/// Gets a chat scope's plaintext symmetric key onto this device, and keeps
/// other members supplied with their own copy — the two halves of
/// end-to-end encryption that actually touch the network. See
/// supabase/migrations/20260820030000_e2ee_and_password_recovery.sql for
/// the key_wraps table and RPCs this talks to.
///
/// A scope is either the family group (`scope: 'group', scopeId:
/// 'family-group'`) or one direct conversation (`scope: 'direct'`,
/// `scopeId`: the conversation id).
class KeySyncService {
  KeySyncService(this._client);

  final SupabaseClient _client;
  final _e2ee = E2eeService.instance;

  final Map<String, Uint8List> _cache = {};
  Future<void>? _publicKeyReady;

  String _cacheKey(String scope, String scopeId) => '$scope:$scopeId';

  /// Uploads this device's public key to profiles.public_key if it isn't
  /// already there — the prerequisite for anyone to ever seal a key for
  /// this member. Safe to call on every app start; it's a no-op once set.
  Future<void> ensurePublicKeyUploaded() async {
    final existing = _publicKeyReady;
    if (existing != null) return existing;

    final upload = _ensurePublicKeyUploaded();
    _publicKeyReady = upload;
    try {
      await upload;
    } catch (_) {
      if (identical(_publicKeyReady, upload)) _publicKeyReady = null;
      rethrow;
    }
  }

  Future<void> _ensurePublicKeyUploaded() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;

    final myKey = await _e2ee.myPublicKeyBase64();
    final row = await _client
        .from('profiles')
        .select('public_key')
        .eq('id', uid)
        .maybeSingle();
    if (row != null && row['public_key'] == myKey) return;

    await _client.from('profiles').update({'public_key': myKey}).eq('id', uid);
  }

  /// Returns the scope's plaintext symmetric key, or null if this device
  /// doesn't have it yet and no one else has created it either — a state
  /// that resolves itself once another already-keyed device calls
  /// [resealForMissingMembers] for this scope (which every device does
  /// opportunistically whenever it opens that chat).
  Future<Uint8List?> getScopeKey({
    required String scope,
    required String scopeId,
  }) async {
    await ensurePublicKeyUploaded();
    final cacheKey = _cacheKey(scope, scopeId);
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final myWrap = await _client.rpc<String?>(
      'fetch_my_key_wrap',
      params: {'p_scope': scope, 'p_scope_id': scopeId},
    );
    if (myWrap != null) {
      final key = await _e2ee.unsealMyKey(myWrap);
      if (key != null) {
        _cache[cacheKey] = key;
        await resealForMissingMembers(scope: scope, scopeId: scopeId, key: key);
        return key;
      }

      // This wrap was sealed to a private key that no longer exists, which
      // happens after reinstall/clear-data. Remove only our unusable copy;
      // another participant that still has the scope key will reseal it for
      // the new public key on their next refresh/open.
      await _client.rpc(
        'delete_own_key_wrap',
        params: {'p_scope': scope, 'p_scope_id': scopeId},
      );
    }

    // No wrap for me yet. If nothing has ever been created for this scope,
    // this device becomes the one that creates it (first sender/opener
    // wins — key_wraps' unique constraint makes a second concurrent
    // creator's self-wrap a harmless no-op via ON CONFLICT DO NOTHING,
    // they'll just pick up the real key from their own reseal pass next).
    final exists = await _client.rpc<bool>(
      'scope_key_exists',
      params: {'p_scope': scope, 'p_scope_id': scopeId},
    );
    if (exists) return null;

    final newKey = _e2ee.generateSymmetricKey();
    final myPublicKey = await _e2ee.myPublicKeyBase64();
    final sealedForSelf = await _e2ee.sealKeyFor(
      symmetricKey: newKey,
      recipientPublicKeyBase64: myPublicKey,
    );
    final uid = _client.auth.currentUser!.id;
    await _client.rpc(
      'upload_key_wrap',
      params: {
        'p_scope': scope,
        'p_scope_id': scopeId,
        'p_member_id': uid,
        'p_sealed_key': sealedForSelf,
      },
    );
    _cache[cacheKey] = newKey;
    await resealForMissingMembers(scope: scope, scopeId: scopeId, key: newKey);
    return newKey;
  }

  /// Seals [key] for every current scope participant who doesn't have a
  /// wrap yet (and has a public key uploaded). Any device that already
  /// holds the plaintext key can do this — it's how a newly-joined member,
  /// or a member opening the app for the first time after this feature
  /// shipped, eventually gets their own wrap without needing the admin.
  Future<void> resealForMissingMembers({
    required String scope,
    required String scopeId,
    required Uint8List key,
  }) async {
    final missing = await _client.rpc<List<dynamic>>(
      'list_missing_key_wraps',
      params: {'p_scope': scope, 'p_scope_id': scopeId},
    );

    for (final row in missing.whereType<Map<String, dynamic>>()) {
      final memberId = row['member_id'] as String?;
      final publicKey = row['public_key'] as String?;
      if (memberId == null || publicKey == null) continue;

      final sealed = await _e2ee.sealKeyFor(
        symmetricKey: key,
        recipientPublicKeyBase64: publicKey,
      );
      await _client.rpc(
        'upload_key_wrap',
        params: {
          'p_scope': scope,
          'p_scope_id': scopeId,
          'p_member_id': memberId,
          'p_sealed_key': sealed,
        },
      );
    }
  }

  /// Refreshes every chat this member can access. A keyed device calling
  /// this on app start automatically reseals missing wraps for a family
  /// member who reinstalled, without requiring each chat to be opened.
  Future<void> refreshAccessibleScopes() async {
    try {
      await ensurePublicKeyUploaded();
      await getScopeKey(scope: 'group', scopeId: 'family-group');

      final rows = await _client.rpc<List<dynamic>>(
        'list_direct_conversations',
      );
      for (final row in rows.whereType<Map<String, dynamic>>()) {
        final conversationId = row['conversation_id'] as String?;
        if (conversationId == null) continue;
        try {
          await getScopeKey(scope: 'direct', scopeId: conversationId);
        } catch (_) {
          // One damaged/new conversation must not prevent the remaining
          // conversations from refreshing their wraps.
        }
      }
    } catch (_) {
      // Startup key refresh is opportunistic. Chat screens retry and show a
      // specific encryption-sync message when connectivity is unavailable.
    }
  }
}
