// Local (pre-checkout) book draft. Photos live in IndexedDB; this JSON in
// shared_preferences. Placement offsets are fractions of the slot size so
// they survive any render resolution (screen or 300 DPI print).

class PhotoRef {
  const PhotoRef({required this.id, required this.width, required this.height});
  final String id;
  final int width, height; // compressed full-size pixels

  Map<String, dynamic> toJson() => {'id': id, 'w': width, 'h': height};
  factory PhotoRef.fromJson(Map<String, dynamic> j) =>
      PhotoRef(id: j['id'] as String, width: j['w'] as int, height: j['h'] as int);
}

class Placement {
  const Placement({required this.photoId, this.scale = 1, this.dx = 0, this.dy = 0});
  final String photoId;
  final double scale; // >= 1, relative to "cover" fit
  final double dx, dy; // offset as fraction of slot width/height

  Placement copyWith({double? scale, double? dx, double? dy}) => Placement(
      photoId: photoId, scale: scale ?? this.scale, dx: dx ?? this.dx, dy: dy ?? this.dy);

  Map<String, dynamic> toJson() => {'photo': photoId, 's': scale, 'dx': dx, 'dy': dy};
  factory Placement.fromJson(Map<String, dynamic> j) => Placement(
        photoId: j['photo'] as String,
        scale: (j['s'] as num).toDouble(),
        dx: (j['dx'] as num).toDouble(),
        dy: (j['dy'] as num).toDouble(),
      );
}

enum CoverMode { manual, designer }

/// Free element on the cover (a photo now; stickers once provided).
class CoverElement {
  const CoverElement({
    required this.photoId,
    this.cx = .5,
    this.cy = .35,
    this.width = .45,
    this.rotation = 0,
  });
  final String photoId;
  final double cx, cy; // centre, fraction of cover size
  final double width; // fraction of cover width
  final double rotation; // radians

  CoverElement copyWith({double? cx, double? cy, double? width, double? rotation}) =>
      CoverElement(
        photoId: photoId,
        cx: cx ?? this.cx,
        cy: cy ?? this.cy,
        width: width ?? this.width,
        rotation: rotation ?? this.rotation,
      );

  Map<String, dynamic> toJson() =>
      {'photo': photoId, 'cx': cx, 'cy': cy, 'w': width, 'r': rotation};
  factory CoverElement.fromJson(Map<String, dynamic> j) => CoverElement(
        photoId: j['photo'] as String,
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        width: (j['w'] as num).toDouble(),
        rotation: (j['r'] as num).toDouble(),
      );
}

/// Where the child's name sits on the cover, relative to the template's name box:
/// centre offset as a fraction of the cover size, and a size multiplier.
class NamePos {
  const NamePos({this.dx = 0, this.dy = 0, this.scale = 1});
  final double dx, dy, scale;

  static const minScale = .5, maxScale = 2.5;
  bool get isDefault => dx == 0 && dy == 0 && scale == 1;

  NamePos copyWith({double? dx, double? dy, double? scale}) =>
      NamePos(dx: dx ?? this.dx, dy: dy ?? this.dy, scale: scale ?? this.scale);

  Map<String, dynamic> toJson() => {'dx': dx, 'dy': dy, 'scale': scale};
  factory NamePos.fromJson(Map<String, dynamic> j) => NamePos(
        dx: (j['dx'] as num?)?.toDouble() ?? 0,
        dy: (j['dy'] as num?)?.toDouble() ?? 0,
        scale: (j['scale'] as num?)?.toDouble() ?? 1,
      );
}

class CoverDesign {
  const CoverDesign({
    this.mode = CoverMode.manual,
    this.childName = '',
    this.font = 'ArefRuqaa',
    this.color = 0xFF2B2622,
    this.element,
    this.designerNotes = '',
    this.namePos = const NamePos(),
  });

  final CoverMode mode;
  final String childName;
  final String font;
  final int color;
  final CoverElement? element;
  final String designerNotes;
  final NamePos namePos;

