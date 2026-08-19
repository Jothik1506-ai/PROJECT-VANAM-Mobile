import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/invites/invite_qr_codec.dart';

void main() {
  group('InviteQrCodec', () {
    test('round-trips a real code + pin', () {
      final encoded = InviteQrCodec.encode(code: 'VANAM-7F2K9Q', pin: '8420');
      expect(encoded, 'VANAM1:VANAM-7F2K9Q:8420');

      final decoded = InviteQrCodec.decode(encoded);
      expect(decoded, ('VANAM-7F2K9Q', '8420'));
    });

    test('rejects a QR payload from something unrelated', () {
      expect(InviteQrCodec.decode('https://example.com'), isNull);
      expect(InviteQrCodec.decode('random text'), isNull);
      expect(InviteQrCodec.decode(''), isNull);
    });

    test('rejects a payload with the wrong version prefix', () {
      expect(InviteQrCodec.decode('VANAM2:VANAM-7F2K9Q:8420'), isNull);
    });

    test('rejects a malformed payload with missing parts', () {
      expect(InviteQrCodec.decode('VANAM1:VANAM-7F2K9Q'), isNull);
      expect(InviteQrCodec.decode('VANAM1::8420'), isNull);
      expect(InviteQrCodec.decode('VANAM1:VANAM-7F2K9Q:'), isNull);
    });

    test('trims stray whitespace from a scanned payload', () {
      final decoded = InviteQrCodec.decode('  VANAM1:VANAM-7F2K9Q:8420  ');
      expect(decoded, ('VANAM-7F2K9Q', '8420'));
    });
  });
}
