import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../chat/attachment_service.dart';
import '../chat/chat_attachment.dart';
import '../theme/tokens.dart';

/// Renders a chat attachment inside a message bubble: a decrypted photo
/// preview, or a tappable document row.
class ChatAttachmentView extends StatefulWidget {
  const ChatAttachmentView({
    super.key,
    required this.attachment,
    required this.scope,
    required this.scopeId,
    required this.textColor,
  });

  final ChatAttachment attachment;
  final String scope;
  final String scopeId;
  final Color textColor;

  @override
  State<ChatAttachmentView> createState() => _ChatAttachmentViewState();
}

class _ChatAttachmentViewState extends State<ChatAttachmentView> {
  Future<Uint8List>? _image;
  var _opening = false;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.isImage) _image = _load();
  }

  @override
  void didUpdateWidget(ChatAttachmentView old) {
    super.didUpdateWidget(old);
    if (old.attachment.path != widget.attachment.path) {
      _image = widget.attachment.isImage ? _load() : null;
    }
  }

  Future<Uint8List> _load() => chatAttachmentService.fetch(
    scope: widget.scope,
    scopeId: widget.scopeId,
    attachment: widget.attachment,
  );

  void _retryImage() => setState(() => _image = _load());

  Future<void> _openDocument() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final bytes = await chatAttachmentService.fetch(
        scope: widget.scope,
        scopeId: widget.scopeId,
        attachment: widget.attachment,
      );
      final dir = await getTemporaryDirectory();
      final safeName = widget.attachment.name.replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final file = File('${dir.path}${Platform.pathSeparator}$safeName');
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        _snack('No app on this phone can open this file.');
      }
    } catch (_) {
      if (mounted) _snack('Could not open this file. Check your connection.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final attachment = widget.attachment;

    if (attachment.isImage) {
      return FutureBuilder<Uint8List>(
        future: _image,
        builder: (context, snapshot) {
          const size = 220.0;
          if (snapshot.hasError) {
            return InkWell(
              onTap: _retryImage,
              child: SizedBox(
                width: size,
                height: 120,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.refresh, color: widget.textColor),
                    const SizedBox(height: 4),
                    Text(
                      'Photo unavailable · tap to retry',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: widget.textColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null) {
            return SizedBox(
              width: size,
              height: size,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.textColor,
                ),
              ),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatImageViewerScreen(bytes: bytes),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VanamRadii.field - 4),
              child: Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
                cacheWidth: 600,
                gaplessPlayback: true,
              ),
            ),
          );
        },
      );
    }

    return InkWell(
      onTap: _openDocument,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file_outlined, color: widget.textColor),
          const SizedBox(width: VanamSpacing.sm),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: widget.textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _opening ? 'Opening…' : attachment.sizeLabel,
                  style: TextStyle(
                    color: widget.textColor.withValues(alpha: 0.75),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (_opening)
            Padding(
              padding: const EdgeInsets.only(left: VanamSpacing.sm),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.inkMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen pinch-to-zoom view of a decrypted chat photo.
class ChatImageViewerScreen extends StatelessWidget {
  const ChatImageViewerScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
