# qr_scanner_plus

A better qrcode and barcode scanner.

Features:
✅ Camera view can click to set focus point.
✅ Camera view can use scale gesture.
✅ Multi qrcode is support.
✅ Simple to use.
[ ] Automatically find potential QR codes and automatically zoom in and focus

## Getting Started

```dart
import 'package:flutter/material.dart';
import 'package:qr_scanner_plus/qr_scanner_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('BarcodeScannerPlus example'),
        ),
        body: Center(
            child: QrScannerPlusView(
          _onResult,
          debug: true,
        )),
      ),
    );
  }

  _onResult(List<Barcode> barcodes) {
    for (final barcode in barcodes) {
      print(barcode.type);
      print(barcode.rawValue);
    }
  }
}

```