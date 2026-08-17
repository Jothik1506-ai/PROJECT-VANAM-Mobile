import 'package:flutter/material.dart';

final vanamThemeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

String themeModeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'System',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}
