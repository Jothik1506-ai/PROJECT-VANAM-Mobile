import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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

  static final cacheManager = CacheManager(
    Config(
      'vanam_family_media',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 80,
    ),
  );

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
