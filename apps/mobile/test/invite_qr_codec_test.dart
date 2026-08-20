import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/invites/invite_qr_codec.dart';

void main() {
  group('InviteQrCodec', () {
    test('round-trips a real username + password', () {
      final encoded = InviteQrCodec.encode(
        username: 'vanam_jothik',
        password: 'vanam_2026',
      );
      expect(encoded, 'VANAM2:vanam_jothik:vanam_2026');

      final decoded = InviteQrCodec.decode(encoded);
      expect(decoded, ('vanam_jothik', 'vanam_2026'));
    });

    test('rejects a QR payload from something unrelated', () {
      expect(InviteQrCodec.decode('https://example.com'), isNull);
      expect(InviteQrCodec.decode('random text'), isNull);
      expect(InviteQrCodec.decode(''), isNull);
    });

    test('rejects a payload with the wrong version prefix', () {
      expect(InviteQrCodec.decode('VANAM1:vanam_jothik:vanam_2026'), isNull);
    });

    test('rejects a malformed payload with missing parts', () {
      expect(InviteQrCodec.decode('VANAM2:vanam_jothik'), isNull);
      expect(InviteQrCodec.decode('VANAM2::vanam_2026'), isNull);
      expect(InviteQrCodec.decode('VANAM2:vanam_jothik:'), isNull);
    });

    test('trims stray whitespace from a scanned payload', () {
      final decoded = InviteQrCodec.decode('  VANAM2:vanam_jothik:vanam_2026  ');
      expect(decoded, ('vanam_jothik', 'vanam_2026'));
    });
  });
}
