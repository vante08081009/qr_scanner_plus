import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'src/camera_view.dart';
import 'src/barcode_detector_debug_painter.dart';
import 'src/object_detector_painter.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

export 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
export 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class QrResultCache {
  Barcode barcode;
  int count;

  QrResultCache(this.barcode, this.count);
}

class QrScannerPlusView extends StatefulWidget {
  bool debug = false;
  bool stop = false;
  final Function(List<Barcode> barcodes) onResult;
  QrScannerPlusView(this.onResult, {this.debug = false, Key? key})
      : super(key: key);

  void pause() {
    stop = true;
  }

  void resume() {
    stop = false;
  }

  @override
  _BarcodeScannerViewState createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<QrScannerPlusView> {
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  late ObjectDetector _objectDetector;
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  List<QrResultCache> _resultCache = [];
  Timer? _timerCallbackResult;

  @override
  void initState() {
    _initializeDetector(DetectionMode.stream);
    super.initState();
  }

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
        cache.count = max(0, cache.count - 2);
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
            cache.count = min(30, cache.count + 10);
          } else {
            cache.count = max(0, cache.count - 2);
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

  void _initializeDetector(DetectionMode mode) async {
    print('Set detector in mode: $mode');

    // uncomment next lines if you want to use the default model
    // final options = ObjectDetectorOptions(
    //     mode: mode, classifyObjects: true, multipleObjects: true);
    // _objectDetector = ObjectDetector(options: options);

    // uncomment next lines if you want to use a local model
    // make sure to add tflite model to assets/ml
    final path = 'assets/ml/object_labeler.tflite';
    final modelPath = await _getModel(path);
    final options = LocalObjectDetectorOptions(
      mode: mode,
      modelPath: modelPath,
      classifyObjects: true,
      multipleObjects: true,
    );
    _objectDetector = ObjectDetector(options: options);

    // uncomment next lines if you want to use a remote model
    // make sure to add model to firebase
    // final modelName = 'bird-classifier';
    // final response =
    //     await FirebaseObjectDetectorModelManager().downloadModel(modelName);
    // print('Downloaded: $response');
    // final options = FirebaseObjectDetectorOptions(
    //   mode: mode,
    //   modelName: modelName,
    //   classifyObjects: true,
    //   multipleObjects: true,
    // );
    // _objectDetector = ObjectDetector(options: options);

    _canProcess = true;
  }

  Future<String> _getModel(String assetPath) async {
    if (Platform.isAndroid) {
      return 'flutter_assets/$assetPath';
    }
    final path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    await Directory(dirname(path)).create(recursive: true);
    final file = io.File(path);
    if (!await file.exists()) {
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return file.path;
  }

  Future<void> processImage(InputImage inputImage) async {
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;

    final tmpBarcodes = await _barcodeScanner.processImage(inputImage);

    final objects = await _objectDetector.processImage(inputImage);
    for (final object in objects) {
      for (final label in object.labels) {
        print("@@@ label ${label.text} ${label.confidence}");
      }
    }

    saveResultCache(tmpBarcodes);

    //callback result every 0.5s
    _timerCallbackResult ??=
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (resultCache.isNotEmpty) {
        if (widget.stop != true) {
          widget.onResult.call(resultCache);
        }

        if (widget.debug == true) {
          if (inputImage.inputImageData?.size != null &&
              inputImage.inputImageData?.imageRotation != null) {
            final painter = BarcodeDetectorDebugPainter(
                resultCache,
                inputImage.inputImageData!.size,
                inputImage.inputImageData!.imageRotation);

            setState(() {
              _customPaint = CustomPaint(painter: painter);
            });
          }
        }
      } else {
        setState(() {
          _customPaint = null;
        });
      }
    });
    setState(() {});
    _isBusy = false;
  }
}
