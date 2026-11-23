import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/page_template.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/storage_urls.dart';
import '../editor/draft/image_tools.dart';
import 'admin_shell.dart';
import 'data/admin_repository.dart';
import 'print/print_files_dialog.dart';
import '../../core/theme/lazy_fonts.dart';

final _productsProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).products());

/// Admin template editor: draw photo frames and text lines on each page.
/// Coordinates are stored in millimetres on the page (0,0 = top-left).
class TemplateEditorPage extends ConsumerStatefulWidget {
  const TemplateEditorPage({super.key});

  @override
  ConsumerState<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends ConsumerState<TemplateEditorPage> {
  String? _slug;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(_productsProvider);
    return products.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
          child: TextButton(
              onPressed: () => ref.invalidate(_productsProvider), child: const Text('تعذّر التحميل. إعادة المحاولة'))),
      data: (all) {
        final list = all.where((p) => p.kind == 'book').toList();
        if (list.isEmpty) return const Center(child: Text('لا توجد منتجات.'));
        final slug = list.any((p) => p.slug == _slug) ? _slug! : list.first.slug;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (list.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(NSpace.md, NSpace.sm, NSpace.md, 0),
              child: Wrap(spacing: NSpace.sm, children: [
                for (final p in list)
                  ChoiceChip(
                    label: Text(p.title),
                    selected: p.slug == slug,
                    onSelected: (_) => setState(() => _slug = p.slug),
                  ),
              ]),
            ),
          Expanded(child: _ProductTemplates(key: ValueKey(slug), slug: slug)),
        ]);
      },
    );
  }
}

