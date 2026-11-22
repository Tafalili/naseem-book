import '../storage_urls.dart';
import 'package:material_ui/material_ui.dart';

/// Page geometry in millimetres.
abstract final class BookGeometry {
  static const pageW = 186.0;
  static const pageH = 276.0;
  static const coverW = 200.0; // artwork inside the 5 mm white stroke on A4
  static const coverH = 287.0;
}

enum SlotShape { rect, rounded, ellipse }

double _r(double v) => (v * 10).roundToDouble() / 10; // 0.1 mm

class PhotoSlot {
  const PhotoSlot({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.rotation = 0,
    this.shape = SlotShape.rect,
    this.radius = 0,
  });

  final String id;
  final double x, y, w, h, rotation, radius; // mm, degrees
  final SlotShape shape;

  PhotoSlot copyWith({double? x, double? y, double? w, double? h, double? rotation, SlotShape? shape, double? radius}) =>
      PhotoSlot(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        rotation: rotation ?? this.rotation,
        shape: shape ?? this.shape,
        radius: radius ?? this.radius,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': _r(x),
        'y': _r(y),
        'w': _r(w),
        'h': _r(h),
        if (rotation != 0) 'rotation': _r(rotation),
        'shape': shape.name,
        if (shape == SlotShape.rounded) 'radius': _r(radius),
      };

  factory PhotoSlot.fromJson(Map<String, dynamic> j) => PhotoSlot(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
        shape: SlotShape.values.asNameMap()[j['shape']] ?? SlotShape.rect,
        radius: (j['radius'] as num?)?.toDouble() ?? 0,
      );
}

enum TextKind { childName, memory }

class TextSlot {
  const TextSlot({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.kind,
    this.rotation = 0,
    this.lines = 1,
    this.fontSizeMm = 5,
  });

  final String id;
  final double x, y, w, h, rotation, fontSizeMm;
  final TextKind kind;
  final int lines;

  TextSlot copyWith({double? x, double? y, double? w, double? h, double? rotation, TextKind? kind, int? lines, double? fontSizeMm}) =>
      TextSlot(
        id: id,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        rotation: rotation ?? this.rotation,
        kind: kind ?? this.kind,
        lines: lines ?? this.lines,
        fontSizeMm: fontSizeMm ?? this.fontSizeMm,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': _r(x),
        'y': _r(y),
        'w': _r(w),
        'h': _r(h),
        if (rotation != 0) 'rotation': _r(rotation),
        'kind': kind == TextKind.childName ? 'child_name' : 'memory',
        'lines': lines,
        'font_size_mm': _r(fontSizeMm),
      };

  factory TextSlot.fromJson(Map<String, dynamic> j) => TextSlot(
        id: j['id'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        w: (j['w'] as num).toDouble(),
        h: (j['h'] as num).toDouble(),
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0,
        kind: j['kind'] == 'child_name' ? TextKind.childName : TextKind.memory,
        lines: (j['lines'] as num?)?.toInt() ?? 1,
        fontSizeMm: (j['font_size_mm'] as num?)?.toDouble() ?? 5,
      );
}

class PageTemplate {
  const PageTemplate({
    required this.id,
    required this.pageNumber,
    required this.title,
    required this.backgroundPath,
    required this.photoSlots,
    required this.textSlots,
    required this.isCover,
  });

  final String id;
  final int pageNumber; // 0 = cover
  final String title;
  final String? backgroundPath;
  final List<PhotoSlot> photoSlots;
  final List<TextSlot> textSlots;
  final bool isCover;

  double get widthMm => isCover ? BookGeometry.coverW : BookGeometry.pageW;
  double get heightMm => isCover ? BookGeometry.coverH : BookGeometry.pageH;
  ImageProvider? get background => catalogImage(backgroundPath);

  static const columns = 'id,page_number,title,background_path,photo_slots,text_slots,is_cover';

  factory PageTemplate.fromJson(Map<String, dynamic> j) => PageTemplate(
        id: j['id'] as String,
        pageNumber: (j['page_number'] as num).toInt(),
        title: (j['title'] as String?) ?? '',
        backgroundPath: j['background_path'] as String?,
        photoSlots: ((j['photo_slots'] as List?) ?? const [])
            .map((e) => PhotoSlot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        textSlots: ((j['text_slots'] as List?) ?? const [])
            .map((e) => TextSlot.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        isCover: j['is_cover'] as bool? ?? false,
      );
}
