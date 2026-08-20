import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../invites/invite_qr_codec.dart';
import '../theme/tokens.dart';

/// Scans the QR code shown on the admin's member-created sheet (see
/// admin_invites_screen.dart) and pops back to Login with the
/// (username, password) pair it decodes. Only ever pops on a payload that
/// actually parses as ours — a random unrelated QR code is silently
/// ignored rather than sent back as garbage credentials.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController();
  var _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;
      final decoded = InviteQrCodec.decode(raw);
      if (decoded == null) continue;
      _handled = true;
      Navigator.of(context).pop(decoded);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.vanam;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan login QR code'),
        actions: [
          IconButton(
            tooltip: 'Toggle flash',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: palette.brand, width: 3),
                borderRadius: BorderRadius.circular(VanamRadii.card),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: VanamSpacing.xl,
            child: Text(
              'Point the camera at the login QR code',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
            ),
          ),
        ],
      ),
    );
  }
}
