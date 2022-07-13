import 'dart:async';

import 'package:flutter/services.dart';

export 'src/barcode_scanner_view.dart';

class QrScannerPlus {
  static const MethodChannel _channel = MethodChannel('qr_scanner_plus');

  static Future<String?> get platformVersion async {
    final String? version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
