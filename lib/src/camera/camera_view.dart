import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';

import './focuspoint.dart';
import '../events.dart';

class CameraView extends StatefulWidget {
  CameraView(
      {Key? key,
      required this.customPaint,
      this.customPaint2,
      this.customPaint3,
      this.onCameraPermissionDenied,
      required this.onImage,
      this.initialDirection = CameraLensDirection.back})
      : super(key: key);

  final CustomPaint? customPaint;
  final CustomPaint? customPaint2;
  final CustomPaint? customPaint3;
  final Function(InputImage inputImage) onImage;
  final Function()? onCameraPermissionDenied;
  final CameraLensDirection initialDirection;

  setCameraFocusPoint(Offset offset) {
    eventBus.fire(SetFocusPointEvent(offset));
  }

  resetCameraFocusPoint() {
    eventBus.fire(ReSetFocusPointEvent());
  }

  zoomIn() {
    eventBus.fire(ZoomInEvent());
  }

  zoomOut() {
    eventBus.fire(ZoomOutEvent());
  }

  pausePreview() {
    eventBus.fire(PausePreviewEvent());
  }

  resumePreview() {
    eventBus.fire(ResumePreviewEvent());
  }

  @override
  _CameraViewState createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  List<CameraDescription> cameras = [];
  CameraController? cameraController;
  FocusPoint? focusPoint;

  int _cameraIndex = 0;
  double zoomLevel = 1, minZoomLevel = 1, maxZoomLevel = 1;
  double zoomTarget = 0, _lastGestureScale = 1;
  bool _changingCameraLens = false;
  bool paused = false;

  @override
  void initState() {
    super.initState();

    if (mounted) {
      _initCamera();

      eventBus.on<ZoomInEvent>().listen((e) async {
        if (mounted && cameraController?.value.isInitialized == true) {
          setState(() {
            zoomLevel += 0.4;
            if (zoomLevel < minZoomLevel) {
              zoomLevel = minZoomLevel;
            } else if (zoomLevel >= min(maxZoomLevel, 1.6)) {
              zoomLevel = min(maxZoomLevel, 1.6);
            }
            setZoomLevel(zoomLevel);
          });
        }
      });

      eventBus.on<PausePreviewEvent>().listen((e) async {
        if (mounted && cameraController?.value.isInitialized == true) {
          paused = true;
          cameraController?.pausePreview();
          focusPoint?.hide();
        }
      });

      eventBus.on<ResumePreviewEvent>().listen((e) async {
        if (mounted && cameraController?.value.isInitialized == true) {
          paused = false;
          cameraController?.resumePreview();
          focusPoint?.show();
        }
      });

      // Listen to background/resume changes
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void dispose() {
    // Remove background/resume changes listener
    WidgetsBinding.instance.removeObserver(this);

    if (cameraController?.value.isInitialized == true) {
      cameraController?.stopImageStream().then((value) {
        cameraController?.dispose();
      });
    }

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

  void setZoomLevel(double zoom) {
    if (mounted && cameraController?.value.isInitialized == true) {
      cameraController?.setZoomLevel(zoomLevel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
        children: [_liveFeedBody(), focusPoint ?? const SizedBox.shrink()]);
  }

  void _handleCameraZoomChange() {
    if (cameraController?.value.isInitialized == true) {
      Timer.periodic(const Duration(milliseconds: 20), (timer) {
        if (mounted) {
          if (zoomTarget != 0) {
            zoomLevel = zoomLevel + zoomTarget;

            if (zoomLevel < minZoomLevel) {
              zoomLevel = minZoomLevel;
            } else if (zoomLevel > min(maxZoomLevel, 3)) {
              zoomLevel = min(maxZoomLevel, 3);
            }
            setZoomLevel(zoomLevel);
          }
        }
      });
    }
  }

  Widget _liveFeedBody() {
    return GestureDetector(
        child: _cameraPreviewBody(),
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

          var offset = Offset(details.localPosition.dx / size.width,
              details.localPosition.dy / size.height);

          focusPoint?.setCameraFocusPoint(offset);
        });
  }

  Widget _cameraPreviewBody() {
    if (cameraController?.value.isInitialized == true) {
      final size = MediaQuery.of(context).size;
      // calculate scale depending on screen and camera ratios
      // this is actually size.aspectRatio / (1 / camera.aspectRatio)
      // because camera preview size is received as landscape
      // but we're calculating for portrait orientation
      var scale = 9 / 16;
      try {
        scale = size.aspectRatio * cameraController!.value.aspectRatio;
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
                    : CameraPreview(cameraController!),
              ),
            ),
            if (widget.customPaint != null) widget.customPaint!,
            if (widget.customPaint2 != null) widget.customPaint2!,
            if (widget.customPaint3 != null) widget.customPaint3!,
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
    cameraController = CameraController(
      camera,
      ResolutionPreset.veryHigh,
      enableAudio: false,
    );
    focusPoint = FocusPoint(cameraController!);

    cameraController?.initialize().then((_) {
      if (!mounted) {
        return;
      }
      cameraController?.getMinZoomLevel().then((value) {
        zoomLevel = value;
        minZoomLevel = value;
      });
      cameraController?.getMaxZoomLevel().then((value) {
        maxZoomLevel = value;
      });

      _handleCameraZoomChange();

      setState(() {});

      cameraController?.startImageStream(_processCameraImage);
    });
  }

  Future _processCameraImage(CameraImage image) async {
    if (paused) {
      return;
    }
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

    if (cameraController?.value.isInitialized == true) {
      if (state == AppLifecycleState.resumed) {
        if (cameraController?.value.isInitialized ?? false == false) {
          _initCamera();
        } else {
          cameraController?.resumePreview();
        }
      } else if (state == AppLifecycleState.paused) {
        cameraController?.pausePreview();
      }
    }
  }
}
