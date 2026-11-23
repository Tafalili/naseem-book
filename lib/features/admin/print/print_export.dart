import 'dart:convert';
import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/page_template.dart';
import '../../editor/draft/image_tools.dart';
import '../data/admin_repository.dart';
import '../../../core/theme/lazy_fonts.dart';

/// Print geometry at 300 DPI, matching the store's own A4 files:
/// pages are 186×276 mm, odd pages flush right and even pages flush left
/// (mirrored for duplex), both flush bottom; the front cover sits inside a
/// 5 mm white border.
abstract final class PrintSheet {
  static const dpi = 300;
  static const k = dpi / 25.4; // px per mm
  static const a4W = 2480, a4H = 3508;
  static const pageW = 2197, pageH = 3260;
  static const coverMargin = 59; // 5 mm

  /// Top-left of the artwork on the A4 sheet.
  static ui.Offset origin(PageTemplate t) {
    if (t.isCover) return const ui.Offset(coverMargin + .0, coverMargin + .0);
    final x = t.pageNumber.isOdd ? a4W - pageW : 0;
    return ui.Offset(x.toDouble(), (a4H - pageH).toDouble());
  }

  static String fileName(PageTemplate t) => t.isCover
      ? '00_cover_front.jpg'
      : 'p${t.pageNumber.toString().padLeft(2, '0')}_${t.pageNumber.isOdd ? 'right' : 'left'}.jpg';
}

/// What one book needs to be drawn.
class PrintBook {
  PrintBook({required this.book, required this.templates, required this.photos, required this.backgrounds});
  final AdminBook book;
  final List<PageTemplate> templates;
  final Map<String, ui.Image> photos; // storage path -> image
  final Map<String, ui.Image> backgrounds; // template id -> image
}

double _rad(double deg) => deg * math.pi / 180;

/// Draws one A4 sheet. Mirrors the editor's PageCanvas so print = preview.
Future<ui.Image> renderSheet(PrintBook pb, PageTemplate t) async {
  const k = PrintSheet.k;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(const ui.Rect.fromLTWH(0, 0, PrintSheet.a4W + .0, PrintSheet.a4H + .0), ui.Paint()..color = const ui.Color(0xFFFFFFFF));

  final w = t.widthMm * k, h = t.heightMm * k;
  final o = PrintSheet.origin(t);
  c.save();
  c.translate(o.dx, o.dy);
  c.clipRect(ui.Rect.fromLTWH(0, 0, w, h));
  final hi = ui.Paint()..filterQuality = ui.FilterQuality.high;

  final bg = pb.backgrounds[t.id];
  if (bg != null) {
    c.drawImageRect(bg, ui.Rect.fromLTWH(0, 0, bg.width + .0, bg.height + .0), ui.Rect.fromLTWH(0, 0, w, h), hi);
  }

  final page = pb.book.pages.where((p) => p.pageNumber == t.pageNumber).firstOrNull;

  void inBox(double x, double y, double bw, double bh, double rot, void Function(double sw, double sh) draw) {
    final sw = bw * k, sh = bh * k;
    c.save();
    c.translate((x + bw / 2) * k, (y + bh / 2) * k);
    if (rot != 0) c.rotate(_rad(rot));
    c.translate(-sw / 2, -sh / 2);
    draw(sw, sh);
    c.restore();
  }

  // photos
  for (final s in t.photoSlots) {
    final path = page?.slots[s.id];
    final img = path == null ? null : pb.photos[path];
    if (img == null) continue;
    final tr = page!.transforms[s.id] ?? (scale: 1.0, dx: 0.0, dy: 0.0);
    inBox(s.x, s.y, s.w, s.h, s.rotation, (sw, sh) {
      final box = ui.Rect.fromLTWH(0, 0, sw, sh);
      switch (s.shape) {
        case SlotShape.ellipse:
          c.clipPath(ui.Path()..addOval(box));
        case SlotShape.rounded:
          c.clipRRect(ui.RRect.fromRectAndRadius(box, ui.Radius.circular(s.radius * k)));
        case SlotShape.rect:
          c.clipRect(box);
      }
      final base = math.max(sw / img.width, sh / img.height);
      final dw = img.width * base * tr.scale, dh = img.height * base * tr.scale;
      final left = (sw - dw) / 2 + tr.dx * sw, top = (sh - dh) / 2 + tr.dy * sh;
      c.drawImageRect(img, ui.Rect.fromLTWH(0, 0, img.width + .0, img.height + .0),
          ui.Rect.fromLTWH(left, top, dw, dh), hi);
    });
  }

  // texts
  final cover = pb.book.cover;
  final name = pb.book.childName;
  for (final ts in t.textSlots) {
    if (ts.kind == TextKind.childName) {
      if (name.isEmpty) continue;
      inBox(ts.x, ts.y, ts.w, ts.h, ts.rotation, (sw, sh) {
        final tp = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(
              fontFamily: t.isCover ? ((cover['font'] as String?) ?? NFonts.ruqaa) : NFonts.naskh,
              fontSize: ts.fontSizeMm * k,
              height: 1.25,
              color: t.isCover ? ui.Color(((cover['color'] as num?) ?? 0xFF2B2B2B).toInt()) : NColors.ink,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        )..layout();
        // FittedBox(scaleDown): shrink to fit, never enlarge
        final f = math.min(1.0, math.min(sw / tp.width, sh / tp.height));
        c.translate(sw / 2, sh / 2);
        c.scale(f);
        tp.paint(c, ui.Offset(-tp.width / 2, -tp.height / 2));
      });
    } else {
      final text = page?.texts[ts.id];
      if (text == null || text.trim().isEmpty) continue;
      inBox(ts.x, ts.y, ts.w, ts.h, ts.rotation, (sw, sh) {
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontFamily: NFonts.naskh,
              fontSize: ts.fontSizeMm * k,
              height: ts.h / ts.lines / ts.fontSizeMm,
              color: NColors.ink,
            ),
          ),
          textAlign: TextAlign.start,
          textDirection: TextDirection.rtl,
          maxLines: ts.lines,
          ellipsis: '…',
        )..layout(minWidth: sw, maxWidth: sw);
        tp.paint(c, ui.Offset.zero);
      });
    }
  }

  // cover photo / sticker
  final el = cover['element'];
  if (t.isCover && el is Map) {
    final img = pb.photos[el['photo_path']];
    if (img != null) {
      double n(Object? v, double d) => (v as num?)?.toDouble() ?? d;
      final ew = n(el['width'], .45) * w;
      final eh = ew * img.height / img.width;
      c.save();
      c.translate(n(el['cx'], .5) * w, n(el['cy'], .35) * h);
      c.rotate(n(el['rotation'], 0));
      final box = ui.Rect.fromLTWH(-ew / 2, -eh / 2, ew, eh);
      c.clipRRect(ui.RRect.fromRectAndRadius(box, ui.Radius.circular(ew * .04)));
      c.drawImageRect(img, ui.Rect.fromLTWH(0, 0, img.width + .0, img.height + .0), box, hi);
      c.restore();
    }
  }

  c.restore();
  final pic = rec.endRecording();
  final out = await pic.toImage(PrintSheet.a4W, PrintSheet.a4H);
  pic.dispose();
  return out;
}

