import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/crypto/e2ee_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage talks over a platform channel with no
  // implementation in a plain `flutter test` run — fake it with a simple
  // in-memory map so ensureKeyPair()'s read/write calls succeed here the
  // same way they would on a real device's secure storage.
  final fakeStore = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'read':
        return fakeStore[call.arguments['key']];
      case 'write':
        fakeStore[call.arguments['key'] as String] =
            call.arguments['value'] as String;
        return null;
      case 'readAll':
        return fakeStore;
      case 'delete':
        fakeStore.remove(call.arguments['key']);
        return null;
      case 'deleteAll':
        fakeStore.clear();
        return null;
      case 'containsKey':
        return fakeStore.containsKey(call.arguments['key']);
      default:
        return null;
    }
  });

  final e2ee = E2eeService.instance;

  group('E2eeService message encryption', () {
    test('round-trips a plaintext message under a symmetric key', () async {
      final key = e2ee.generateSymmetricKey();
      final ciphertext = await e2ee.encryptMessage(
        plaintext: 'Hello family!',
        symmetricKey: key,
      );

      expect(ciphertext, isNot(contains('Hello family!')));

      final decrypted = await e2ee.decryptMessage(
        ciphertextBase64: ciphertext,
        symmetricKey: key,
      );
      expect(decrypted, 'Hello family!');
    });

    test('fails to decrypt with the wrong key', () async {
      final key = e2ee.generateSymmetricKey();
      final wrongKey = e2ee.generateSymmetricKey();
      final ciphertext = await e2ee.encryptMessage(
        plaintext: 'secret',
        symmetricKey: key,
      );

      final decrypted = await e2ee.decryptMessage(
        ciphertextBase64: ciphertext,
        symmetricKey: wrongKey,
      );
      expect(decrypted, isNull);
    });

    test('two encryptions of the same plaintext produce different ciphertext',
        () async {
      final key = e2ee.generateSymmetricKey();
      final a = await e2ee.encryptMessage(plaintext: 'same', symmetricKey: key);
      final b = await e2ee.encryptMessage(plaintext: 'same', symmetricKey: key);
      expect(a, isNot(b)); // random nonce each time
    });
  });

  group('E2eeService sealed-box key wrapping', () {
    test('seals a symmetric key to a public key and unseals it back',
        () async {
      final symmetricKey = e2ee.generateSymmetricKey();
      final recipientPublicKey = await e2ee.myPublicKeyBase64();

      final sealed = await e2ee.sealKeyFor(
        symmetricKey: symmetricKey,
        recipientPublicKeyBase64: recipientPublicKey,
      );

      final unsealed = await e2ee.unsealMyKey(sealed);
      expect(unsealed, symmetricKey);
    });

    test('unsealMyKey returns null for garbage input', () async {
      final result = await e2ee.unsealMyKey('not-valid-base64-sealed-data');
      expect(result, isNull);
    });
  });
}
