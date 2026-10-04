import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// مسح باركود أو QR بكاميرا الموبايل. على الكمبيوتر بيستخدم سكانر USB (بيكتب في خانة البحث).
bool get cameraScanSupported => Platform.isAndroid || Platform.isIOS;

Future<String?> scanBarcode(BuildContext context) =>
    Navigator.push<String>(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _ScanPage()));

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('وجّه الكاميرا على الباركود'),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on_rounded), onPressed: () => _controller.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch_rounded), onPressed: () => _controller.switchCamera()),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              final code = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
              if (code == null || _done) return;
              _done = true;
              Navigator.pop(context, code);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'لازم تسمح للتطبيق يستخدم الكاميرا من إعدادات الموبايل'
                      : 'الكاميرا مش شغالة: ${error.errorCode.name}',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