/// JPEG (quality 95) with 300 DPI written into the JFIF header.
Future<Uint8List> encodeJpeg300(ui.Image img) async {
  final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final canvas = web.HTMLCanvasElement()
    ..width = img.width
    ..height = img.height;
  final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
  ctx.putImageData(
      web.ImageData(data.buffer.asUint8ClampedList(data.offsetInBytes, data.lengthInBytes).toJS, img.width, img.height.toJS),
      0,
      0);
  final bytes = await blobBytes(await canvasToJpeg(canvas, .95));
  return setJpegDpi(bytes, PrintSheet.dpi);
}

/// Sets the JFIF density (APP0) so printers and Photoshop read 300 DPI.
Uint8List setJpegDpi(Uint8List b, int dpi) {
  // FF D8 FF E0 len(2) 'JFIF\0' ver(2) units(1) xd(2) yd(2)
  if (b.length > 18 && b[2] == 0xFF && b[3] == 0xE0 && b[6] == 0x4A && b[7] == 0x46 && b[8] == 0x49 && b[9] == 0x46) {
    b[13] = 1;
    b[14] = dpi >> 8;
    b[15] = dpi & 0xFF;
    b[16] = dpi >> 8;
    b[17] = dpi & 0xFF;
  }
  return b;
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

typedef PrintProgress = void Function(String stage, int done, int total);

/// Builds the print package of an order: one folder per book with the front
/// cover and every page as A4 300 DPI JPEGs, plus a notes file.
Future<Uint8List> buildPrintZip(AdminRepository repo, AdminOrder order, {required PrintProgress onProgress}) async {
  await LazyFonts.ensure();
  final archive = Archive();
  final notes = StringBuffer()
    ..writeln('طلب ${order.row.code} · ${order.row.customerName} · ${order.row.phone}')
    ..writeln('${order.row.city} · ${order.address}')
    ..writeln();
  final missing = <String>{};

  // load everything first so the progress bar measures the drawing
  final tplCache = <String, List<PageTemplate>>{};
  final bgCache = <String, ui.Image>{};
  final photoCache = <String, ui.Image>{};
  final books = <PrintBook>[];
  for (final b in order.books) {
    final templates = tplCache[b.productId] ??= await repo.printTemplates(b.productId);
    final paths = {
      for (final p in b.pages) ...p.slots.values,
      if (b.cover['element'] is Map && (b.cover['element'] as Map)['photo_path'] is String)
        (b.cover['element'] as Map)['photo_path'] as String,
    };
    var i = 0;
    for (final path in paths) {
      onProgress('تحميل صور الكتاب ${b.no}', i++, paths.length);
      if (photoCache.containsKey(path)) continue;
      try {
        photoCache[path] = await decodeImage(await repo.download('order-photos', path));
      } catch (_) {
        missing.add('صورة غير موجودة: $path');
      }
    }
    final bgs = <String, ui.Image>{};
    i = 0;
    for (final t in templates) {
      onProgress('تحميل ملفات التصميم', i++, templates.length);
      final cached = bgCache[t.id];
      if (cached != null) {
        bgs[t.id] = cached;
        continue;
      }
      if (t.printPath == null) {
        missing.add('${t.isCover ? 'الغلاف' : 'الصفحة ${t.pageNumber}'}: لا يوجد ملف طباعة (ارفعه من محرر القوالب)');
        continue;
      }
      try {
        bgs[t.id] = bgCache[t.id] = await decodeImage(await repo.download('print-files', t.printPath!));
      } catch (_) {
        missing.add('${t.isCover ? 'الغلاف' : 'الصفحة ${t.pageNumber}'}: تعذّر تحميل ملف الطباعة');
      }
    }
    books.add(PrintBook(book: b, templates: templates, photos: photoCache, backgrounds: bgs));
  }

  final total = books.fold(0, (n, b) => n + b.templates.length);
  var done = 0;
  for (final pb in books) {
    final b = pb.book;
    final folder = order.books.length > 1 ? 'book${b.no}/' : '';
    notes
      ..writeln('— الكتاب ${b.no}${order.books.length > 1 ? ' (المجلد book${b.no})' : ''}')
      ..writeln('الاسم على الغلاف: ${b.childName.isEmpty ? 'بدون' : b.childName}')
      ..writeln('الغلاف: ${b.coverMode == 'designer' ? '«اتركه لذوقكم» — يصممه المصمم (الملف المرفق أساس فقط)' : 'من تصميم الزبون'}');
    final designerNotes = ((b.cover['designer_notes'] as String?) ?? '').trim();
    if (designerNotes.isNotEmpty) notes.writeln('ملاحظات للمصمم: $designerNotes');
    if (b.giftWrap) notes.writeln('تغليف هدية: نعم');
    notes.writeln();

    for (final t in pb.templates) {
      onProgress('رسم الكتاب ${b.no}: ${t.isCover ? 'الغلاف' : 'ص ${t.pageNumber}'}', done, total);
      final img = await renderSheet(pb, t);
      final jpg = await encodeJpeg300(img);
      img.dispose();
      archive.add(ArchiveFile.bytes('$folder${PrintSheet.fileName(t)}', jpg)..compression = CompressionType.none);
      done++;
      // let the progress dialog repaint between pages
      await Future<void>.delayed(Duration.zero);
    }
  }
  // shop items: the customer's details and original photos, one folder each
  for (final it in order.items) {
    final folder = 'items/${it.no.toString().padLeft(2, '0')}_${_safeName(it.title)}/';
    notes
      ..writeln('— ${it.title} × ${it.qty}${it.photos.isEmpty ? '' : ' (الصور في المجلد $folder)'}')
      ..writeAll(it.texts.map((e) => '${e.$1}: ${e.$2}\n'))
      ..writeln();
    for (final (n, path) in it.photos.indexed) {
      onProgress('تحميل صور ${it.title}', n, it.photos.length);
      try {
        final bytes = await repo.download('order-photos', path);
        archive.add(ArchiveFile.bytes('${folder}photo_${(n + 1).toString().padLeft(2, '0')}.jpg', bytes)
          ..compression = CompressionType.none);
      } catch (_) {
        missing.add('صورة غير موجودة (${it.title}): $path');
      }
    }
  }
  if (missing.isNotEmpty) {
    notes
      ..writeln('تنبيهات:')
      ..writeAll(missing.map((m) => '• $m\n'));
  }
  archive.add(ArchiveFile.bytes('00_معلومات_الطلب.txt', utf8.encode(notes.toString())));
  for (final im in {...photoCache.values, ...bgCache.values}) {
    im.dispose();
  }
  onProgress('ضغط الملف', total, total);
  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

String _safeName(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim().replaceAll(RegExp(r'\s+'), '_');

/// Saves bytes as a file in the browser.
void saveFile(Uint8List bytes, String name, String type) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: type));
  final url = web.URL.createObjectURL(blob);
  (web.HTMLAnchorElement()
        ..href = url
        ..download = name)
      .click();
  Future<void>.delayed(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
