import 'package:flutter/material.dart';

/// Circular VANAM logo mark used on Login/Splash/Home/avatars.
///
/// `Final.png` is pre-composed as a filled white circle with the
/// calligraphy centered and transparent corners — no extra circular
/// container or background needed around it.
class VanamLogo extends StatelessWidget {
  const VanamLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/brand/Final.png',
        fit: BoxFit.contain,
      ),
    );
  }
}
