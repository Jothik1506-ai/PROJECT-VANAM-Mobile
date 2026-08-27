import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'member_avatar.dart';

/// One avatar bubble in the family story row at the top of Home.
/// [hasStory] draws the WhatsApp-style ring — colored (brand gradient) if
/// [hasUnseen], grey once every one of that person's active stories has
/// been viewed. No ring at all when they have no active story.
class StoryAvatar extends StatelessWidget {
  const StoryAvatar({
    super.key,
    required this.name,
    this.hasStory = false,
    this.hasUnseen = false,
    this.onTap,
  });

  final String name;
  final bool hasStory;
  final bool hasUnseen;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            alignment: Alignment.center,
            decoration: hasStory
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasUnseen
                        ? const LinearGradient(
                            colors: [
                              Color(0xFFE07A3F), // brand-adjacent warm accent
                              Color(0xFF9F2F24), // kumkum, matches the app's accent palette
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: hasUnseen ? null : palette.line,
                  )
                : null,
            child: MemberAvatar(name: name, size: 56),
          ),
          const SizedBox(height: VanamSpacing.xs),
          Text(name, style: TextStyle(fontSize: 12, color: palette.ink)),
        ],
      ),
    );
  }
}

/// The leading "Add" bubble — dashed circle with a plus icon. Tapping it
/// opens the photo picker to post a new 24h story (see HomeScreen).
class AddMemberAvatar extends StatelessWidget {
  const AddMemberAvatar({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: _DashedCircle(
              color: palette.line,
              child: Icon(Icons.add, color: palette.brand),
            ),
          ),
          const SizedBox(height: VanamSpacing.xs),
          Text('Add', style: TextStyle(fontSize: 12, color: palette.inkMuted)),
        ],
      ),
    );
  }
}

class _DashedCircle extends StatelessWidget {
  const _DashedCircle({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedCirclePainter(color),
      child: Center(child: child),
    );
  }
}

class _DashedCirclePainter extends CustomPainter {
  const _DashedCirclePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashCount = 24;
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    for (var i = 0; i < dashCount; i++) {
      final startAngle = (i * 2 * 3.14159265) / dashCount;
      final endAngle = startAngle + (3.14159265 / dashCount) * 0.6;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 1),
        startAngle,
        endAngle - startAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DashedCirclePainter oldDelegate) =>
      oldDelegate.color != color;
}
