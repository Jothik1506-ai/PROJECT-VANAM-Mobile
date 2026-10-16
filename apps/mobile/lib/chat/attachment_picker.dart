import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_attachment.dart';

/// A file the user chose to send. Its bytes are read only when it is
/// about to be encrypted and uploaded, so a multi-file pick never holds
/// every file in memory at once.
class PickedAttachment {
  PickedAttachment({
    required Future<Uint8List> Function() read,
    required this.name,
    required this.mime,
    required this.kind,
  }) : _read = read;

  final Future<Uint8List> Function() _read;

  /// Reads the file's bytes. Call right before encrypting; don't keep them.
  Future<Uint8List> readBytes() => _read();

  final String name;
  final String mime;
  final ChatAttachmentKind kind;

  /// Set once the encrypted file is uploaded, so a retry after a failed
  /// message send doesn't upload it a second time.
  ChatAttachment? uploaded;

  String get placeholderText =>
      kind == ChatAttachmentKind.image ? '📷 Photo' : '📎 $name';
}

/// Result of a pick: the files that can be sent, plus how many were skipped
/// for being over the size limit.
class PickResult {
  const PickResult(this.items, {this.tooLarge = 0});

  final List<PickedAttachment> items;
  final int tooLarge;

  static const empty = PickResult([]);
}

class AttachmentPicker {
  AttachmentPicker._();

  static const maxPerSend = 10;
  static final _images = ImagePicker();

  /// Photos from the gallery (several at once). They are downscaled and
  /// compressed by the picker, like Home post photos.
  static Future<PickResult> gallery() async {
    final files = await _images.pickMultiImage(
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return _fromXFiles(files.take(maxPerSend), ChatAttachmentKind.image);
  }

  static Future<PickResult> camera() async {
    final file = await _images.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return file == null
        ? PickResult.empty
        : _fromXFiles([file], ChatAttachmentKind.image);
  }

  /// Documents of any type (PDF, Word, Excel, text, ...).
  static Future<PickResult> documents() async {
    // file_picker 13: pickFiles() is multi-select and returns an empty list
    // when the user cancels. Each PlatformFile exposes an XFile, read lazily.
    final picked = await FilePicker.pickFiles();
    return _fromXFiles(
      picked.take(maxPerSend).map((f) => f.xFile),
      ChatAttachmentKind.file,
    );
  }

  static Future<PickResult> _fromXFiles(
    Iterable<XFile> files,
    ChatAttachmentKind kind,
  ) async {
    final items = <PickedAttachment>[];
    var tooLarge = 0;
    for (final file in files) {
      if (await file.length() > ChatAttachment.maxBytes) {
        tooLarge++;
        continue;
      }
      items.add(
        PickedAttachment(
          read: file.readAsBytes,
          name: file.name,
          mime: mimeFor(file.name),
          kind: ChatAttachmentKind.image,
        ),
      );
    }
    return PickResult(items, tooLarge: tooLarge);
  }

  static String mimeFor(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt' => 'text/plain',
      'csv' => 'text/csv',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }
}
