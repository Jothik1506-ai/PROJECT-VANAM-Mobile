import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../media/video_fit.dart';
import '../theme/tokens.dart';

/// Tap-to-play video player for Home posts.
///
/// Lazy by design: does NOT create a [VideoPlayerController] or start
/// downloading video bytes until the user explicitly taps "Play". This avoids
/// competing for bandwidth or memory as posts scroll into view.
class PostVideoPlayer extends StatefulWidget {
  const PostVideoPlayer({
    super.key,
    required this.videoUrl,
    this.durationSeconds,
    this.thumbnailUrl,
    this.fullScreen = false,
    this.startAt = Duration.zero,
  });

  final String videoUrl;
  final int? durationSeconds;
  final String? thumbnailUrl;

  /// Full-screen mode: starts playing immediately (the user already asked
  /// for it), no rounded placeholder corners and no "full screen" button.
  final bool fullScreen;

  /// Where playback starts (used when continuing from the feed card).
  final Duration startAt;

  @override
  State<PostVideoPlayer> createState() => _PostVideoPlayerState();
}

class _PostVideoPlayerState extends State<PostVideoPlayer> {
  VideoPlayerController? _controller;
  var _isInitializing = false;
  var _hasError = false;
  var _showControls = true;
  var _isMuted = false;
  Timer? _controlsTimer;

