import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Render locally: crop is relative to the input image, then rotate and flip.
Future<ui.Image> transformRecipeImage(
  ui.Image image, {
  Rect crop = const Rect.fromLTRB(0, 0, 1, 1),
  int turns = 0,
  bool flip = false,
  int? longestSide,
}) async {
  final scale = longestSide == null
      ? 1.0
      : math.min(
          1.0,
          longestSide /
              math.max(image.width * crop.width, image.height * crop.height),
        );
  final width = math.max(1, (image.width * crop.width * scale).round());
  final height = math.max(1, (image.height * crop.height * scale).round());
  final rotation = turns % 4;
  final outWidth = rotation.isOdd ? height : width;
  final outHeight = rotation.isOdd ? width : height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.translate(outWidth / 2, outHeight / 2);
  if (flip) canvas.scale(-1, 1);
  canvas.rotate(rotation * math.pi / 2);
  canvas.drawImageRect(
    image,
    Rect.fromLTRB(
      crop.left * image.width,
      crop.top * image.height,
      crop.right * image.width,
      crop.bottom * image.height,
    ),
    Rect.fromLTWH(-width / 2, -height / 2, width.toDouble(), height.toDouble()),
    Paint()
      ..filterQuality = scale < 1 ? FilterQuality.medium : FilterQuality.none,
  );
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(outWidth, outHeight);
  } finally {
    picture.dispose();
  }
}

class RecipeImageEditor extends StatefulWidget {
  const RecipeImageEditor({super.key, required this.bytes});
  final Uint8List bytes;
  @override
  State<RecipeImageEditor> createState() => _RecipeImageEditorState();
}

class _RecipeImageEditorState extends State<RecipeImageEditor> {
  ui.Image? _original, _image;
  Rect _crop = const Rect.fromLTRB(0, 0, 1, 1);
  bool _busy = true;
  String? _error;
  int _corner = 0;
  int _longestSide = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(widget.bytes);
      final image = (await codec.getNextFrame()).image;
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _original = _image = image;
        _busy = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'This image could not be opened.';
          _busy = false;
        });
      }
    } finally {
      codec?.dispose();
    }
  }

  @override
  void dispose() {
    if (_image != _original) _image?.dispose();
    _original?.dispose();
    super.dispose();
  }

  Future<void> _transform({int turns = 0, bool flip = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final edited = await transformRecipeImage(
        _image!,
        turns: turns,
        flip: flip,
      );
      if (!mounted) {
        edited.dispose();
        return;
      }
      final old = _image;
      final selection = _crop;
      var crop = switch (turns % 4) {
        1 => Rect.fromLTRB(
          1 - selection.bottom,
          selection.left,
          1 - selection.top,
          selection.right,
        ),
        2 => Rect.fromLTRB(
          1 - selection.right,
          1 - selection.bottom,
          1 - selection.left,
          1 - selection.top,
        ),
        3 => Rect.fromLTRB(
          selection.top,
          1 - selection.right,
          selection.bottom,
          1 - selection.left,
        ),
        _ => selection,
      };
      if (flip) {
        crop = Rect.fromLTRB(
          1 - crop.right,
          crop.top,
          1 - crop.left,
          crop.bottom,
        );
      }
      setState(() {
        _image = edited;
        _crop = crop;
      });
      if (old != _original) old?.dispose();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not edit this picture. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() {
    final old = _image;
    setState(() {
      _image = _original;
      _longestSide = 0;
      _crop = const Rect.fromLTRB(0, 0, 1, 1);
      _error = null;
    });
    if (old != _original) old?.dispose();
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    ui.Image? cropped;
    try {
      cropped = await transformRecipeImage(
        _image!,
        crop: _crop,
        longestSide: _longestSide == 0 ? null : _longestSide,
      );
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes > 5 * 1024 * 1024) {
        throw const FormatException(
          'The edited image exceeds 5 MB. Choose a smaller image size or crop a smaller area.',
        );
      }
      if (mounted) {
        Navigator.pop(
          context,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException
              ? error.message
              : 'Could not save this edit. Try again.',
        );
      }
    } finally {
      cropped?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _drag(Offset point, Size size) {
    final x = (point.dx / size.width).clamp(0.0, 1.0);
    final y = (point.dy / size.height).clamp(0.0, 1.0);
    setState(() {
      _crop = Rect.fromLTRB(
        _corner % 2 == 0 ? x.clamp(0.0, _crop.right - .02) : _crop.left,
        _corner < 2 ? y.clamp(0.0, _crop.bottom - .02) : _crop.top,
        _corner % 2 == 1 ? x.clamp(_crop.left + .02, 1.0) : _crop.right,
        _corner >= 2 ? y.clamp(_crop.top + .02, 1.0) : _crop.bottom,
      );
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Edit picture')),
    body: SafeArea(
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final image = _image;
                  if (image == null) return const SizedBox.shrink();
                  final scale = math.min(
                    constraints.maxWidth / image.width,
                    constraints.maxHeight / image.height,
                  );
                  final size = Size(image.width * scale, image.height * scale);
                  return Center(
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: GestureDetector(
                        onPanStart: _busy
                            ? null
                            : (details) {
                                final point = details.localPosition;
                                final corners = [
                                  _crop.topLeft,
                                  _crop.topRight,
                                  _crop.bottomLeft,
                                  _crop.bottomRight,
                                ];
                                double distance = double.infinity;
                                for (var i = 0; i < corners.length; i++) {
                                  final delta =
                                      (Offset(
                                                corners[i].dx * size.width,
                                                corners[i].dy * size.height,
                                              ) -
                                              point)
                                          .distance;
                                  if (delta < distance) {
                                    distance = delta;
                                    _corner = i;
                                  }
                                }
                              },
                        onPanUpdate: _busy
                            ? null
                            : (details) => _drag(details.localPosition, size),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            RawImage(image: image, fit: BoxFit.fill),
                            CustomPaint(painter: _CropPainter(_crop)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Drag the corners to crop.'),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              IconButton(
                tooltip: 'Rotate left',
                onPressed: _busy || _image == null
                    ? null
                    : () => _transform(turns: 3),
                icon: const Icon(Icons.rotate_left),
              ),
              IconButton(
                tooltip: 'Rotate right',
                onPressed: _busy || _image == null
                    ? null
                    : () => _transform(turns: 1),
                icon: const Icon(Icons.rotate_right),
              ),
              IconButton(
                tooltip: 'Flip horizontally',
                onPressed: _busy || _image == null
                    ? null
                    : () => _transform(flip: true),
                icon: const Icon(Icons.flip),
              ),
              TextButton(
                onPressed: _busy || _image == null ? null : _reset,
                child: const Text('Reset'),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<int>(
              isExpanded: true,
              value: _longestSide,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _longestSide = value!),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Original image size')),
                DropdownMenuItem(
                  value: 2048,
                  child: Text('Resize: longest side 2048 px'),
                ),
                DropdownMenuItem(
                  value: 1600,
                  child: Text('Resize: longest side 1600 px'),
                ),
                DropdownMenuItem(
                  value: 1024,
                  child: Text('Resize: longest side 1024 px'),
                ),
                DropdownMenuItem(
                  value: 800,
                  child: Text('Resize: longest side 800 px'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: _busy || _image == null ? null : _apply,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.crop);
  final Rect crop;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      crop.left * size.width,
      crop.top * size.height,
      crop.right * size.width,
      crop.bottom * size.height,
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(shade, Paint()..color = Colors.black54);
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight,
    ]) {
      canvas.drawCircle(corner, 8, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) => crop != oldDelegate.crop;
}
