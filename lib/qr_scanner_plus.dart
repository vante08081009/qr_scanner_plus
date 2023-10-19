import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'src/camera/camera_view.dart';
import 'src/debug/barcode_detector_debug_painter.dart';
import 'src/debug/object_detector_painter.dart';
import 'src/debug/multi_qrcode_select_painter.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

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
  bool multiCodeSelect = true;
  final Function(List<Barcode> barcode) onResult;
  QrScannerPlusView(this.onResult,
      {this.debug = false, this.multiCodeSelect = true, Key? key})
      : super(key: key);

  @override
  _BarcodeScannerViewState createState() => _BarcodeScannerViewState();
}

class _BarcodeScannerViewState extends State<QrScannerPlusView> {
  final BarcodeScanner _barcodeScanner = BarcodeScanner();
  late ObjectDetector _objectDetector;
  bool _canProcess = true;
  bool _isBusy = false;
  CustomPaint? _customPaint;
  CustomPaint? _customPaint2;
  CustomPaint? _customPaint3;

  List<QrResultCache> _resultCache = [];
  Timer? _timerCallbackResult;
  late CameraView _cameraView;

  @override
  void initState() {
    _initializeDetector(DetectionMode.stream);
    super.initState();
  }

  @override
  void dispose() {
    _canProcess = false;
    _timerCallbackResult?.cancel();
    _barcodeScanner.close();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _cameraView = CameraView(
        customPaint: _customPaint,
        customPaint2: _customPaint2,
        customPaint3: _customPaint3,
        onImage: (inputImage) {
          processImage(inputImage);
        });

    return _cameraView;
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
    //const model = 'packages/qr_scanner_plus/assets/ml/object_labeler.tflite';
    const model = 'assets/ml/object_labeler.tflite';
    final modelPath = await _getModel(model);
    final options = LocalObjectDetectorOptions(
        mode: mode,
        modelPath: modelPath,
        classifyObjects: true,
        multipleObjects: true,
        maximumLabelsPerObject: 3,
        confidenceThreshold: 0.7);
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
    String path = '';
    if (Platform.isAndroid) {
      path = '${(await getApplicationDocumentsDirectory()).path}/$assetPath';
    } else {
      path = '${(await getApplicationSupportDirectory()).path}/$assetPath';
    }
    await Directory(dirname(path)).create(recursive: true);
    final file = File(path);
    if (!await file.exists()) {
      final byteData = await rootBundle.load(assetPath);
      await file.writeAsBytes(byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return file.path;
    //}
  }

  Future<void> processImage(InputImage inputImage) async {
    if (!mounted) return;
    if (!_canProcess) return;
    if (_isBusy) return;
    _isBusy = true;

    //object detect
    List<DetectedObject> objects =
        await _objectDetector.processImage(inputImage);

    if (objects.isNotEmpty) {
      for (final object in objects) {
        for (final label in object.labels) {
          if (label.text.isNotEmpty) {
            // print(
            //     "@@@ object.boundingBox.center: ${object.boundingBox.center}");
            // print(
            //     "@@@ inputImage.metadata!.size: ${inputImage.metadata!.size}");
            print(
                "@@@ label index: ${label.index}, label: ${label.text}, confidence: ${label.confidence}");
            Offset _focusPointOffset;
            if (Platform.isIOS) {
              _focusPointOffset = Offset(
                  object.boundingBox.center.dx /
                      inputImage.metadata!.size.width,
                  object.boundingBox.center.dy /
                      inputImage.metadata!.size.height);
            } else {
              _focusPointOffset = Offset(
                  object.boundingBox.center.dx /
                      inputImage.metadata!.size.height,
                  object.boundingBox.center.dy /
                      inputImage.metadata!.size.width);
            }

            // print("@@@ tmp: ${_focusPointOffset}");
            //if label is 2d  barcode, set the camera focus point
            if (label.index == 7) {
              _cameraView.setCameraFocusPoint(_focusPointOffset);
              Future.delayed(Duration(milliseconds: 300), () {
                if (mounted) {
                  _cameraView.zoomIn();
                }
              });
            }
          }
        }
      }

      if (widget.debug == true && mounted) {
        setState(() {
          _customPaint = CustomPaint(
              painter: ObjectDetectorPainter(objects,
                  inputImage.metadata!.rotation, inputImage.metadata!.size));
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _customPaint = null;
        });
      }
    }

    //barcode decode
    final tmpBarcodes = await _barcodeScanner.processImage(inputImage);

    saveResultCache(tmpBarcodes);

    //callback result every 0.5s
    _timerCallbackResult ??=
        Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;

      if (resultCache.isNotEmpty) {
        if (widget.debug == true) {
          if (inputImage.metadata?.size != null &&
              inputImage.metadata?.rotation != null &&
              mounted) {
            setState(() {
              _customPaint2 = CustomPaint(
                  painter: BarcodeDetectorDebugPainter(
                      resultCache,
                      inputImage.metadata!.size,
                      inputImage.metadata!.rotation));
            });
          }
        }

        //if more then 1 qr code, let user to choose one
        if (resultCache.length > 1) {
          if (widget.multiCodeSelect) {
            _cameraView.pausePreview();
            setState(() {
              _customPaint3 = CustomPaint(
                  painter: MultiQrcodeSelectPainter(
                      resultCache,
                      inputImage.metadata!.size,
                      inputImage.metadata!.rotation,
                      onMultiSelect));
            });
          }

          _isBusy = false;
        } else {
          setState(() {
            _customPaint3 = CustomPaint(
                painter: MultiQrcodeSelectPainter(
                    resultCache,
                    inputImage.metadata!.size,
                    inputImage.metadata!.rotation,
                    onMultiSelect));
          });
          widget.onResult.call(resultCache);
          _isBusy = false;
          return;
        }
      } else {
        if (mounted) {
          setState(() {
            _customPaint2 = null;
            _customPaint3 = null;
          });
        }
      }
    });

    _isBusy = false;
  }

  onMultiSelect(Barcode barcode) {
    setState(() {
      _customPaint3 = null;
    });
    widget.onResult.call([barcode]);
  }
}
