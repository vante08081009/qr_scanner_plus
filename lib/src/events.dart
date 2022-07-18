import 'package:flutter/material.dart';
import 'package:event_bus/event_bus.dart';

EventBus eventBus = EventBus();

class FocusPointEvent {
  Offset offset;

  FocusPointEvent(this.offset);
}
