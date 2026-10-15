import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import 'chat_attachment.dart';

/// A file the user chose to send, read into memory and ready to encrypt.
class PickedAttachment {
  PickedAttachment({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.kind,
  });

  final Uint8List bytes;
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
    return _fromXFiles(files.take(maxPerSend));
  }

  static Future<PickResult> camera() async {
    final file = await _images.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    return file == null ? PickResult.empty : _fromXFiles([file]);
  }

  /// Documents of any type (PDF, Word, Excel, text, ...).
  static Future<PickResult> documents() async {
    final picked = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (picked == null) return PickResult.empty;

    final items = <PickedAttachment>[];
    var tooLarge = 0;
    for (final file in picked.files.take(maxPerSend)) {
      if (file.size > ChatAttachment.maxBytes) {
        tooLarge++;
        continue;
      }
      Uint8List? bytes = file.bytes;
      final path = file.path;
      if (bytes == null && path != null) bytes = await File(path).readAsBytes();
      if (bytes == null) continue;
      items.add(
        PickedAttachment(
          bytes: bytes,
          name: file.name,
          mime: mimeFor(file.name),
          kind: ChatAttachmentKind.file,
        ),
      );
    }
    return PickResult(items, tooLarge: tooLarge);
  }

  static Future<PickResult> _fromXFiles(Iterable<XFile> files) async {
    final items = <PickedAttachment>[];
    var tooLarge = 0;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      if (bytes.length > ChatAttachment.maxBytes) {
        tooLarge++;
        continue;
      }
      items.add(
        PickedAttachment(
          bytes: bytes,
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
