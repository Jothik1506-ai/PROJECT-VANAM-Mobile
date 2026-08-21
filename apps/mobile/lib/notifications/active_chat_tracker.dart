/// Tracks which chat screen (if any) is currently open on this device, so a
/// foreground push notification for that exact chat can be suppressed —
/// the message is already appearing live via Realtime, so a system
/// notification banner on top of it is pure noise (this is what WhatsApp
/// does too: no banner while you're already looking at the chat).
///
/// Deliberately a bare global instead of a stream/notifier: the only
/// consumer is a synchronous check inside a push-notification callback,
/// and the only writers are ChatDetailScreen's init/dispose. A single
/// current value is all this needs.
class ActiveChatTracker {
  ActiveChatTracker._();
  static final instance = ActiveChatTracker._();

  String? _current;

  static const String familyGroupScope = 'family-group';

  static String directScope(String conversationId) => 'direct:$conversationId';

  void setActive(String scope) => _current = scope;

  /// Only clears if [scope] is still the current one — avoids a race where
  /// screen B's dispose() (running after screen A's initState() already set
  /// the new active scope) accidentally clears screen A's value.
  void clearIfActive(String scope) {
    if (_current == scope) _current = null;
  }

  bool isActive(String scope) => _current == scope;
}

final activeChatTracker = ActiveChatTracker.instance;
