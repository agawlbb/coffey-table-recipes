import 'child_mode.dart';

import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pasteboard/pasteboard.dart';

import 'shopping_photo_paste_stub.dart'
    if (dart.library.js_interop) 'shopping_photo_paste_web.dart';

enum ShoppingPhotoSource { camera, file, clipboard }

Future<Uint8List?> pickShoppingPhoto(
  BuildContext context,
  ShoppingPhotoSource source,
) async {
  if (source == ShoppingPhotoSource.clipboard) {
    if (kIsWeb) {
      return showDialog<Uint8List>(
        context: context,
        builder: (_) => const _PastePhotoDialog(),
      );
    }
    return _readClipboard();
  }
  final XFile? file;
  if (source == ShoppingPhotoSource.camera) {
    file = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
  } else {
    file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(
          label: 'Images',
          extensions: ['jpg', 'jpeg', 'png', 'webp'],
          mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
          uniformTypeIdentifiers: [
            'public.jpeg',
            'public.png',
            'org.webmproject.webp',
          ],
        ),
      ],
    );
  }
  if (file == null) return null;
  if (await file.length() > 5 * 1024 * 1024) {
    throw const FormatException('Choose an image of at most 5 MB.');
  }
  return file.readAsBytes();
}

Future<Uint8List> _readClipboard() async {
  final bytes = await Pasteboard.image;
  if (bytes == null || bytes.isEmpty) {
    throw const FormatException(
      'No image was available. Copy an image and allow clipboard access, or use your browser’s Paste command.',
    );
  }
  if (bytes.length > 5 * 1024 * 1024) {
    throw const FormatException('Choose an image of at most 5 MB.');
  }
  return bytes;
}

class _PastePhotoDialog extends StatefulWidget {
  const _PastePhotoDialog();
  @override
  State<_PastePhotoDialog> createState() => _PastePhotoDialogState();
}

class _PastePhotoDialogState extends State<_PastePhotoDialog> {
  String? _error;
  bool _reading = false;
  VoidCallback? _stopListening;

  @override
  void initState() {
    super.initState();
    _stopListening = listenForPhotoPaste((image) {
      if (_reading) {
        image.ignore();
      } else {
        _read(() => image);
      }
    });
  }

  Future<void> _read(Future<Uint8List> Function() read) async {
    setState(() => _reading = true);
    try {
      final bytes = await read();
      if (mounted) Navigator.pop(context, bytes);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : 'Clipboard access was denied. Use your browser’s Paste command.',
        );
      }
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  @override
  void dispose() {
    _stopListening?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Paste image'),
    content: Text(
      _error ?? 'Use Ctrl+V, Command+V or your browser’s Paste command, or tap Paste from clipboard.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _reading ? null : () => _read(_readClipboard),
        child: const Text('Paste from clipboard'),
      ),
    ],
  );
}

class ShoppingPhotoViewer extends StatefulWidget {
  const ShoppingPhotoViewer({super.key, required this.load, this.onDelete});
  final Future<Map<String, dynamic>> Function() load;
  final Future<bool> Function()? onDelete;
  @override
  State<ShoppingPhotoViewer> createState() => _ShoppingPhotoViewerState();
}

class _ShoppingPhotoViewerState extends State<ShoppingPhotoViewer> {
  late Future<Uint8List> _photo = _load();
  Future<Uint8List> _load() async =>
      base64Decode((await widget.load())['image_base64'] as String);

  bool _deleting = false;
  Future<void> _delete() async {
    if (_deleting || childMode.value) return;
    setState(() => _deleting = true);
    try {
      if (await widget.onDelete!()) {
        if (mounted) Navigator.pop(context);
      } else {
        throw StateError('Photo removal failed');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete photo. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Shopping item photo'),
      actions: [
        if (widget.onDelete != null && !childModeOf(context))
          IconButton(
            tooltip: 'Delete photo',
            onPressed: _deleting ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: FutureBuilder<Uint8List>(
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () {
                final photo = _load();
                setState(() {
                  _photo = photo;
                });
              },
              child: const Text('Could not load photo. Tap to retry.'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(
              snapshot.data!,
              semanticLabel: 'Shopping item photo',
              errorBuilder: (_, error, stack) =>
                  const Text('This photo could not be opened.'),
            ),
          ),
        );
      },
    ),
  );
}