  CoverDesign copyWith({
    CoverMode? mode,
    String? childName,
    String? font,
    int? color,
    CoverElement? element,
    bool clearElement = false,
    String? designerNotes,
    NamePos? namePos,
  }) =>
      CoverDesign(
        mode: mode ?? this.mode,
        childName: childName ?? this.childName,
        font: font ?? this.font,
        color: color ?? this.color,
        element: clearElement ? null : (element ?? this.element),
        designerNotes: designerNotes ?? this.designerNotes,
        namePos: namePos ?? this.namePos,
      );

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'name': childName,
        'font': font,
        'color': color,
        if (element != null) 'element': element!.toJson(),
        'notes': designerNotes,
        if (!namePos.isDefault) 'name_pos': namePos.toJson(),
      };

  factory CoverDesign.fromJson(Map<String, dynamic> j) => CoverDesign(
        mode: CoverMode.values.asNameMap()[j['mode']] ?? CoverMode.manual,
        childName: j['name'] as String? ?? '',
        font: j['font'] as String? ?? 'ArefRuqaa',
        color: j['color'] as int? ?? 0xFF2B2622,
        element: j['element'] == null
            ? null
            : CoverElement.fromJson(Map<String, dynamic>.from(j['element'] as Map)),
        designerNotes: j['notes'] as String? ?? '',
        namePos: j['name_pos'] is Map
            ? NamePos.fromJson(Map<String, dynamic>.from(j['name_pos'] as Map))
            : const NamePos(),
      );
}

/// A customer can design several books (one per child) of the same product.
/// The first book's id is the product slug; later ones are `slug~suffix`.
String slugOfBook(String bookId) => bookId.split('~').first;
String newBookId(String slug) => '$slug~${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

class BookDraft {
  const BookDraft({
    required this.productSlug,
    String? bookId,
    this.photos = const [],
    this.placements = const {},
    this.texts = const {},
    this.cover = const CoverDesign(),
    this.updatedAt,
  }) : bookId = bookId ?? productSlug;

  final String productSlug;
  final String bookId;
  final List<PhotoRef> photos;
  final Map<String, Placement> placements; // slotId -> placement
  final Map<String, String> texts; // textSlotId -> printed text
  final CoverDesign cover;
  final DateTime? updatedAt;

  PhotoRef? photo(String id) {
    for (final p in photos) {
      if (p.id == id) return p;
    }
    return null;
  }

  Set<String> get usedPhotoIds => {
        ...placements.values.map((p) => p.photoId),
        if (cover.element != null) cover.element!.photoId,
      };

  /// Memory texts (paid add-on). Child-name lines are filled from the cover name.
  bool get hasPrintedText => texts.values.any((t) => t.trim().isNotEmpty);

  BookDraft copyWith({
    List<PhotoRef>? photos,
    Map<String, Placement>? placements,
    Map<String, String>? texts,
    CoverDesign? cover,
  }) =>
      BookDraft(
        productSlug: productSlug,
        bookId: bookId,
        photos: photos ?? this.photos,
        placements: placements ?? this.placements,
        texts: texts ?? this.texts,
        cover: cover ?? this.cover,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'v': 1,
        'slug': productSlug,
        'book': bookId,
        'photos': photos.map((p) => p.toJson()).toList(),
        'placements': placements.map((k, v) => MapEntry(k, v.toJson())),
        'texts': texts,
        'cover': cover.toJson(),
        'updated': updatedAt?.toIso8601String(),
      };

  factory BookDraft.fromJson(Map<String, dynamic> j) => BookDraft(
        productSlug: j['slug'] as String,
        bookId: j['book'] as String?,
        photos: ((j['photos'] as List?) ?? const [])
            .map((e) => PhotoRef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        placements: ((j['placements'] as Map?) ?? const {}).map((k, v) =>
            MapEntry(k as String, Placement.fromJson(Map<String, dynamic>.from(v as Map)))),
        texts: ((j['texts'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String)),
        cover: j['cover'] == null
            ? const CoverDesign()
            : CoverDesign.fromJson(Map<String, dynamic>.from(j['cover'] as Map)),
        updatedAt: DateTime.tryParse(j['updated'] as String? ?? ''),
      );
}
