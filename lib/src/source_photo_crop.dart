import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// Crop source imagery locally, without a generated-image API request.
Future<Map<String, dynamic>> prepareSourcePhoto(
  Map<String, dynamic> suggestion,
) async {
  ui.Codec? codec;
  ui.Image? source, cropped;
  ui.Picture? picture;
  try {
    final bytes = base64Decode(suggestion['image_base64'] as String);
    if (bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Source image is too large.');
    }
    codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 1600,
      allowUpscaling: false,
    );
    source = (await codec.getNextFrame()).image;
    final crop = suggestion['crop'] as Map;
    final left = (crop['left'] as num).toDouble(),
        top = (crop['top'] as num).toDouble();
    final right = (crop['right'] as num).toDouble(),
        bottom = (crop['bottom'] as num).toDouble();
    if (left < 0 ||
        top < 0 ||
        right > 1 ||
        bottom > 1 ||
        right <= left ||
        bottom <= top) {
      throw const FormatException('Invalid source crop.');
    }
    final rect = ui.Rect.fromLTRB(
      left * source.width,
      top * source.height,
      right * source.width,
      bottom * source.height,
    );
    final scale = math.min(1.0, 1024 / math.max(rect.width, rect.height));
    final width = math.max(1, (rect.width * scale).round()),
        height = math.max(1, (rect.height * scale).round());
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      rect,
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    picture = recorder.endRecording();
    cropped = await picture.toImage(width, height);
    final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
    if (png == null || png.lengthInBytes > 5 * 1024 * 1024) {
      throw const FormatException('Source image is too large.');
    }
    return {
      'image_base64': base64Encode(png.buffer.asUint8List()),
      'caption': suggestion['caption'] ?? 'Picture from imported recipe',
      'attribution': suggestion['attribution'] ?? 'From imported recipe',
    };
  } finally {
    codec?.dispose();
    source?.dispose();
    cropped?.dispose();
    picture?.dispose();
  }
}
