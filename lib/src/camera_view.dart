import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class QrScannerCameraPlusView extends StatefulWidget {
  const QrScannerCameraPlusView(
      {Key? key,
      required this.title,
      required this.customPaint,
      this.text,
      this.onCameraPermissionDenied,
      required this.onImage,
      this.initialDirection = CameraLensDirection.back})
      : super(key: key);

  final String title;
  final CustomPaint? customPaint;
  final String? text;
  final Function(InputImage inputImage) onImage;
  final Function()? onCameraPermissionDenied;
  final CameraLensDirection initialDirection;

  @override
  _CameraViewState createState() => _CameraViewState();
}

class _CameraViewState extends State<QrScannerCameraPlusView> {
  CameraController? _controller;
  File? _image;
  String? _path;
  List<CameraDescription> cameras = [];

  int _cameraIndex = 0;
  double zoomLevel = 1, minZoomLevel = 1, maxZoomLevel = 1;
  double zoomTarget = 0, _lastGestureScale = 1;
  final bool _allowPicker = true;
  bool _changingCameraLens = false;

  @override
  void initState() {
    super.initState();

    _initCamera();
  }

  @override
  void dispose() {
    _stopLiveFeed();
    super.dispose();
  }

  _initCamera() async {
    requestPermission().then((isGranted) {
      if (isGranted == true) {
        availableCameras().then((value) {
          cameras = value;

          if (cameras.any(
            (element) =>
                element.lensDirection == widget.initialDirection &&
                element.sensorOrientation == 90,
          )) {
            _cameraIndex = cameras.indexOf(
              cameras.firstWhere((element) =>
                  element.lensDirection == widget.initialDirection &&
                  element.sensorOrientation == 90),
            );
          } else {
            _cameraIndex = cameras.indexOf(
              cameras.firstWhere(
                (element) => element.lensDirection == widget.initialDirection,
              ),
            );
          }

          _startLiveFeed();
        });
      } else {
        widget.onCameraPermissionDenied?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _body();
  }

  Widget _body() {
    return _liveFeedBody();
  }

  void _handleCameraZoomChange() {
    Timer.periodic(Duration(milliseconds: 20), (timer) {
      if (_controller == null || _controller?.value.isInitialized == false) {
        return;
      }
      if (zoomTarget != 0) {
        zoomLevel = zoomLevel + zoomTarget;

        if (zoomLevel < minZoomLevel) {
          zoomLevel = minZoomLevel;
        } else if (zoomLevel > min(maxZoomLevel, 3)) {
          zoomLevel = min(maxZoomLevel, 3);
        }
        _controller?.setZoomLevel(zoomLevel);
      }
    });
  }

  Widget _liveFeedBody() {
    return GestureDetector(
      child: _cameraBody(),
      onScaleUpdate: (ScaleUpdateDetails details) {
        double scale = details.scale;

        if (scale - _lastGestureScale > 0.005) {
          zoomTarget = 0.3;
        } else if (_lastGestureScale - scale > 0.005) {
          zoomTarget = -0.3;
        } else {
          zoomTarget = 0;
        }

        _lastGestureScale = scale;
      },
      onScaleEnd: (ScaleEndDetails details) {
        zoomTarget = 0;
        _lastGestureScale = 1;
      },
    );
  }

  Widget _cameraBody() {
    if (_controller == null || _controller?.value.isInitialized == false) {
      return const SizedBox.shrink();
    }

    final size = MediaQuery.of(context).size;
    // calculate scale depending on screen and camera ratios
    // this is actually size.aspectRatio / (1 / camera.aspectRatio)
    // because camera preview size is received as landscape
    // but we're calculating for portrait orientation
    var scale = 9 / 16;
    try {
      scale = size.aspectRatio * _controller!.value.aspectRatio;
    } catch (e) {
      print(e);
    }

    // to prevent scaling down, invert the value
    if (scale < 1) scale = 1 / scale;

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Transform.scale(
            scale: scale,
            child: Center(
              child: _changingCameraLens
                  ? Center(
                      child: const Text('Changing camera lens'),
                    )
                  : CameraPreview(_controller!),
            ),
          ),
          if (widget.customPaint != null) widget.customPaint!,
        ],
      ),
    );
  }

  Future _startLiveFeed() async {
    final camera = cameras[_cameraIndex];
    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _controller?.getMinZoomLevel().then((value) {
        zoomLevel = value;
        minZoomLevel = value;
      });
      _controller?.getMaxZoomLevel().then((value) {
        maxZoomLevel = value;
      });
      _controller?.startImageStream(_processCameraImage);

      _handleCameraZoomChange();
    });
  }

  Future _stopLiveFeed() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    _controller = null;
  }

  Future _switchLiveCamera() async {
    setState(() => _changingCameraLens = true);
    _cameraIndex = (_cameraIndex + 1) % cameras.length;

    await _stopLiveFeed();
    await _startLiveFeed();
    setState(() => _changingCameraLens = false);
  }

  Future _processCameraImage(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize =
        Size(image.width.toDouble(), image.height.toDouble());

    final camera = cameras[_cameraIndex];
    final imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (imageRotation == null) return;

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return;

    final planeData = image.planes.map(
      (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    final inputImage =
        InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);

    widget.onImage(inputImage);
  }

  Future<bool> requestPermission() async {
    PermissionStatus status = await Permission.camera.request();

    if (status == PermissionStatus.granted ||
        status == PermissionStatus.limited) {
      return Future.value(true);
    } else {
      print("@@@ QrScannerCameraPlusView.requestPermission(): ${status}");
      return Future.value(false);
    }
  }
}
