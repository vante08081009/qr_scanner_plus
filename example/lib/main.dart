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
          child: _buildBarcodeScannerView(),
        ),
      ),
    );
  }

  Widget _buildBarcodeScannerView() {
    return QrScannerPlusView(
      _onResult,
      debug: true,
    );
  }

  _onResult(List<Barcode> barcodes) {
    //print(barcodes);
  }
}