  @override
  void initState() {
    super.initState();
    if (widget.fullScreen) _startPlayback();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _startPlayback() async {
    if (_isInitializing || widget.videoUrl.isEmpty) return;

    setState(() {
      _isInitializing = true;
      _hasError = false;
    });

    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );
      await controller.initialize();
      if (widget.startAt > Duration.zero &&
          widget.startAt < controller.value.duration) {
        await controller.seekTo(widget.startAt);
      }
      controller.addListener(_onControllerUpdate);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isInitializing = false;
      });

      await controller.play();
      _resetControlsTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _hasError = true;
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null) {
      _startPlayback();
      return;
    }
    if (controller.value.isPlaying) {
      controller.pause();
      _controlsTimer?.cancel();
      setState(() => _showControls = true);
    } else {
      if (controller.value.position >= controller.value.duration) {
        controller.seekTo(Duration.zero);
      }
      controller.play();
      _resetControlsTimer();
    }
  }

  void _toggleMute() {
    final controller = _controller;
    if (controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _onTapVideo() {
    setState(() => _showControls = !_showControls);
    if (_showControls && (_controller?.value.isPlaying ?? false)) {
      _resetControlsTimer();
    }
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _showControls = false);
      }
    });
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    final controller = _controller;

    // 1. Initial un-initialized state (zero network requests until tap)
    if (controller == null || !controller.value.isInitialized) {
      return _buildPlaceholder(context, palette);
    }

    // 2. Initialized playing/paused state.
    //
    // Was `AspectRatio(controller.value.aspectRatio, child: VideoPlayer)`,
    // but PostCard already wraps this widget in a 4:3 AspectRatio, whose
    // tight constraints override the inner AspectRatio — so the Texture was
    // forced to 4:3 and every portrait phone video was stretched sideways.
    // Now the video is laid out at its own upright size inside a FittedBox
    // (cover or contain, see computeVideoFit), so it is never distorted
    // whatever box the parent gives it.
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = computeVideoFit(
          reportedSize: controller.value.size,
          viewport: constraints.biggest,
          rotationCorrection: controller.value.rotationCorrection,
        );
        final player = ColoredBox(
          color: Colors.black,
          child: GestureDetector(
            onTap: _onTapVideo,
            behavior: HitTestBehavior.opaque,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRect(
                  child: FittedBox(
                    fit: layout.fit,
                    child: SizedBox.fromSize(
                      size: layout.uprightSize,
                      // VideoPlayer applies rotationCorrection itself.
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),

                // Buffering indicator
                if (controller.value.isBuffering)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),

                // Overlay controls
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_showControls,
                    child: _buildControlsOverlay(context, controller, palette),
                  ),
                ),
              ],
            ),
          ),
        );
        // Unbounded parent (e.g. a plain Column): size to the video itself.
        if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
          return AspectRatio(aspectRatio: layout.aspectRatio, child: player);
        }
        return player;
      },
    );
  }

  Future<void> _openFullScreen() async {
    final controller = _controller;
    final position = controller?.value.position ?? Duration.zero;
    await controller?.pause();
    _controlsTimer?.cancel();
    if (!mounted) return;
    setState(() => _showControls = true);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            FullScreenVideoPage(videoUrl: widget.videoUrl, startAt: position),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, VanamPalette palette) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1916),
        borderRadius: widget.fullScreen
            ? null
            : BorderRadius.circular(VanamRadii.card),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle warm decorative background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [const Color(0xFF2E1C14), const Color(0xFF18120F)],
                ),
              ),
            ),
          ),

          // Top label chip
          Positioned(
            top: VanamSpacing.md,
            left: VanamSpacing.md,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.videocam_outlined,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Family Video',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Duration chip if known
          if (widget.durationSeconds != null && widget.durationSeconds! > 0)
            Positioned(
              top: VanamSpacing.md,
              right: VanamSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _formatDuration(Duration(seconds: widget.durationSeconds!)),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // Center play trigger or loader / error
          if (_isInitializing)
            const SizedBox.square(
              dimension: 48,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            )
          else if (_hasError)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: palette.danger,
                  size: 36,
                ),
                const SizedBox(height: VanamSpacing.sm),
                const Text(
                  'Could not play video',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
                const SizedBox(height: VanamSpacing.sm),
                OutlinedButton(
                  onPressed: _startPlayback,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('Try again'),
                ),
              ],
            )
          else
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _startPlayback,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: palette.brand.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

          if (!_isInitializing && !_hasError)
            Positioned(
              bottom: VanamSpacing.md,
              child: Text(
                'Tap to play',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildControlsOverlay(
    BuildContext context,
    VideoPlayerController controller,
    VanamPalette palette,
  ) {
    final isFinished = controller.value.position >= controller.value.duration;

    return Container(
      color: Colors.black38,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top row: full-screen (feed only) + mute buttons
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(VanamSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!widget.fullScreen)
                    IconButton(
                      onPressed: _openFullScreen,
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                      ),
                      tooltip: 'Full screen',
                    ),
                  IconButton(
                    onPressed: _toggleMute,
                    icon: Icon(
                      _isMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      color: Colors.white,
                    ),
                    tooltip: _isMuted ? 'Unmute' : 'Mute',
                  ),
                ],
              ),
            ),
          ),

          // Center play / pause / replay button
          IconButton(
            onPressed: _togglePlayPause,
            iconSize: 48,
            icon: Icon(
              isFinished
                  ? Icons.replay_rounded
                  : (controller.value.isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_filled_rounded),
              color: Colors.white,
            ),
          ),

          // Bottom scrubber and duration
          Padding(
            padding: const EdgeInsets.fromLTRB(
              VanamSpacing.md,
              0,
              VanamSpacing.md,
              VanamSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  colors: VideoProgressColors(
                    playedColor: palette.brand,
                    bufferedColor: Colors.white30,
                    backgroundColor: Colors.white12,
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(controller.value.position),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                    Text(
                      _formatDuration(controller.value.duration),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen playback of a family video: black background, the video
/// cover-cropped when it is portrait (fills the phone screen like Reels) and
/// letterboxed when it is landscape — never stretched.
class FullScreenVideoPage extends StatelessWidget {
  const FullScreenVideoPage({
    super.key,
    required this.videoUrl,
    this.startAt = Duration.zero,
  });

  final String videoUrl;
  final Duration startAt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SizedBox.expand(
        child: PostVideoPlayer(
          videoUrl: videoUrl,
          fullScreen: true,
          startAt: startAt,
        ),
      ),
    );
  }
}
