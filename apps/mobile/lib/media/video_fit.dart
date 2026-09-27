import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// How a video should be laid out inside a box (a feed card or the whole
/// screen): the video's upright size, and whether to cover-crop or letterbox.
///
/// The widget tree built from this is always
/// `FittedBox(fit: fit, child: SizedBox.fromSize(size: uprightSize, child: VideoPlayer(...)))`
/// so the video keeps its own aspect ratio and is never stretched.
@immutable
class VideoFitLayout {
  const VideoFitLayout({required this.uprightSize, required this.fit});

  /// The video's display size once rotation metadata has been applied
  /// (a portrait phone recording is taller than it is wide here).
  final Size uprightSize;

  /// [BoxFit.cover] (fill the box, crop the overflow) or [BoxFit.contain]
  /// (show the whole frame, black bars on the short sides).
  final BoxFit fit;

  double get aspectRatio => uprightSize.width / uprightSize.height;
}

/// Fallback when the player has not reported a usable size yet.
const _fallbackVideoSize = Size(1080, 1920);

/// Cover-crop only when at most this much of the frame's short side would be
/// cut away (e.g. a 9:16 phone video on a 9:20 screen keeps ~80% of its width,
/// so it fills the screen like Instagram Reels; a 3:4 video would lose 40%,
/// so it is letterboxed instead).
const _minVisibleFractionForCover = 0.75;

/// Returns the video's upright size.
///
/// [reportedSize] is `VideoPlayerController.value.size`. On current
/// video_player_android (2.12, ExoPlayer) and AVFoundation, that size is
/// already upright and `VideoPlayer` applies `rotationCorrection` itself via a
/// `RotatedBox`, so the default [reportedSizeIsUpright] = true is correct.
/// Pass false only for a source that reports the raw (pre-rotation) coded
/// size together with a 90/270 degree [rotationCorrection].
Size uprightVideoSize(
  Size reportedSize, {
  int rotationCorrection = 0,
  bool reportedSizeIsUpright = true,
}) {
  if (reportedSize.width <= 0 ||
      reportedSize.height <= 0 ||
      !reportedSize.width.isFinite ||
      !reportedSize.height.isFinite) {
    return _fallbackVideoSize;
  }
  final quarterTurns = (rotationCorrection ~/ 90) % 4;
  if (!reportedSizeIsUpright && quarterTurns.isOdd) {
    return Size(reportedSize.height, reportedSize.width);
  }
  return reportedSize;
}

/// Decides how to show a video of [reportedSize] inside [viewport].
///
/// - Same orientation and close aspect ratio (portrait video on a portrait
///   phone screen): [BoxFit.cover], filling the screen edge to edge.
/// - Otherwise (landscape video on a portrait screen, portrait video in a
///   landscape feed card, very different ratios): [BoxFit.contain], i.e.
///   letterbox/pillarbox. Never a stretch.
VideoFitLayout computeVideoFit({
  required Size reportedSize,
  required Size viewport,
  int rotationCorrection = 0,
  bool reportedSizeIsUpright = true,
}) {
  final upright = uprightVideoSize(
    reportedSize,
    rotationCorrection: rotationCorrection,
    reportedSizeIsUpright: reportedSizeIsUpright,
  );
  if (viewport.width <= 0 ||
      viewport.height <= 0 ||
      !viewport.width.isFinite ||
      !viewport.height.isFinite) {
    return VideoFitLayout(uprightSize: upright, fit: BoxFit.contain);
  }

  final videoAspect = upright.width / upright.height;
  final viewportAspect = viewport.width / viewport.height;
  final videoIsPortrait = videoAspect < 1;
  final viewportIsPortrait = viewportAspect < 1;

  // Fraction of the video's cropped dimension that stays visible under cover.
  final visibleFraction = videoAspect > viewportAspect
      ? viewportAspect / videoAspect
      : videoAspect / viewportAspect;

  final cover =
      videoIsPortrait == viewportIsPortrait &&
      visibleFraction >= _minVisibleFractionForCover;

  return VideoFitLayout(
    uprightSize: upright,
    fit: cover ? BoxFit.cover : BoxFit.contain,
  );
}
