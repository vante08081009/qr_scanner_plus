import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:event_bus/event_bus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import '../events.dart';

class CameraView extends StatefulWidget {
  CameraView(
      {Key? key,
      required this.customPaint,
      this.customPaint2,
      this.onCameraPermissionDenied,
      required this.onImage,
      this.initialDirection = CameraLensDirection.back})
      : super(key: key);

  final CustomPaint? customPaint;
  final CustomPaint? customPaint2;
  final Function(InputImage inputImage) onImage;
  final Function()? onCameraPermissionDenied;
  final CameraLensDirection initialDirection;

  setCameraFocusPoint(Offset offset) {
    eventBus.fire(FocusPointEvent(offset));
  }

  stopPreview() {
    eventBus.fire(StopPreviewEvent());
  }

  @override
  _CameraViewState createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  CameraController? _cameraController;
  File? _image;
  String? _path;
  Offset _lastFocusPoint = Offset.zero;
  List<CameraDescription> cameras = [];

  int _cameraIndex = 0;
  double zoomLevel = 1, minZoomLevel = 1, maxZoomLevel = 1;
  double zoomTarget = 0, _lastGestureScale = 1;
  final bool _allowPicker = true;
  bool _changingCameraLens = false;
  Timer? _resetFocusModeTimer;
  bool _waitResetFucusMode = false;
  AccelerometerEvent? _lastAccelerometerEvent;
  double _focusPointAnimationOpacity = 0.0;

  @override
  void initState() {
    super.initState();

    if (mounted) {
      _initCamera();

      eventBus.on<FocusPointEvent>().listen((e) {
        Offset offset = e.offset;

        final size = MediaQuery.of(context).size;

        _lastFocusPoint =
            Offset(offset.dx * size.width, offset.dy * size.height);

        _handleSetFocusPoint(offset);
      });

      eventBus.on<StopPreviewEvent>().listen((e) {
        _stopLiveFeed();
      });

      // Listen to background/resume changes
      WidgetsBinding.instance?.addObserver(this);
    }
  }

  @override
  void dispose() {
    _resetFocusModeTimer?.cancel();

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
    return Stack(children: [_body(), _focusPoint()]);
  }

  Widget _focusPoint() {
    return Positioned(
      left: _lastFocusPoint.dx - 32,
      top: _lastFocusPoint.dy - 32,
      child: AnimatedOpacity(
          opacity: _focusPointAnimationOpacity,
          duration: const Duration(milliseconds: 200),
          curve: Curves.linear,
          child: const Image(
              image: AssetImage('assets/images/focus.png',
                  package: 'qr_scanner_plus'),
              width: 64,
              height: 64,
              fit: BoxFit.contain)),
    );
  }

  Widget _body() {
    return _liveFeedBody();
  }

  void _handleCameraZoomChange() {
    if (_cameraController?.value.isInitialized == true) {
      Timer.periodic(Duration(milliseconds: 20), (timer) {
        if (zoomTarget != 0) {
          zoomLevel = zoomLevel + zoomTarget;

          if (zoomLevel < minZoomLevel) {
            zoomLevel = minZoomLevel;
          } else if (zoomLevel > min(maxZoomLevel, 3)) {
            zoomLevel = min(maxZoomLevel, 3);
          }
          _cameraController?.setZoomLevel(zoomLevel);
        }
      });
    }
  }

  void _resetFocusPoint() async {
    _cameraController?.setFocusMode(FocusMode.auto);
  }

  void _handleSetFocusPoint(Offset? point) async {
    if (_cameraController?.value.isInitialized == true) {
      _cameraController?.setFocusMode(FocusMode.locked);
      _cameraController?.setFocusPoint(point);

      //Switch back to auto-focus after 20 seconds.
      _resetFocusModeTimer?.cancel();
      _waitResetFucusMode = true;
      _resetFocusModeTimer = Timer(const Duration(seconds: 20), () {
        _waitResetFucusMode = false;
        print("Reset focus mode");

        _resetFocusPoint();
      });

      _playFocusPointAnimation();
    }
  }

  void _autoResetFocusModeByAccelerometer() {
    if (_cameraController?.value.isInitialized == true) {
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
              _resetFocusPoint();

              _waitResetFucusMode = false;
            }
          }
        }
        _lastAccelerometerEvent = event;
      });
    }
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
        onTapUp: (TapUpDetails details) {
          final size = MediaQuery.of(context).size;

          setState(() {
            _lastFocusPoint = details.localPosition;
          });

          var offset = Offset(details.localPosition.dx / size.width,
              details.localPosition.dy / size.height);

          _handleSetFocusPoint(offset);
        });
  }

  Widget _cameraBody() {
    if (_cameraController?.value.isInitialized == true) {
      final size = MediaQuery.of(context).size;
      // calculate scale depending on screen and camera ratios
      // this is actually size.aspectRatio / (1 / camera.aspectRatio)
      // because camera preview size is received as landscape
      // but we're calculating for portrait orientation
      var scale = 9 / 16;
      try {
        scale = size.aspectRatio * _cameraController!.value.aspectRatio;
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
                    ? Container(
                        color: Colors.black,
                        child: const Center(
                            child: CircularProgressIndicator(
                          color: Colors.white30,
                        )))
                    : CameraPreview(_cameraController!),
              ),
            ),
            if (widget.customPaint != null) widget.customPaint!,
            if (widget.customPaint2 != null) widget.customPaint2!,
          ],
        ),
      );
    } else {
      return SizedBox.expand(
          child: Container(
              color: Colors.black,
              child: const Center(
                  child: CircularProgressIndicator(
                color: Colors.white30,
              ))));
    }
  }

  Future _startLiveFeed() async {
    if (!mounted) {
      return;
    }

    final camera = cameras[_cameraIndex];
    _cameraController = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _cameraController?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      _cameraController?.getMinZoomLevel().then((value) {
        zoomLevel = value;
        minZoomLevel = value;
      });
      _cameraController?.getMaxZoomLevel().then((value) {
        maxZoomLevel = value;
      });
      _cameraController?.startImageStream(_processCameraImage);

      _handleCameraZoomChange();
      _autoResetFocusModeByAccelerometer();
    });
  }

  Future _stopLiveFeed() async {
    try {
      await _cameraController?.stopImageStream();
      await _cameraController?.dispose();
    } catch (err) {}
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

  Future<void> _playFocusPointAnimation({int loop = 2}) async {
    for (var i = 0; i < loop; i++) {
      await Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _focusPointAnimationOpacity = 0.5;
          });
        }
      });
      await Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _focusPointAnimationOpacity = 0.8;
          });
        }
      });
    }

    await Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _focusPointAnimationOpacity = 0;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);

    print("@@@ didChangeAppLifecycleState {$state}");

    if (_cameraController?.value.isInitialized == true) {
      if (state == AppLifecycleState.resumed) {
        if (_cameraController?.value.isInitialized ?? false == false) {
          _initCamera();
        } else {
          _cameraController?.resumePreview();
        }
      } else if (state == AppLifecycleState.paused) {
        _cameraController?.pausePreview();
      }
    }
  }
}
