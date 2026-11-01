import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

// Only installed while the explicit Paste image dialog is open. Text paste in
// the item and note fields therefore keeps its normal browser behavior.
VoidCallback listenForPhotoPaste(void Function(Future<Uint8List>) onImage) {
  final listener = ((web.Event event) {
    final clipboard = (event as web.ClipboardEvent).clipboardData;
    final files = clipboard?.files;
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null || !file.type.startsWith('image/')) continue;
      event.preventDefault();
      onImage(_bytes(file));
      return;
    }
  }).toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

Future<Uint8List> _bytes(web.File file) async {
  if (file.size > 5 * 1024 * 1024) {
    throw const FormatException('Choose an image of at most 5 MB.');
  }
  return (await file.arrayBuffer().toDart).toDart.asUint8List();
}
