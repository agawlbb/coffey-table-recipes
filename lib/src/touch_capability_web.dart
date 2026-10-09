import 'dart:js_interop';

@JS('navigator.maxTouchPoints')
external int get _maxTouchPoints;

// Includes hybrid laptops, not just browsers identifying as phones.
bool deviceSupportsTouch() => _maxTouchPoints > 0;
