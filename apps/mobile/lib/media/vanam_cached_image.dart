import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Picks a request width for [VanamCachedImage] that actually matches this
/// device's screen, instead of a fixed constant that's wrong on every
/// device except whatever one it happened to be tuned on. [logicalWidth]
/// is the widget's own width in logical pixels (e.g. full screen width for
/// a full-bleed image, or a card's measured width) — this multiplies it by
/// the device's actual pixel ratio and caps the result so very high-DPI
/// devices don't request an absurdly large transform.
int screenAwareImageWidth(
  BuildContext context,
  double logicalWidth, {
  int cap = 1080,
}) {
  final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  final physical = (logicalWidth * devicePixelRatio).round();
  return physical.clamp(1, cap);
}

class VanamCachedImage extends StatefulWidget {
  const VanamCachedImage({
    super.key,
    required this.imageUrl,
    required this.fit,
    required this.width,
    this.quality = 65,
    this.resize = 'cover',
    this.placeholder,
    this.errorWidget,
    this.imageBuilder,
  });

  final String imageUrl;
  final BoxFit fit;
  final int width;
  final int quality;
  final String resize;
  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;
  final ImageWidgetBuilder? imageBuilder;

  // Must be an ImageCacheManager (not a plain CacheManager) because
  // CachedNetworkImage below is given memCacheWidth/maxWidthDiskCache —
  // cached_network_image asserts the cache manager supports resizing
  // whenever either is set, and throws otherwise. That assertion is
  // stripped in release builds (so this silently just skipped the resize
  // optimization there — images still loaded fine), but a debug build hit
  // the real assertion failure, which surfaced as every photo failing to
  // load ("Photo unavailable") the moment private-bucket signed URLs (a
  // different code path than the old public URLs) started being used.
  static final cacheManager = _VanamImageCacheManager();

  @override
  State<VanamCachedImage> createState() => _VanamCachedImageState();
}

class _VanamCachedImageState extends State<VanamCachedImage> {
  var _useOriginal = false;
  var _fallbackQueued = false;

  @override
  Widget build(BuildContext context) {
    final displayUrl = _useOriginal
        ? widget.imageUrl
        : _transformedSupabaseUrl(
            widget.imageUrl,
            width: widget.width,
            quality: widget.quality,
            resize: widget.resize,
          );

    return CachedNetworkImage(
      imageUrl: displayUrl,
      cacheManager: VanamCachedImage.cacheManager,
      fit: widget.fit,
      memCacheWidth: widget.width,
      maxWidthDiskCache: widget.width,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, url) =>
          widget.placeholder?.call(context) ?? const SizedBox.shrink(),
      errorWidget: (context, url, error) {
        if (!_useOriginal &&
            !_fallbackQueued &&
            displayUrl != widget.imageUrl) {
          _fallbackQueued = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _useOriginal = true);
          });
          return widget.placeholder?.call(context) ?? const SizedBox.shrink();
        }
        return widget.errorWidget?.call(context) ??
            const Icon(Icons.broken_image_outlined);
      },
      imageBuilder: widget.imageBuilder,
    );
  }
}

class _VanamImageCacheManager extends CacheManager with ImageCacheManager {
  static const _key = 'vanam_family_media';
  static final _instance = _VanamImageCacheManager._();

  factory _VanamImageCacheManager() => _instance;

  _VanamImageCacheManager._()
    : super(
        Config(
          _key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 80,
        ),
      );
}

String _transformedSupabaseUrl(
  String url, {
  required int width,
  required int quality,
  required String resize,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  const objectPath = '/storage/v1/object/public/';
  if (!uri.path.startsWith(objectPath)) return url;

  final query = Map<String, String>.from(uri.queryParameters);
  query.addAll({'width': '$width', 'quality': '$quality', 'resize': resize});

  return uri
      .replace(
        path: uri.path.replaceFirst(
          objectPath,
          '/storage/v1/render/image/public/',
        ),
        queryParameters: query,
      )
      .toString();
}
