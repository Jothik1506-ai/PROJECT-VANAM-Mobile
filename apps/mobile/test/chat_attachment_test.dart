import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/chat/chat_attachment.dart';
import 'package:vanam_mobile/chat/chat_message.dart';
import 'package:vanam_mobile/crypto/e2ee_service.dart';

void main() {
  test('attachment survives encode/parse', () {
    const original = ChatAttachment(
      kind: ChatAttachmentKind.file,
      name: 'Ration card.pdf',
      mime: 'application/pdf',
      size: 2048,
      path: 'group/u1/abc',
    );
    final parsed = ChatAttachment.tryParse(original.encode());
    expect(parsed, isNotNull);
    expect(parsed!.name, 'Ration card.pdf');
    expect(parsed.isImage, isFalse);
    expect(parsed.size, 2048);
    expect(parsed.path, 'group/u1/abc');
    expect(parsed.sizeLabel, '2 KB');
  });

  test('ordinary text is not an attachment', () {
    expect(ChatAttachment.tryParse('hello'), isNull);
    expect(ChatAttachment.tryParse('vanam:att:1:{bad json'), isNull);
    expect(ChatAttachment.tryParse('vanam:att:1:{"n":"x"}'), isNull);
  });

  test('ChatMessage exposes its attachment', () {
    final message = ChatMessage(
      id: '1',
      senderName: 'A',
      text: const ChatAttachment(
        kind: ChatAttachmentKind.image,
        name: 'p.jpg',
        mime: 'image/jpeg',
        size: 10,
        path: 'direct/c/x',
      ).encode(),
      sentAt: DateTime(2026),
    );
    expect(message.attachment?.isImage, isTrue);
  });

  test('file bytes round-trip and reject a wrong key', () async {
    final e2ee = E2eeService.instance;
    final key = e2ee.generateSymmetricKey();
    final data = Uint8List.fromList(List.generate(5000, (i) => i % 256));

    final packed = await e2ee.encryptBytes(bytes: data, symmetricKey: key);
    expect(packed.length, data.length + 28);
    expect(
      await e2ee.decryptBytes(packed: packed, symmetricKey: key),
      equals(data),
    );
    expect(
      await e2ee.decryptBytes(
        packed: packed,
        symmetricKey: e2ee.generateSymmetricKey(),
      ),
      isNull,
    );
  });
}
