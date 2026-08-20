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

  String _cacheKey(String scope, String scopeId) => '$scope:$scopeId';

  /// Uploads this device's public key to profiles.public_key if it isn't
  /// already there — the prerequisite for anyone to ever seal a key for
  /// this member. Safe to call on every app start; it's a no-op once set.
  Future<void> ensurePublicKeyUploaded() async {
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
      }
      return key;
    }

    // No wrap for me yet. If nothing has ever been created for this scope,
    // this device becomes the one that creates it (first sender/opener
    // wins — key_wraps' unique constraint makes a second concurrent
    // creator's self-wrap a harmless no-op via ON CONFLICT DO NOTHING,
    // they'll just pick up the real key from their own reseal pass next).
    final exists = scope == 'group'
        ? await _client.rpc<bool>('group_key_exists')
        : (await _client.rpc<String?>(
                'fetch_my_key_wrap',
                params: {'p_scope': scope, 'p_scope_id': scopeId},
              ) !=
              null);
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
}
