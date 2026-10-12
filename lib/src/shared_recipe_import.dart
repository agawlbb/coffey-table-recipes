import 'dart:async';

import 'package:better_share_handler/better_share_handler.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class SharedRecipeInput {
  const SharedRecipeInput({this.file, this.text, this.url, this.error});
  final XFile? file;
  final String? text, url, error;
}

/// Capture staging files immediately; authentication never discards pending shares.
class SharedRecipeInbox extends ValueNotifier<List<SharedRecipeInput>>
    with WidgetsBindingObserver {
  SharedRecipeInbox() : super([]);
  StreamSubscription<SharedMedia>? _subscription;
  Future<void> _delivery = Future.value();
  static const _iosInbox = MethodChannel('coffey_table_recipes/share_inbox');
  final _receivedIds = <String>{};
  bool _readingIOS = false;
  bool _observing = false;
  String? _lastIOSFailure;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _delivery = _delivery.then((_) => readSavedIOSShares());
    }
  }

  Future<void> readSavedIOSShares() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS || _readingIOS) {
      return;
    }
    _readingIOS = true;
    try {
      final entries =
          await _iosInbox.invokeListMethod<dynamic>('pending') ?? [];
      for (final entry in entries) {
        final item = Map<String, dynamic>.from(entry as Map);
        final id = item['id'] as String;
        if (!_receivedIds.contains(id)) {
          if (item['error'] is String) {
            _add(SharedRecipeInput(error: item['error'] as String));
          } else {
            await receive(
              SharedMedia(
                content: item['content'] as String?,
                attachments: (item['attachments'] as List).map((value) {
                  final attachment = value as Map;
                  return SharedAttachment(
                    path: attachment['path'] as String,
                    type: SharedAttachmentType.file,
                  );
                }).toList(),
              ),
            );
          }
          _receivedIds.add(id);
        }
        await _iosInbox.invokeMethod<void>('acknowledge', id);
      }
    } on MissingPluginException {
      // No native inbox is available; ordinary launch is not a recipe share.
    } catch (_) {
      if (_lastIOSFailure != 'storage') {
        _lastIOSFailure = 'storage';
        _add(
          const SharedRecipeInput(
            error: 'Could not read saved recipe shares. Try reopening the app.',
          ),
        );
      }
    } finally {
      _readingIOS = false;
    }
  }

  Future<void> start() async {
    if (kIsWeb ||
        ![
          TargetPlatform.android,
          TargetPlatform.iOS,
        ].contains(defaultTargetPlatform)) {
      return;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS && !_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      _iosInbox.setMethodCallHandler((call) async {
        if (call.method == 'changed') {
          _delivery = _delivery.then((_) => readSavedIOSShares());
          await _delivery;
        }
      });
      await readSavedIOSShares();
    }
    // iOS reads the App Group and document-opening inbox through the native
    // bridge on startup/resume. Android uses the share plugin's delivery stream.
    if (defaultTargetPlatform == TargetPlatform.iOS) return;
    final handler = ShareHandler.instance;
    _subscription = handler.sharedMediaStream.listen(
      (media) {
        _delivery = _delivery.then((_) => receive(media));
      },
      onError: (_) => _add(
        const SharedRecipeInput(
          error: 'Could not read the shared file. Try sharing it again.',
        ),
      ),
    );
    try {
      final initial = await handler.getInitialSharedMedia();
      if (initial != null) {
        await receive(initial);
        await handler.resetInitialSharedMedia();
      }
    } catch (_) {
      _add(
        const SharedRecipeInput(
          error: 'Could not read the shared file. Try sharing it again.',
        ),
      );
    }
  }

  void _add(SharedRecipeInput input) => value = [...value, input];
  SharedRecipeInput? take() {
    if (value.isEmpty) return null;
    final first = value.first;
    value = value.skip(1).toList();
    return first;
  }

  Future<void> receive(SharedMedia media) async {
    final attachments = (media.attachments ?? [])
        .whereType<SharedAttachment>()
        .toList();
    for (final attachment in attachments) {
      try {
        final source = XFile(attachment.path);
        if (await source.length() > 5 * 1024 * 1024) {
          _add(
            const SharedRecipeInput(
              error: 'Shared files must be at most 5 MB.',
            ),
          );
          continue;
        }
        final bytes = await source.readAsBytes();
        _add(
          SharedRecipeInput(
            file: XFile.fromData(bytes, name: source.name, path: source.name),
          ),
        );
      } catch (_) {
        _add(
          const SharedRecipeInput(
            error: 'Could not read the shared file. Try sharing it again.',
          ),
        );
      }
    }
    // A file caption should not become a second unrelated recipe.
    if (attachments.isEmpty && (media.content ?? '').trim().isNotEmpty) {
      final text = media.content!.trim();
      final uri = Uri.tryParse(text);
      if (uri != null &&
          uri.scheme == 'https' &&
          uri.host.isNotEmpty &&
          !text.contains(RegExp(r'\s'))) {
        _add(SharedRecipeInput(url: text));
      } else {
        _add(SharedRecipeInput(text: text));
      }
    }
  }

  @override
  void dispose() {
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _iosInbox.setMethodCallHandler(null);
    }
    _subscription?.cancel();
    super.dispose();
  }
}

final sharedRecipeInbox = SharedRecipeInbox();
