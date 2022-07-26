import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../events.dart';

class FocusPoint extends StatefulWidget {
  CameraController cameraController;
  FocusPoint(this.cameraController, {Key? key}) : super(key: key);
  bool _hide = false;

  setCameraFocusPoint(Offset offset) {
    eventBus.fire(SetFocusPointEvent(offset));
  }

  resetFocusPoint() {
    if (cameraController.value.isInitialized == true) {
      print("@@@ resetFocusPoint");
      cameraController.setFocusMode(FocusMode.auto);
    }
  }

  hide() {
    _hide = true;
  }

  @override
  State<FocusPoint> createState() => _FocusPointState();
}

class _FocusPointState extends State<FocusPoint> {
  Offset _lastFocusPoint = Offset.zero;
  double _focusPointAnimationOpacity = 0.0;
  AccelerometerEvent? _lastAccelerometerEvent;
  bool _needAutoResetFocusPoint = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _lastFocusPoint.dx - 32,
      top: _lastFocusPoint.dy - 32,
      child: widget._hide
          ? const SizedBox.shrink()
          : IgnorePointer(
              child: AnimatedOpacity(
                  opacity: _focusPointAnimationOpacity,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.linear,
                  child: const Image(
                      image: AssetImage('assets/images/focus.png',
                          package: 'qr_scanner_plus'),
                      width: 64,
                      height: 64,
                      fit: BoxFit.contain))),
    );
  }

  @override
  void initState() {
    super.initState();

    _listenFocusPointEvent();
    _autoResetFocusModeByAccelerometer();
  }

  _listenFocusPointEvent() {
    eventBus.on<SetFocusPointEvent>().listen((e) async {
      if (_busy == true) {
        return;
      }
      _busy = true;

      Offset offset = e.offset;

      final size = MediaQuery.of(context).size;

      _lastFocusPoint = Offset(offset.dx * size.width, offset.dy * size.height);

      await _setFocusPoint(offset);
      _busy = false;
    });
  }

  _setFocusPoint(Offset? point) async {
    if (widget.cameraController.value.isInitialized == true) {
      await widget.cameraController.setFocusMode(FocusMode.locked);
      await widget.cameraController.setFocusPoint(point);

      _needAutoResetFocusPoint = false;
      Future.delayed(const Duration(milliseconds: 5000), () {
        _needAutoResetFocusPoint = true;
      });

      _playAnimation();
    }
  }

  _playAnimation({int loop = 3}) async {
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

    if (mounted) {
      setState(() {
        _focusPointAnimationOpacity = 0;
      });
    }
  }

  _autoResetFocusModeByAccelerometer() {
    if (widget.cameraController.value.isInitialized == true) {
      //If the user has moved the phone (calc by accelerometer values), switch back to auto-focus.

      accelerometerEvents.listen((AccelerometerEvent event) {
        if (_lastAccelerometerEvent != null) {
          var diff = (event.x * event.y * event.z -
                  _lastAccelerometerEvent!.x *
                      _lastAccelerometerEvent!.y *
                      _lastAccelerometerEvent!.z) *
              100 ~/
              100;

          if (_needAutoResetFocusPoint == true && diff.abs() > 10) {
            widget.resetFocusPoint();
            _needAutoResetFocusPoint = false;
          }
        }

        _lastAccelerometerEvent = event;
      });
    }
  }
}
