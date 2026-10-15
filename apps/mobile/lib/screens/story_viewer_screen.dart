import 'dart:async';

import 'package:flutter/material.dart';

import '../home/story_repository.dart';
import '../media/vanam_cached_image.dart';
import '../models/story.dart';
import '../widgets/feedback_button.dart';

/// Full-screen WhatsApp-style story viewer. [initialGroupIndex] is which
/// person's stories to open on; tapping the right/left third of the
/// screen moves forward/back, each story auto-advances after
/// [_storyDuration], and running out of stories for one person moves on
/// to the next person's group (or closes, after the last one) — same
/// browsing model as WhatsApp Status.
class StoryViewerScreen extends StatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroupIndex,
    required this.repository,
    this.currentUserId,
    this.onDeleted,
  });

  final List<StoryGroup> groups;
  final int initialGroupIndex;
  final StoryRepository repository;
  final String? currentUserId;
  final VoidCallback? onDeleted;

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  static const _storyDuration = Duration(seconds: 5);

  late int _groupIndex = widget.initialGroupIndex;
  int _storyIndex = 0;
  late final AnimationController _progress;
  Timer? _fallbackTimer;

  StoryGroup get _group => widget.groups[_groupIndex];
  Story get _story => _group.stories[_storyIndex];

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(vsync: this, duration: _storyDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _advance();
      });
    _startCurrent();
  }

  @override
  void dispose() {
    _progress.dispose();
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _startCurrent() {
    unawaited(widget.repository.markViewed(_story.id));
    _progress
      ..reset()
      ..forward();
  }

  void _advance() {
    if (_storyIndex < _group.stories.length - 1) {
      setState(() => _storyIndex++);
      _startCurrent();
      return;
    }
    if (_groupIndex < widget.groups.length - 1) {
      setState(() {
        _groupIndex++;
        _storyIndex = 0;
      });
      _startCurrent();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _goBack() {
    if (_storyIndex > 0) {
      setState(() => _storyIndex--);
      _startCurrent();
      return;
    }
    if (_groupIndex > 0) {
      setState(() {
        _groupIndex--;
        _storyIndex = widget.groups[_groupIndex].stories.length - 1;
      });
      _startCurrent();
      return;
    }
    // Already the very first story — restart it instead of doing nothing.
    _startCurrent();
  }

  Future<void> _deleteCurrent() async {
    _progress.stop();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this story?'),
        content: const Text('This removes it for everyone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      _progress.forward();
      return;
    }
    try {
      await widget.repository.deleteOwnStory(_story.id);
      widget.onDeleted?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete story.')),
        );
        _progress.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            VanamCachedImage(
              key: ValueKey(_story.id),
              imageUrl: _story.mediaUrl,
              fit: BoxFit.contain,
              width: MediaQuery.sizeOf(context).width.round(),
              resize: 'contain',
              placeholder: (context) =>
                  const Center(child: CircularProgressIndicator()),
              errorWidget: (context) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
            // Tap zones: left third = back, right two-thirds = forward.
            // A held press pauses the auto-advance timer, same as
            // WhatsApp/Instagram stories.
            Row(
              children: [
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onTap: _goBack,
                    onLongPressStart: (_) => _progress.stop(),
                    onLongPressEnd: (_) => _progress.forward(),
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: _advance,
                    onLongPressStart: (_) => _progress.stop(),
                    onLongPressEnd: (_) => _progress.forward(),
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  for (var i = 0; i < _group.stories.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) => LinearProgressIndicator(
                          value: i < _storyIndex
                              ? 1
                              : i == _storyIndex
                              ? _progress.value
                              : 0,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white,
                          ),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 20,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _group.authorName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                      ),
                    ),
                  ),
                  if (widget.currentUserId != null &&
                      _story.authorId == widget.currentUserId)
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                      onPressed: _deleteCurrent,
                    ),
                  FeedbackIconButton(
                    screen: 'Story viewer',
                    color: Colors.white,
                    itemId: _story.id,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
