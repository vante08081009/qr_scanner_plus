import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'src/camera_view.dart';
import 'src/barcode_detector_debug_painter.dart';

export 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class QrResultCache {
  Barcode barcode;
  int count;

  QrResultCache(this.barcode, this.count);
}

class QrScannerPlusView extends StatefulWidget {
  bool debug = false;
  final Function(List<Barcode> barcodes) onResult;
  QrScannerPlusView(this.onResult, {this.debug = false, Key? key})
      : super(key: key);

  @override
  _BarcodeScannerViewState createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<QrScannerPlusView> {
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  List<QrResultCache> _resultCache = [];

  @override
  void dispose() {
    _canProcess = false;
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CameraView(
      customPaint: _customPaint,
      onImage: (inputImage) {
        processImage(inputImage);
      },
    );
  }

  saveResultCache(List<Barcode> barcodes) {
    if (barcodes.isEmpty) {
      for (final cache in _resultCache) {
        cache.count = max(0, cache.count - 1);
      }
    } else {
      for (final barcode in barcodes) {
        QrResultCache tmp = _resultCache.firstWhere(
            (element) => element.barcode.rawValue == barcode.rawValue,
            orElse: () => QrResultCache(barcode, -1));
        if (tmp.count == -1) {
          _resultCache.add(QrResultCache(barcode, 0));
        }

        for (final cache in _resultCache) {
          if (cache.barcode.rawValue == barcode.rawValue) {
            cache.barcode = barcode;
            cache.count = min(30, cache.count + 30);
          } else {
            cache.count = max(0, cache.count - 1);
          }
        }
      }
    }
  }

  List<Barcode> get resultCache {
    var tmp = _resultCache.where((element) => element.count > 0);

    if (tmp.isNotEmpty) {
      List<Barcode> ret = [];

      for (final element in tmp) {
        ret.add(element.barcode);
      }
      return ret;
    } else {
      return [];
    }
  }

  Future<void> processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;

    final tmpBarcodes = await _barcodeScanner.processImage(inputImage);

    saveResultCache(tmpBarcodes);

    var barcodes = resultCache;
    if (barcodes.isNotEmpty) {
      widget.onResult.call(barcodes);
    }

    if (widget.debug == true) {
      if (inputImage.inputImageData?.size != null &&
          inputImage.inputImageData?.imageRotation != null) {
        final painter = BarcodeDetectorDebugPainter(
            barcodes,
            inputImage.inputImageData!.size,
            inputImage.inputImageData!.imageRotation);
        _customPaint = CustomPaint(painter: painter);
      }
    }

    _isBusy = false;
    if (mounted) {
      setState(() {});
    }
  }
}
