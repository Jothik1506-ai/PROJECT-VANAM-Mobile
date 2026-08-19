import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/chat/direct_conversation.dart';

void main() {
  group('DirectConversation.fromJson', () {
    test('parses a full row from list_direct_conversations()', () {
      final conversation = DirectConversation.fromJson({
        'conversation_id': 'c1',
        'other_user_id': 'u2',
        'other_display_name': 'Lakshmi',
        'last_message_text': 'See you tomorrow',
        'last_message_at': '2026-08-19T10:00:00.000Z',
      });

      expect(conversation.conversationId, 'c1');
      expect(conversation.otherUserId, 'u2');
      expect(conversation.otherDisplayName, 'Lakshmi');
      expect(conversation.lastMessageText, 'See you tomorrow');
      expect(conversation.lastMessageAt, isNotNull);
    });

    test('a conversation with no messages yet has null preview fields', () {
      final conversation = DirectConversation.fromJson({
        'conversation_id': 'c1',
        'other_user_id': 'u2',
        'other_display_name': 'Lakshmi',
        'last_message_text': null,
        'last_message_at': null,
      });

      expect(conversation.lastMessageText, isNull);
      expect(conversation.lastMessageAt, isNull);
    });

    test('missing display name falls back to a safe default, not a crash', () {
      final conversation = DirectConversation.fromJson({
        'conversation_id': 'c1',
        'other_user_id': 'u2',
      });

      expect(conversation.otherDisplayName, 'Family Member');
    });
  });
}
