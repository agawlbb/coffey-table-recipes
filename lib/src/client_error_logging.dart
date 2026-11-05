import 'package:flutter/foundation.dart';

import 'client_log.dart';

/// Preserve Flutter/platform error handling; diagnostics do not suppress errors.
void installClientErrorLogging({ClientLog? log}) {
  final target = log ?? clientLog;
  final flutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    target.record(
      'flutter',
      'uncaught_error',
      error: details.exception,
      stack: details.stack,
    );
    flutterHandler?.call(details);
  };
  final platformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    target.record('platform', 'uncaught_error', error: error, stack: stack);
    return platformHandler?.call(error, stack) ?? false;
  };
}
