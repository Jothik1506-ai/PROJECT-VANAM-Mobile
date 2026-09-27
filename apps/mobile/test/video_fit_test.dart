import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanam_mobile/media/video_fit.dart';

void main() {
  const phoneScreen = Size(412, 915); // ~9:20 portrait phone
  const feedCard = Size(400, 300); // PostCard's 4:3 media box

  group('uprightVideoSize', () {
    test('keeps an already-upright size (current video_player behaviour)', () {
      expect(
        uprightVideoSize(const Size(1080, 1920), rotationCorrection: 90),
        const Size(1080, 1920),
      );
    });

    test('swaps a raw landscape size when rotation 90/270 is unapplied', () {
      expect(
        uprightVideoSize(
          const Size(1920, 1080),
          rotationCorrection: 90,
          reportedSizeIsUpright: false,
        ),
        const Size(1080, 1920),
      );
      expect(
        uprightVideoSize(
          const Size(1920, 1080),
          rotationCorrection: 270,
          reportedSizeIsUpright: false,
        ),
        const Size(1080, 1920),
      );
      expect(
        uprightVideoSize(
          const Size(1920, 1080),
          rotationCorrection: 180,
          reportedSizeIsUpright: false,
        ),
        const Size(1920, 1080),
      );
    });

    test('falls back to a portrait size when the player reports zero', () {
      expect(uprightVideoSize(Size.zero), const Size(1080, 1920));
    });
  });

  group('computeVideoFit', () {
    test('portrait phone video fills a portrait screen (cover)', () {
      final layout = computeVideoFit(
        reportedSize: const Size(1080, 1920),
        viewport: phoneScreen,
      );
      expect(layout.fit, BoxFit.cover);
      expect(layout.uprightSize, const Size(1080, 1920));
    });

    test('raw rotated portrait recording is treated as portrait', () {
      final layout = computeVideoFit(
        reportedSize: const Size(1920, 1080),
        rotationCorrection: 90,
        reportedSizeIsUpright: false,
        viewport: phoneScreen,
      );
      expect(layout.fit, BoxFit.cover);
      expect(layout.aspectRatio, closeTo(9 / 16, 0.001));
    });

    test('landscape video on a portrait screen is letterboxed', () {
      final layout = computeVideoFit(
        reportedSize: const Size(1920, 1080),
        viewport: phoneScreen,
      );
      expect(layout.fit, BoxFit.contain);
    });

    test('3:4 video on a tall screen is letterboxed, not over-cropped', () {
      final layout = computeVideoFit(
        reportedSize: const Size(960, 1280),
        viewport: phoneScreen,
      );
      expect(layout.fit, BoxFit.contain);
    });

    test('portrait video in the 4:3 feed card is pillarboxed', () {
      final layout = computeVideoFit(
        reportedSize: const Size(1080, 1920),
        viewport: feedCard,
      );
      expect(layout.fit, BoxFit.contain);
    });

    test('invalid viewport falls back to contain', () {
      final layout = computeVideoFit(
        reportedSize: const Size(1080, 1920),
        viewport: const Size(double.infinity, double.infinity),
      );
      expect(layout.fit, BoxFit.contain);
    });
  });

  testWidgets('FittedBox layout keeps the video aspect ratio in a 4:3 box', (
    tester,
  ) async {
    final layout = computeVideoFit(
      reportedSize: const Size(1080, 1920),
      viewport: feedCard,
    );
    const key = Key('video');
    await tester.pumpWidget(
      Center(
        child: SizedBox.fromSize(
          size: feedCard,
          child: FittedBox(
            fit: layout.fit,
            child: SizedBox.fromSize(
              size: layout.uprightSize,
              child: const ColoredBox(key: key, color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(key));
    // Rendered at 9:16 (pillarboxed inside 4:3), not stretched to 4:3.
    expect(rect.width / rect.height, closeTo(9 / 16, 0.01));
    expect(rect.height, closeTo(feedCard.height, 0.01));
  });
}
