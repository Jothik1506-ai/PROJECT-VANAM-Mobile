import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/update/update_service.dart';
import 'update_prompt.dart';

class UpdateCheckGate extends StatefulWidget {
  const UpdateCheckGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateCheckGate> createState() => _UpdateCheckGateState();
}

class _UpdateCheckGateState extends State<UpdateCheckGate> {
  late final UpdateService _service;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _service = UpdateService(manifestUrl: AppConfig.updateManifestUrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    if (_checked || !AppConfig.updateChecksEnabled || !mounted) return;
    _checked = true;

    try {
      final result = await _service.check();
      if (!mounted || !result.hasUpdate) return;

      await UpdatePrompt.show(context, result: result, service: _service);
    } catch (_) {
      // OTA is a convenience path for sideloaded builds. It must never
      // destabilize normal app startup.
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
