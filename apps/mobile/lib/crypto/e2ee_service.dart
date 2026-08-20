import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// This device's X25519 keypair + the "sealed box" primitive used to hand
/// chat-scope symmetric keys to other members without the server ever
/// seeing plaintext key material.
///
/// Sealed box (same idea as libsodium's crypto_box_seal): to encrypt
/// [plaintext] for someone else's public key with no shared secret and no
/// sender identity needed, generate a one-time ephemeral X25519 keypair,
/// ECDH it against the recipient's public key, derive an AES-256 key from
/// that via HKDF, and AES-GCM-encrypt with a zero nonce. The zero nonce is
/// safe here specifically because the derived key is unique per call (a
/// fresh ephemeral keypair every time) — nonce reuse only matters when the
/// same key encrypts more than once.
class E2eeService {
  E2eeService._();
  static final E2eeService instance = E2eeService._();

  static const _storage = FlutterSecureStorage();
  static const _privateKeyStorageKey = 'vanam_x25519_private_key';

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  SimpleKeyPair? _cachedKeyPair;

  /// Loads this device's keypair from secure storage, generating and
  /// persisting a new one on first run. Idempotent — safe to call anytime.
  Future<SimpleKeyPair> ensureKeyPair() async {
    final cached = _cachedKeyPair;
    if (cached != null) return cached;

    final storedSeed = await _storage.read(key: _privateKeyStorageKey);
    if (storedSeed != null) {
      final seedBytes = base64Decode(storedSeed);
      final keyPair = await _x25519.newKeyPairFromSeed(seedBytes);
      _cachedKeyPair = keyPair;
      return keyPair;
    }

    final keyPair = await _x25519.newKeyPair();
    final seedBytes = await keyPair.extractPrivateKeyBytes();
    await _storage.write(
      key: _privateKeyStorageKey,
      value: base64Encode(seedBytes),
    );
    _cachedKeyPair = keyPair;
    return keyPair;
  }

  /// This device's public key, base64-encoded — the value uploaded to
  /// profiles.public_key.
  Future<String> myPublicKeyBase64() async {
    final keyPair = await ensureKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Generates a fresh random 256-bit symmetric key for a chat scope
  /// (the family group, or one direct conversation).
  Uint8List generateSymmetricKey() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
  }

  /// Seals [symmetricKey] to [recipientPublicKeyBase64] — only that
  /// public key's matching private key can open it. Returns base64.
  Future<String> sealKeyFor({
    required Uint8List symmetricKey,
    required String recipientPublicKeyBase64,
  }) async {
    final recipientPublicKey = SimplePublicKey(
      base64Decode(recipientPublicKeyBase64),
      type: KeyPairType.x25519,
    );

    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
    );
    final derivedKey = await _deriveAesKey(
      sharedSecret: sharedSecret,
      ephemeralPublicKeyBytes: ephemeralPublicKey.bytes,
      recipientPublicKeyBytes: recipientPublicKey.bytes,
    );

    final secretBox = await _aesGcm.encrypt(
      symmetricKey,
      secretKey: derivedKey,
      nonce: List<int>.filled(12, 0),
    );

    final sealed = Uint8List.fromList([
      ...ephemeralPublicKey.bytes,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(sealed);
  }

  /// Opens a value produced by [sealKeyFor] using this device's own
  /// keypair. Returns null if it can't be opened (wrong key, corrupt data)
  /// rather than throwing — callers treat that as "not ready yet".
  Future<Uint8List?> unsealMyKey(String sealedBase64) async {
    try {
      final sealed = base64Decode(_stripWhitespace(sealedBase64));
      if (sealed.length < 32 + 16) return null; // ephemeral pubkey + min tag

      final ephemeralPublicKeyBytes = sealed.sublist(0, 32);
      final rest = sealed.sublist(32);
      final cipherText = rest.sublist(0, rest.length - 16);
      final macBytes = rest.sublist(rest.length - 16);

      final keyPair = await ensureKeyPair();
      final myPublicKey = await keyPair.extractPublicKey();

      final ephemeralPublicKey = SimplePublicKey(
        ephemeralPublicKeyBytes,
        type: KeyPairType.x25519,
      );
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: keyPair,
        remotePublicKey: ephemeralPublicKey,
      );
      final derivedKey = await _deriveAesKey(
        sharedSecret: sharedSecret,
        ephemeralPublicKeyBytes: ephemeralPublicKeyBytes,
        recipientPublicKeyBytes: myPublicKey.bytes,
      );

      final secretBox = SecretBox(
        cipherText,
        nonce: List<int>.filled(12, 0),
        mac: Mac(macBytes),
      );
      final plaintext = await _aesGcm.decrypt(secretBox, secretKey: derivedKey);
      return Uint8List.fromList(plaintext);
    } catch (_) {
      return null;
    }
  }

  /// Postgres's `encode(bytes, 'base64')` line-wraps every 76 characters
  /// (MIME-style) — Dart's base64Decode rejects embedded newlines, so
  /// anything round-tripped through a `text` RPC param needs this before
  /// decoding. Short payloads never hit the wrap length, which is why this
  /// only shows up for longer ciphertext/sealed keys.
  static String _stripWhitespace(String s) => s.replaceAll(RegExp(r'\s+'), '');

  /// Encrypts a chat message body with a chat scope's symmetric key.
  /// Output: 12-byte nonce || ciphertext || 16-byte tag, base64-encoded —
  /// this is exactly what lands in the `body bytea` column (via the RPC's
  /// base64 in/out, see 20260820030000_e2ee_and_password_recovery.sql).
  Future<String> encryptMessage({
    required String plaintext,
    required Uint8List symmetricKey,
  }) async {
    final key = SecretKey(symmetricKey);
    final nonce = _aesGcm.newNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final packed = Uint8List.fromList([
      ...nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(packed);
  }

  /// Reverses [encryptMessage]. Returns null (rather than throwing) on any
  /// failure — a message this device can't decrypt (wrong/missing key,
  /// corrupt data) should render as "Unable to decrypt", not crash the
  /// chat screen.
  Future<String?> decryptMessage({
    required String ciphertextBase64,
    required Uint8List symmetricKey,
  }) async {
    try {
      final packed = base64Decode(_stripWhitespace(ciphertextBase64));
      if (packed.length < 12 + 16) return null;
      final nonce = packed.sublist(0, 12);
      final rest = packed.sublist(12);
      final cipherText = rest.sublist(0, rest.length - 16);
      final macBytes = rest.sublist(rest.length - 16);

      final key = SecretKey(symmetricKey);
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(macBytes));
      final plaintext = await _aesGcm.decrypt(secretBox, secretKey: key);
      return utf8.decode(plaintext);
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _deriveAesKey({
    required SecretKey sharedSecret,
    required List<int> ephemeralPublicKeyBytes,
    required List<int> recipientPublicKeyBytes,
  }) {
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: [...ephemeralPublicKeyBytes, ...recipientPublicKeyBytes],
      info: utf8.encode('vanam-sealed-box'),
    );
  }
}
