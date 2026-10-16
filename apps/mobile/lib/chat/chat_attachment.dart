import 'dart:convert';

enum ChatAttachmentKind { image, file }

/// A photo or document attached to a chat message.
///
/// On the wire an attachment is an ordinary encrypted chat message whose
/// plaintext is [encode]'s output: a marker prefix plus a small JSON
/// description. The file itself is encrypted separately and stored in the
/// private `chat-attachments` bucket at [path].
class ChatAttachment {
  const ChatAttachment({
    required this.kind,
    required this.name,
    required this.mime,
    required this.size,
    required this.path,
  });

  final ChatAttachmentKind kind;
  final String name;
  final String mime;

  /// Size of the original (decrypted) file in bytes.
  final int size;

  /// Object path inside the `chat-attachments` bucket.
  final String path;

  bool get isImage => kind == ChatAttachmentKind.image;

  static const bucket = 'chat-attachments';
  static const _prefix = 'vanam:att:1:';

  /// Largest file a member can send. Encryption runs on the phone, so this
  /// stays modest; photos are compressed before they get anywhere near it.
  static const maxBytes = 15 * 1024 * 1024;

  String encode() => '$_prefix${jsonEncode({
    'k': kind.name,
    'n': name,
    'm': mime,
    's': size,
    'p': path,
  })}';

  /// Returns the attachment described by a decrypted message body, or null
  /// when [text] is an ordinary message.
  static ChatAttachment? tryParse(String text) {
    if (!text.startsWith(_prefix)) return null;
    try {
      final json = jsonDecode(text.substring(_prefix.length));
      if (json is! Map<String, dynamic>) return null;
      final path = json['p'] as String?;
      if (path == null || path.isEmpty) return null;
      return ChatAttachment(
        kind: json['k'] == 'image'
            ? ChatAttachmentKind.image
            : ChatAttachmentKind.file,
        name: json['n'] as String? ?? 'file',
        mime: json['m'] as String? ?? 'application/octet-stream',
        size: (json['s'] as num?)?.toInt() ?? 0,
        path: path,
      );
    } catch (_) {
      return null;
    }
  }

  /// Short text used where a message preview is shown (e.g. notifications,
  /// chat lists).
  String get previewLabel => isImage ? '📷 Photo' : '📎 $name';

  String get sizeLabel {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(0)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
