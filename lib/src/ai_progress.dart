import 'dart:async';

import 'package:flutter/material.dart';

const aiProgressZoneKey = #recipeAiProgress;

/// Each screen owns its progress; async zones carry it through existing request callbacks.
class AiRunProgress extends ValueNotifier<String?> {
  AiRunProgress() : super(null);
  bool _disposed = false;
  int _generation = 0;
  Future<T> run<T>(Future<T> Function() request) async {
    final generation = ++_generation;
    try {
      return await runZoned(
        request,
        zoneValues: {
          aiProgressZoneKey: (String message, int elapsed) {
            if (!_disposed && generation == _generation) {
              value = elapsed > 0 ? '$message ($elapsed s)' : message;
            }
          },
        },
      );
    } finally {
      if (!_disposed && generation == _generation) value = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AiProgressText extends StatelessWidget {
  const AiProgressText(this.progress, {super.key});
  final AiRunProgress progress;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: progress,
    builder: (context, message, _) => message == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Semantics(liveRegion: true, child: Text(message)),
          ),
  );
}