class _ProductTemplates extends ConsumerWidget {
  const _ProductTemplates({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pages = ref.watch(templatesProvider(slug));
    return pages.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
          child: TextButton(
              onPressed: () => ref.invalidate(templatesProvider(slug)), child: const Text('تعذّر التحميل. إعادة المحاولة'))),
      data: (list) => _Editor(slug: slug, pages: list),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.slug, required this.pages});
  final String slug;
  final List<PageTemplate> pages;
  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  int _index = 0;
  late List<PhotoSlot> _photos;
  late List<TextSlot> _texts;
  String? _newBackground;
  String? _selected;
  bool _dirty = false, _busy = false;
  bool _showDesign = true;
  int _rev = 0; // bumps on canvas drags so the number fields refresh

  PageTemplate get _page => widget.pages[_index];

  @override
  void initState() {
    super.initState();
    LazyFonts.ensure();
    _load();
  }

  @override
  void didUpdateWidget(covariant _Editor old) {
    super.didUpdateWidget(old);
    if (!_dirty && old.pages != widget.pages) _load();
  }

  void _load() {
    _photos = [..._page.photoSlots];
    _texts = [..._page.textSlots];
    _newBackground = null;
    _selected = null;
    _dirty = false;
  }

  Future<void> _goTo(int i) async {
    if (i == _index) return;
    if (_dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('تغييرات غير محفوظة'),
          content: const Text('تركت تعديلات على هذه الصفحة لم تُحفظ.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('تجاهلها')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('البقاء')),
          ],
        ),
      );
      if (leave != true) return;
    }
    setState(() {
      _index = i;
      _load();
    });
  }

  void _mutate(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  void _updatePhoto(PhotoSlot s) => _mutate(() => _photos = [for (final p in _photos) p.id == s.id ? s : p]);
  void _updateText(TextSlot s) => _mutate(() => _texts = [for (final p in _texts) p.id == s.id ? s : p]);

  String _nextId(String prefix, Iterable<String> taken) {
    var n = 1;
    while (taken.contains('${prefix}_$n')) {
      n++;
    }
    return '${prefix}_$n';
  }

  void _addPhoto() {
    final id = _nextId('p${_page.pageNumber}', _photos.map((s) => s.id));
    final w = _page.widthMm * .6, h = _page.heightMm * .3;
    _mutate(() {
      _photos = [
        ..._photos,
        PhotoSlot(id: id, x: (_page.widthMm - w) / 2, y: (_page.heightMm - h) / 2, w: w, h: h),
      ];
      _selected = id;
    });
  }

  void _addText() {
    final id = _nextId('t${_page.pageNumber}', _texts.map((s) => s.id));
    final w = _page.widthMm * .7;
    _mutate(() {
      _texts = [
        ..._texts,
        TextSlot(
          id: id,
          x: (_page.widthMm - w) / 2,
          y: _page.heightMm * .7,
          w: w,
          h: 30,
          kind: TextKind.memory,
          lines: 3,
        ),
      ];
      _selected = id;
    });
  }

  void _deleteSelected() {
    final id = _selected;
    if (id == null) return;
    _mutate(() {
      _photos = _photos.where((s) => s.id != id).toList();
      _texts = _texts.where((s) => s.id != id).toList();
      _selected = null;
    });
  }

  Future<void> _uploadBackground() async {
    final messenger = ScaffoldMessenger.of(context);
    final files = await pickFiles(accept: 'image/png,image/jpeg,image/webp');
    if (files.isEmpty) return;
    final f = files.first;
    if (f.size > 30 * 1024 * 1024) {
      messenger.showSnackBar(const SnackBar(content: Text('الملف أكبر من 30 ميغابايت.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await blobBytes(f);
      final path = await ref
          .read(adminRepositoryProvider)
          .uploadBackground(widget.slug, _page.pageNumber, bytes, f.type.isEmpty ? 'image/jpeg' : f.type);
      _mutate(() => _newBackground = path);
      messenger.showSnackBar(const SnackBar(content: Text('رُفع التصميم. اضغط «حفظ» لاعتماده.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذّر رفع التصميم. حاول مجدداً.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(adminRepositoryProvider)
          .saveTemplate(_page.id, _photos, _texts, backgroundPath: _newBackground);
      setState(() => _dirty = false);
      ref.invalidate(templatesProvider(widget.slug));
      messenger.showSnackBar(SnackBar(content: Text('حُفظت الصفحة ${_page.pageNumber}.')));
    } on AdminFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final totalFrames = widget.pages.fold(0, (n, p) => n + p.photoSlots.length);
    final bg = _newBackground != null ? catalogImage(_newBackground) : _page.background;

    final toolbar = Wrap(spacing: NSpace.sm, runSpacing: NSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: 260,
        child: DropdownButtonFormField<int>(
          initialValue: _index,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'الصفحة', isDense: true),
          items: [
            for (var i = 0; i < widget.pages.length; i++)
              DropdownMenuItem(
                value: i,
                child: Text(
                  '${widget.pages[i].isCover ? 'الغلاف' : 'ص ${widget.pages[i].pageNumber} · ${widget.pages[i].title}'}'
                  '${widget.pages[i].photoSlots.isEmpty ? '' : ' (${widget.pages[i].photoSlots.length})'}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (v) => v == null ? null : _goTo(v),
        ),
      ),
      IconButton(
        tooltip: 'الصفحة السابقة',
        onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
      IconButton(
        tooltip: 'الصفحة التالية',
        onPressed: _index < widget.pages.length - 1 ? () => _goTo(_index + 1) : null,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      OutlinedButton.icon(onPressed: _addPhoto, icon: const Icon(Icons.add_photo_alternate_outlined), label: const Text('إطار صورة')),
      OutlinedButton.icon(onPressed: _addText, icon: const Icon(Icons.text_fields_rounded), label: const Text('سطر نص')),
      OutlinedButton.icon(
        onPressed: _busy ? null : _uploadBackground,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('تصميم الصفحة'),
      ),
      OutlinedButton.icon(
        onPressed: () => showPrintFilesDialog(context, widget.slug),
        icon: const Icon(Icons.print_outlined),
        label: const Text('ملفات الطباعة'),
      ),
      FilterChip(
        label: const Text('إظهار التصميم'),
        selected: _showDesign,
        onSelected: (v) => setState(() => _showDesign = v),
      ),
      FilledButton.icon(
        onPressed: _busy || !_dirty ? null : _save,
        icon: _busy
            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.save_rounded),
        label: Text(_dirty ? 'حفظ الصفحة' : 'محفوظة'),
      ),
    ]);

    final canvas = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: wide ? 560 : 480),
        child: Focus(
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent && (e.logicalKey == LogicalKeyboardKey.delete) && _selected != null) {
              _deleteSelected();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: _Canvas(
            widthMm: _page.widthMm,
            heightMm: _page.heightMm,
            background: _showDesign ? bg : null,
            photos: _photos,
            texts: _texts,
            selected: _selected,
            onSelect: (id) => setState(() => _selected = id),
            onPhoto: (s) {
              _rev++;
              _updatePhoto(s);
            },
            onText: (s) {
              _rev++;
              _updateText(s);
            },
          ),
        ),
      ),
    );

    final panel = _Properties(
      key: ValueKey('$_index:$_selected:$_rev'),
      page: _page,
      photo: _photos.where((s) => s.id == _selected).firstOrNull,
      text: _texts.where((s) => s.id == _selected).firstOrNull,
      onPhoto: _updatePhoto,
      onText: _updateText,
      onDelete: _deleteSelected,
      photos: _photos,
      texts: _texts,
      onSelect: (id) => setState(() => _selected = id),
    );

    return ListView(
      padding: const EdgeInsets.all(NSpace.md),
      children: [
        Row(children: [
          Expanded(child: Text('محرر القوالب', style: t.headlineSmall)),
          Text('إطارات الصور في الكتاب: $totalFrames', style: t.bodyMedium),
        ]),
        const SizedBox(height: NSpace.sm),
        toolbar,
        const SizedBox(height: NSpace.md),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: canvas),
            const SizedBox(width: NSpace.md),
            SizedBox(width: 340, child: panel),
          ])
        else ...[
          canvas,
          const SizedBox(height: NSpace.md),
          panel,
        ],
        const SizedBox(height: NSpace.md),
        Text('اسحب الإطار لتحريكه، واسحب الزوايا لتغيير حجمه. الأرقام بالمليمتر على صفحة '
            '${_page.widthMm.toStringAsFixed(0)}×${_page.heightMm.toStringAsFixed(0)} مم.',
            style: t.bodySmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Canvas extends StatelessWidget {
  const _Canvas({
    required this.widthMm,
    required this.heightMm,
    required this.background,
    required this.photos,
    required this.texts,
    required this.selected,
    required this.onSelect,
    required this.onPhoto,
    required this.onText,
  });

  final double widthMm, heightMm;
  final ImageProvider? background;
  final List<PhotoSlot> photos;
  final List<TextSlot> texts;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final ValueChanged<PhotoSlot> onPhoto;
  final ValueChanged<TextSlot> onText;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widthMm / heightMm,
      child: LayoutBuilder(builder: (context, c) {
        final k = c.maxWidth / widthMm;
        return Directionality(
          textDirection: TextDirection.ltr, // geometry is physical: x grows to the right
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: NColors.line), boxShadow: NShadow.soft),
            child: ClipRect(
              child: Stack(children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => onSelect(null),
                    child: background == null
                        ? const ColoredBox(color: NColors.surface)
                        : Image(image: background!, fit: BoxFit.fill, gaplessPlayback: true),
                  ),
                ),
                for (final s in photos)
                  _SlotBox(
                    k: k,
                    id: s.id,
                    rect: Rect.fromLTWH(s.x, s.y, s.w, s.h),
                    rotation: s.rotation,
                    color: NColors.sage,
                    shape: s.shape,
                    radiusMm: s.radius,
                    label: '📷 ${s.id}',
                    selected: selected == s.id,
                    onSelect: () => onSelect(s.id),
                    onChanged: (r) => onPhoto(s.copyWith(x: r.left, y: r.top, w: r.width, h: r.height)),
                    bounds: Size(widthMm, heightMm),
                  ),
                for (final s in texts)
                  _SlotBox(
                    k: k,
                    id: s.id,
                    rect: Rect.fromLTWH(s.x, s.y, s.w, s.h),
                    rotation: s.rotation,
                    color: NColors.sand,
                    label: s.kind == TextKind.childName ? '✎ الاسم' : '✎ ${s.lines} أسطر',
                    selected: selected == s.id,
                    onSelect: () => onSelect(s.id),
                    onChanged: (r) => onText(s.copyWith(x: r.left, y: r.top, w: r.width, h: r.height)),
                    bounds: Size(widthMm, heightMm),
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _SlotBox extends StatelessWidget {
  const _SlotBox({
    required this.k,
    required this.id,
    required this.rect,
    required this.rotation,
    required this.color,
    required this.label,
    required this.selected,
    required this.onSelect,
    required this.onChanged,
    required this.bounds,
    this.shape = SlotShape.rect,
    this.radiusMm = 0,
  });

  final double k;
  final String id;
  final Rect rect; // mm
  final double rotation, radiusMm;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final ValueChanged<Rect> onChanged;
  final Size bounds;
  final SlotShape shape;

  static const _minMm = 5.0;
  static const _handle = 16.0;

  Rect _clamp(Rect r) {
    final w = r.width.clamp(_minMm, bounds.width);
    final h = r.height.clamp(_minMm, bounds.height);
    final x = r.left.clamp(-w / 2, bounds.width - w / 2);
    final y = r.top.clamp(-h / 2, bounds.height - h / 2);
    return Rect.fromLTWH(x, y, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final border = selected ? 2.5 : 1.5;
    final radius = switch (shape) {
      SlotShape.rect => BorderRadius.zero,
      SlotShape.rounded => BorderRadius.circular(radiusMm * k),
      SlotShape.ellipse => BorderRadius.all(Radius.elliptical(rect.width * k / 2, rect.height * k / 2)),
    };

    Widget handle(Alignment a, void Function(Offset d) drag) => Align(
          alignment: a,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => drag(d.delta / k),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpLeftDownRight,
              child: Container(
                width: _handle,
                height: _handle,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: color, width: 2),
                  borderRadius: const BorderRadius.all(Radius.circular(3)),
                ),
              ),
            ),
          ),
        );

    return Positioned(
      left: rect.left * k - _handle / 2,
      top: rect.top * k - _handle / 2,
      width: rect.width * k + _handle,
      height: rect.height * k + _handle,
      child: Transform.rotate(
        angle: rotation * math.pi / 180,
        child: Stack(children: [
          Positioned.fill(
            left: _handle / 2,
            top: _handle / 2,
            right: _handle / 2,
            bottom: _handle / 2,
            child: GestureDetector(
              onTap: onSelect,
              onPanStart: (_) => onSelect(),
              onPanUpdate: (d) => onChanged(_clamp(rect.shift(d.delta / k))),
              child: MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: selected ? .35 : .22),
                    border: Border.all(color: color, width: border),
                    borderRadius: radius,
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(label,
                          style: const TextStyle(fontSize: 12, color: NColors.ink, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (selected) ...[
            handle(Alignment.topLeft, (d) => onChanged(_clamp(Rect.fromLTRB(rect.left + d.dx, rect.top + d.dy, rect.right, rect.bottom)))),
            handle(Alignment.topRight, (d) => onChanged(_clamp(Rect.fromLTRB(rect.left, rect.top + d.dy, rect.right + d.dx, rect.bottom)))),
            handle(Alignment.bottomLeft, (d) => onChanged(_clamp(Rect.fromLTRB(rect.left + d.dx, rect.top, rect.right, rect.bottom + d.dy)))),
            handle(Alignment.bottomRight, (d) => onChanged(_clamp(Rect.fromLTRB(rect.left, rect.top, rect.right + d.dx, rect.bottom + d.dy)))),
          ],
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Properties extends StatelessWidget {
  const _Properties({
    super.key,
    required this.page,
    required this.photo,
    required this.text,
    required this.onPhoto,
    required this.onText,
    required this.onDelete,
    required this.photos,
    required this.texts,
    required this.onSelect,
  });

  final PageTemplate page;
  final PhotoSlot? photo;
  final TextSlot? text;
  final ValueChanged<PhotoSlot> onPhoto;
  final ValueChanged<TextSlot> onText;
  final VoidCallback onDelete;
  final List<PhotoSlot> photos;
  final List<TextSlot> texts;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    Widget num(String label, double v, ValueChanged<double> set, {String suffix = 'مم'}) => Padding(
          padding: const EdgeInsets.only(bottom: NSpace.sm),
          child: TextFormField(
            initialValue: v.toStringAsFixed(1),
            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
            onChanged: (s) {
              final d = double.tryParse(s.trim());
              if (d != null) set(d);
            },
          ),
        );

    Widget grid(List<Widget> children) => Wrap(
          spacing: NSpace.sm,
          children: [for (final c in children) SizedBox(width: 150, child: c)],
        );

    final list = AdminCard(
      title: 'عناصر الصفحة',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (photos.isEmpty && texts.isEmpty) Text('لا توجد إطارات. أضف إطار صورة أو سطر نص.', style: t.bodySmall),
        for (final s in photos)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: photo?.id == s.id,
            leading: const Icon(Icons.photo_outlined, color: NColors.sageDark),
            title: Text(s.id, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
            subtitle: Text('${s.w.toStringAsFixed(0)}×${s.h.toStringAsFixed(0)} مم'),
            onTap: () => onSelect(s.id),
          ),
        for (final s in texts)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            selected: text?.id == s.id,
            leading: const Icon(Icons.text_fields_rounded, color: NColors.gold),
            title: Text(s.kind == TextKind.childName ? 'اسم الطفل' : 'نص (${s.lines} أسطر)'),
            subtitle: Text(s.id, textDirection: TextDirection.ltr, textAlign: TextAlign.right),
            onTap: () => onSelect(s.id),
          ),
      ]),
    );

    Widget? editor;
    if (photo != null) {
      final s = photo!;
      editor = AdminCard(
        title: 'إطار صورة · ${s.id}',
        trailing: IconButton(tooltip: 'حذف', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          grid([
            num('X', s.x, (v) => onPhoto(s.copyWith(x: v))),
            num('Y', s.y, (v) => onPhoto(s.copyWith(y: v))),
            num('العرض', s.w, (v) => onPhoto(s.copyWith(w: math.max(5, v)))),
            num('الارتفاع', s.h, (v) => onPhoto(s.copyWith(h: math.max(5, v)))),
            num('الدوران', s.rotation, (v) => onPhoto(s.copyWith(rotation: v)), suffix: '°'),
            if (s.shape == SlotShape.rounded) num('نصف قطر الزوايا', s.radius, (v) => onPhoto(s.copyWith(radius: math.max(0, v)))),
          ]),
          SegmentedButton<SlotShape>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: SlotShape.rect, label: Text('مستطيل')),
              ButtonSegment(value: SlotShape.rounded, label: Text('زوايا دائرية')),
              ButtonSegment(value: SlotShape.ellipse, label: Text('دائرة')),
            ],
            selected: {s.shape},
            onSelectionChanged: (v) => onPhoto(s.copyWith(
                shape: v.first, radius: v.first == SlotShape.rounded && s.radius == 0 ? 8 : s.radius)),
          ),
        ]),
      );
    } else if (text != null) {
      final s = text!;
      editor = AdminCard(
        title: 'سطر نص · ${s.id}',
        trailing: IconButton(tooltip: 'حذف', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<TextKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: TextKind.memory, label: Text('نص الذكرى')),
              ButtonSegment(value: TextKind.childName, label: Text('اسم الطفل')),
            ],
            selected: {s.kind},
            onSelectionChanged: (v) => onText(s.copyWith(kind: v.first)),
          ),
          const SizedBox(height: NSpace.sm),
          grid([
            num('X', s.x, (v) => onText(s.copyWith(x: v))),
            num('Y', s.y, (v) => onText(s.copyWith(y: v))),
            num('العرض', s.w, (v) => onText(s.copyWith(w: math.max(5, v)))),
            num('الارتفاع', s.h, (v) => onText(s.copyWith(h: math.max(5, v)))),
            num('الدوران', s.rotation, (v) => onText(s.copyWith(rotation: v)), suffix: '°'),
            num('حجم الخط', s.fontSizeMm, (v) => onText(s.copyWith(fontSizeMm: v.clamp(2, 60).toDouble()))),
            num('عدد الأسطر', s.lines.toDouble(), (v) => onText(s.copyWith(lines: v.round().clamp(1, 12))), suffix: ''),
          ]),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ?editor,
      if (editor != null) const SizedBox(height: NSpace.md),
      list,
    ]);
  }
}
