import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vanam_mobile/chat/attachment_picker.dart';
import 'package:vanam_mobile/chat/chat_attachment.dart';
import 'package:vanam_mobile/chat/chat_message.dart';
import 'package:vanam_mobile/chat/chat_page.dart';

ChatMessage _msg(String id, int minute) => ChatMessage(
  id: id,
  senderName: 'A',
  text: id,
  sentAt: DateTime.utc(2026, 10, 1, 12, minute),
);

void main() {
  group('AttachmentPicker.fromXFiles', () {
    XFile file(String name) =>
        XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name, path: name);

    test('documents keep the file kind', () async {
      final r = await AttachmentPicker.fromXFiles([
        file('report.pdf'),
      ], ChatAttachmentKind.file);
      expect(r.items.single.kind, ChatAttachmentKind.file);
      expect(r.items.single.mime, 'application/pdf');
    });

    test('photos keep the image kind', () async {
      final r = await AttachmentPicker.fromXFiles([
        file('a.jpg'),
      ], ChatAttachmentKind.image);
      expect(r.items.single.kind, ChatAttachmentKind.image);
    });
  });

  group('ChatPage.pagingFromRows', () {
    Map<String, dynamic> row(String id, String sentAt) => {
      'id': id,
      'sent_at': sentAt,
    };

    test('full raw page means hasOlder even if rows get filtered', () {
      final rows = [
        row('b', '2026-10-01T12:00:00Z'),
        row('a', '2026-10-01T11:00:00Z'),
      ];
      final p = ChatPage.pagingFromRows(rows, 2);
      expect(p.hasOlder, isTrue);
      expect(p.cursor!.id, 'a');
      expect(p.cursor!.toParams()['p_before_id'], 'a');
    });

    test('short page means no older history', () {
      final p = ChatPage.pagingFromRows([row('a', '2026-10-01T11:00:00Z')], 2);
      expect(p.hasOlder, isFalse);
    });

    test('equal sent_at picks the smaller id as cursor', () {
      final p = ChatPage.pagingFromRows([
        row('b', '2026-10-01T11:00:00Z'),
        row('a', '2026-10-01T11:00:00Z'),
      ], 5);
      expect(p.cursor!.id, 'a');
    });

    test('empty rows give no cursor', () {
      final p = ChatPage.pagingFromRows([], 5);
      expect(p.cursor, isNull);
      expect(p.hasOlder, isFalse);
    });
  });

  group('ChatPage.mergeNewest', () {
    test('empty filtered page keeps the current list', () {
      final current = [_msg('x', 1)];
      expect(
        ChatPage.mergeNewest(current, [], serverEmpty: false),
        same(current),
      );
    });

    test('truly empty server clears the list', () {
      expect(
        ChatPage.mergeNewest([_msg('x', 1)], [], serverEmpty: true),
        isEmpty,
      );
    });

    test('keeps older loaded pages before the newest page', () {
      final merged = ChatPage.mergeNewest(
        [_msg('old', 1), _msg('mid', 5)],
        [_msg('mid', 5), _msg('new', 6)],
        serverEmpty: false,
      );
      expect(merged.map((m) => m.id), ['old', 'mid', 'new']);
    });
  });
}
