import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../models/web_update.dart';
import '../theme/tokens.dart';
import 'vanam_logo.dart';

class RotatingWebUpdateCard extends StatefulWidget {
  const RotatingWebUpdateCard({super.key, required this.updates});

  final List<WebUpdate> updates;

  @override
  State<RotatingWebUpdateCard> createState() => _RotatingWebUpdateCardState();
}

class _RotatingWebUpdateCardState extends State<RotatingWebUpdateCard> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.updates.length > 1) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!_controller.hasClients || !mounted) return;
        final next = (_index + 1) % widget.updates.length;
        _controller.animateToPage(
          next,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.updates.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 118,
      child: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.updates.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              return WebUpdateCard(update: widget.updates[index]);
            },
          ),
          if (widget.updates.length > 1)
            Positioned(
              right: VanamSpacing.md,
              bottom: VanamSpacing.sm,
              child: _WebUpdateDots(
                count: widget.updates.length,
                currentIndex: _index,
              ),
            ),
        ],
      ),
    );
  }
}

class _WebUpdateDots extends StatelessWidget {
  const _WebUpdateDots({required this.count, required this.currentIndex});

  final int count;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: i == currentIndex ? 12 : 6,
            height: 6,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: i == currentIndex ? palette.brand : palette.line,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class WebUpdateCard extends StatelessWidget {
  const WebUpdateCard({super.key, required this.update});

  final WebUpdate update;

  Uri get _uri => Uri.parse('${AppConfig.vanamWebBaseUrl}/${update.path}');

  Future<void> _open(BuildContext context) async {
    final uri = _uri;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened || !context.mounted) return;

    await Clipboard.setData(ClipboardData(text: uri.toString()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open page. Link copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Container(
      margin: const EdgeInsets.only(bottom: VanamSpacing.md),
      padding: const EdgeInsets.all(VanamSpacing.md),
      decoration: BoxDecoration(
        color: palette.surfaceCard,
        borderRadius: BorderRadius.circular(VanamRadii.card),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const VanamLogo(size: 46),
          const SizedBox(width: VanamSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  update.status,
                  style: TextStyle(
                    color: palette.brandStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  update.title,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: VanamSpacing.xs),
                Text(
                  update.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 13,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _open(context),
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open page',
          ),
        ],
      ),
    );
  }
}
