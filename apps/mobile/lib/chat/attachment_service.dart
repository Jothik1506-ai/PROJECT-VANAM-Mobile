import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/e2ee_service.dart';
import '../crypto/key_sync_service.dart';
import 'chat_attachment.dart';

final chatAttachmentService = ChatAttachmentService(Supabase.instance.client);

class AttachmentTooLargeException implements Exception {
  const AttachmentTooLargeException();

  @override
  String toString() => 'Files can be up to 15 MB.';
}

class AttachmentUnavailableException implements Exception {
  const AttachmentUnavailableException();

  @override
  String toString() => 'This file could not be opened.';
}

/// Encrypts files with a chat's key and moves them to and from the private
/// `chat-attachments` bucket. The server only ever stores ciphertext.
class ChatAttachmentService {
  ChatAttachmentService(this._client);

  final SupabaseClient _client;
  final _e2ee = E2eeService.instance;

  // Decrypted images already fetched in this app session, so scrolling a
  // chat doesn't download and decrypt the same photo again. Small on
  // purpose: photos are already compressed before sending.
  static const _cacheLimit = 40;
  final _cache = <String, Uint8List>{};

  /// Encrypts [bytes] with the chat's key, uploads it, and returns the
  /// attachment description to embed in the chat message.
  ///
  /// [scope] is `group` or `direct`; [scopeId] is `family-group` or the
  /// conversation id.
  Future<ChatAttachment> upload({
    required String scope,
    required String scopeId,
    required Uint8List bytes,
    required String name,
    required String mime,
    required ChatAttachmentKind kind,
  }) async {
    if (bytes.length > ChatAttachment.maxBytes) {
      throw const AttachmentTooLargeException();
    }
    final key = await keySyncService.getScopeKey(
      scope: scope,
      scopeId: scopeId,
    );
    if (key == null) throw const EncryptionKeyUnavailableException();

    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Not signed in');
    final folder = scope == 'group' ? 'group/$userId' : 'direct/$scopeId';
    final path = '$folder/${_randomId()}';

    final encrypted = await _e2ee.encryptBytes(bytes: bytes, symmetricKey: key);
    await _client.storage
        .from(ChatAttachment.bucket)
        .uploadBinary(
          path,
          encrypted,
          fileOptions: const FileOptions(
            contentType: 'application/octet-stream',
            upsert: false,
          ),
        );

    return ChatAttachment(
      kind: kind,
      name: name,
      mime: mime,
      size: bytes.length,
      path: path,
    );
  }

  /// Best-effort removal of an uploaded file whose message never went out.
  Future<void> discard(ChatAttachment attachment) async {
    try {
      await _client.storage.from(ChatAttachment.bucket).remove([
        attachment.path,
      ]);
    } catch (_) {}
  }

  /// Downloads and decrypts an attachment.
  Future<Uint8List> fetch({
    required String scope,
    required String scopeId,
    required ChatAttachment attachment,
  }) async {
    final cached = _cache[attachment.path];
    if (cached != null) return cached;

    final key = await keySyncService.getScopeKey(
      scope: scope,
      scopeId: scopeId,
    );
    if (key == null) throw const EncryptionKeyUnavailableException();

    final packed = await _client.storage
        .from(ChatAttachment.bucket)
        .download(attachment.path);
    final plain = await _e2ee.decryptBytes(packed: packed, symmetricKey: key);
    if (plain == null) throw const AttachmentUnavailableException();

    if (attachment.isImage) {
      if (_cache.length >= _cacheLimit) _cache.remove(_cache.keys.first);
      _cache[attachment.path] = plain;
    }
    return plain;
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
