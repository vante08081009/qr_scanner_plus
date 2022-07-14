import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';

class QrScannerCameraPlusView extends StatefulWidget {
  const QrScannerCameraPlusView(
      {Key? key,
      required this.customPaint,
      this.onCameraPermissionDenied,
      required this.onImage,
      this.initialDirection = CameraLensDirection.back})
      : super(key: key);

  final CustomPaint? customPaint;
  final Function(InputImage inputImage) onImage;
  final Function()? onCameraPermissionDenied;
  final CameraLensDirection initialDirection;

  @override
  _CameraViewState createState() => _CameraViewState();
}

class _CameraViewState extends State<QrScannerCameraPlusView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  File? _image;
  String? _path;
  List<CameraDescription> cameras = [];

  int _cameraIndex = 0;
  double zoomLevel = 1, minZoomLevel = 1, maxZoomLevel = 1;
  double zoomTarget = 0, _lastGestureScale = 1;
  final bool _allowPicker = true;
  bool _changingCameraLens = false;
  Timer? _resetFocusModeTimer;
  bool _waitResetFucusMode = false;
  AccelerometerEvent? _lastAccelerometerEvent;

  @override
  void initState() {
    super.initState();

    if (mounted) {
      _initCamera();

      // Listen to background/resume changes
      WidgetsBinding.instance?.addObserver(this);
    }
  }

  @override
  void dispose() {
    _stopLiveFeed();

    // Remove background/resume changes listener
    WidgetsBinding.instance?.removeObserver(this);

    super.dispose();
  }

  Future _initCamera() async {
    return requestPermission().then((isGranted) {
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

  void _handleSetFocusPoint(Offset? point) async {
    _controller?.setFocusMode(FocusMode.locked);
    _controller?.setFocusPoint(point);

    //Switch back to auto-focus after 20 seconds.
    _resetFocusModeTimer?.cancel();
    _waitResetFucusMode = true;
    _resetFocusModeTimer = Timer(const Duration(seconds: 20), () {
      _waitResetFucusMode = false;
      print("Reset focus mode");
      _controller?.setFocusMode(FocusMode.auto);
    });
  }

  void _autoResetFocusModeByAccelerometer() {
    //If the user has moved the phone (calc by accelerometer values), switch back to auto-focus.

    accelerometerEvents.listen((AccelerometerEvent event) {
      if (_lastAccelerometerEvent != null) {
        var diff = (event.x * event.y * event.z -
                _lastAccelerometerEvent!.x *
                    _lastAccelerometerEvent!.y *
                    _lastAccelerometerEvent!.z) *
            100 ~/
            100;
        if (diff.abs() > 10) {
          if (_resetFocusModeTimer?.isActive == true &&
              _waitResetFucusMode == true) {
            _resetFocusModeTimer?.cancel();
            print("Reset focus mode");
            _controller?.setFocusMode(FocusMode.auto);

            _waitResetFucusMode = false;
          }
        }
      }
      _lastAccelerometerEvent = event;
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
        onTapDown: (TapDownDetails details) {
          final size = MediaQuery.of(context).size;

          var offset = Offset(details.localPosition.dx / size.width,
              details.localPosition.dy / size.height);

          _handleSetFocusPoint(offset);
        });
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
    } catch (e) {}

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
    if (!mounted) {
      return;
    }

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
      _autoResetFocusModeByAccelerometer();
    });
  }

  Future _stopLiveFeed() async {
    if (!mounted) {
      return;
    }
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    print("@@@ didChangeAppLifecycleState {$state}");

    if (_controller?.value.isInitialized == true) {
      if (state == AppLifecycleState.resumed) {
        _controller?.resumePreview();
      } else if (state == AppLifecycleState.paused) {
        _controller?.pausePreview();
      }
    }
  }
}
