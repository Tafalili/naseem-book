import 'dart:async';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens the browser file picker for images.
Future<List<web.File>> pickImages({bool multiple = true}) => pickFiles(
    accept: 'image/jpeg,image/png,image/webp,image/heic,image/heif', multiple: multiple);

/// Opens the browser file picker.
Future<List<web.File>> pickFiles({required String accept, bool multiple = false}) {
  final c = Completer<List<web.File>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = accept
    ..multiple = multiple;
  void done() {
    if (c.isCompleted) return;
    final files = input.files;
    c.complete([
      if (files != null)
        for (var i = 0; i < files.length; i++) files.item(i)!,
    ]);
  }

  input.onchange = ((web.Event _) => done()).toJS;
  input.addEventListener('cancel', ((web.Event _) => done()).toJS);
  input.click();
  return c.future;
}

class CompressedPhoto {
  const CompressedPhoto(this.full, this.preview, this.width, this.height);
  final web.Blob full;
  final web.Blob preview;
  final int width, height;
}

/// Decodes with the browser (EXIF orientation applied), then re-encodes:
/// full ≤ 3000 px long side and ≤ ~1.5 MB; preview ≤ 1000 px for editing.
Future<CompressedPhoto> compressPhoto(web.File file,
    {int maxSide = 3000, int maxBytes = 1500000, int previewSide = 1000}) async {
  final url = web.URL.createObjectURL(file);
  try {
    final img = web.HTMLImageElement()..src = url;
    await img.decode().toDart;
    final w0 = img.naturalWidth, h0 = img.naturalHeight;

    var side = math.min(maxSide, math.max(w0, h0));
    web.Blob? full;
    var w = 0, h = 0;
    for (var attempt = 0; attempt < 6; attempt++) {
      final k = side / math.max(w0, h0);
      w = (w0 * k).round();
      h = (h0 * k).round();
      final canvas = _draw(img, w, h);
      for (final q in const [.9, .85, .8, .72]) {
        full = await _toJpeg(canvas, q);
        if (full.size <= maxBytes) break;
      }
      if (full!.size <= maxBytes) break;
      side = (side * .85).round();
    }

    final pk = math.min(1.0, previewSide / math.max(w, h));
    final preview = await _toJpeg(_draw(img, (w * pk).round(), (h * pk).round()), .8);
    return CompressedPhoto(full!, preview, w, h);
  } finally {
    web.URL.revokeObjectURL(url);
  }
}

web.HTMLCanvasElement _draw(web.HTMLImageElement img, int w, int h) {
  final canvas = web.HTMLCanvasElement()
    ..width = w
    ..height = h;
  final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(img, 0, 0, w, h);
  return canvas;
}

Future<web.Blob> _toJpeg(web.HTMLCanvasElement canvas, double quality) {
  final c = Completer<web.Blob>();
  canvas.toBlob(
    ((web.Blob? b) => b == null ? c.completeError(StateError('encode failed')) : c.complete(b))
        .toJS,
    'image/jpeg',
    quality.toJS,
  );
  return c.future;
}

/// Reads a Blob (or File) into memory.
Future<Uint8List> blobBytes(web.Blob b) async =>
    (await b.arrayBuffer().toDart).toDart.asUint8List();

/// Encodes a canvas as JPEG with the browser's encoder.
Future<web.Blob> canvasToJpeg(web.HTMLCanvasElement canvas, double quality) => _toJpeg(canvas, quality);
