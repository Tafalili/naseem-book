import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/page_template.dart';
import '../draft/book_draft.dart';
import '../draft/draft_controller.dart';

double _rad(double deg) => deg * math.pi / 180;

/// Renders one page (or the cover) at any size from its mm template.
/// When [interactive], slots are tappable and the selected photo can be
/// panned/zoomed in place.
class PageCanvas extends StatelessWidget {
  const PageCanvas({
    super.key,
    required this.template,
    required this.draft,
    this.interactive = false,
    this.selectedSlotId,
    this.onSlotTap,
    this.onTextTap,
    this.onPlacementChanged,
    this.onCoverElementChanged,
    this.onCoverElementTap,
  });

  final PageTemplate template;
  final BookDraft draft;
  final bool interactive;
  final String? selectedSlotId;
  final void Function(PhotoSlot slot)? onSlotTap;
  final void Function(TextSlot slot)? onTextTap;
  final void Function(String slotId, Placement p)? onPlacementChanged;
  final void Function(CoverElement e)? onCoverElementChanged;
  final VoidCallback? onCoverElementTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: template.widthMm / template.heightMm,
      child: LayoutBuilder(builder: (context, c) {
        final k = c.maxWidth / template.widthMm; // px per mm
        final bg = template.background;
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: bg == null
                    ? const ColoredBox(color: NColors.surface)
                    : Image(image: bg, fit: BoxFit.fill, gaplessPlayback: true),
              ),
              for (final s in template.photoSlots)
                _positioned(
                  k,
                  s.x,
                  s.y,
                  s.w,
                  s.h,
                  s.rotation,
                  _PhotoSlotView(
                    slot: s,
                    k: k,
                    placement: draft.placements[s.id],
                    photo: draft.placements[s.id] == null
                        ? null
                        : draft.photo(draft.placements[s.id]!.photoId),
                    interactive: interactive,
                    selected: selectedSlotId == s.id,
                    onTap: onSlotTap == null ? null : () => onSlotTap!(s),
                    onChanged: onPlacementChanged == null
                        ? null
                        : (p) => onPlacementChanged!(s.id, p),
                  ),
                ),
              for (final t in template.textSlots)
                _positioned(k, t.x, t.y, t.w, t.h, t.rotation, _textSlot(t, k)),
              if (template.isCover && draft.cover.element != null)
                _CoverElementView(
                  element: draft.cover.element!,
                  photo: draft.photo(draft.cover.element!.photoId),
                  size: Size(c.maxWidth, c.maxWidth * template.heightMm / template.widthMm),
                  interactive: interactive,
                  onChanged: onCoverElementChanged,
                  onTap: onCoverElementTap,
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _positioned(double k, double x, double y, double w, double h, double rot, Widget child) =>
      Positioned(
        left: x * k,
        top: y * k,
        width: w * k,
        height: h * k,
        child: rot == 0 ? child : Transform.rotate(angle: _rad(rot), child: child),
      );

  Widget _textSlot(TextSlot t, double k) {
    final cover = draft.cover;
    if (t.kind == TextKind.childName) {
      final name = cover.childName.trim();
      final onCover = template.isCover;
      if (name.isEmpty) {
        return onCover && interactive
            ? _Hint(label: 'اسم طفلك هنا', k: k, onTap: null)
            : const SizedBox.shrink();
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          name,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: onCover ? cover.font : NFonts.naskh,
            fontSize: t.fontSizeMm * k,
            height: 1.25,
            color: onCover ? Color(cover.color) : NColors.ink,
          ),
        ),
      );
    }
    final text = draft.texts[t.id];
    final tap = interactive && onTextTap != null ? () => onTextTap!(t) : null;
    if (text == null || text.isEmpty) {
      return interactive
          ? _Hint(label: 'نص مطبوع (اختياري)', k: k, onTap: tap, icon: Icons.edit_note_rounded)
          : const SizedBox.shrink();
    }
    return GestureDetector(
      onTap: tap,
      child: Text(
        text,
        maxLines: t.lines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.start,
        style: TextStyle(
          fontFamily: NFonts.naskh,
          fontSize: t.fontSizeMm * k,
          height: t.h / t.lines / t.fontSizeMm,
          color: NColors.ink,
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.label, required this.k, this.onTap, this.icon});
  final String label;
  final double k;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final size = (k * 4.2).clamp(9.0, 15.0);
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
        child: Container(
          decoration: BoxDecoration(
            color: NColors.surface.withValues(alpha: .55),
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            border: Border.all(color: NColors.sage.withValues(alpha: .6)),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) Icon(icon, size: size + 2, color: NColors.sageDark),
                if (icon != null) const SizedBox(width: 4),
                Text(label, style: TextStyle(fontSize: size, color: NColors.sageDark)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoSlotView extends ConsumerStatefulWidget {
  const _PhotoSlotView({
    required this.slot,
    required this.k,
    required this.placement,
    required this.photo,
    required this.interactive,
    required this.selected,
    this.onTap,
    this.onChanged,
  });

  final PhotoSlot slot;
  final double k;
  final Placement? placement;
  final PhotoRef? photo;
  final bool interactive;
  final bool selected;
  final VoidCallback? onTap;
  final ValueChanged<Placement>? onChanged;

  @override
  ConsumerState<_PhotoSlotView> createState() => _PhotoSlotViewState();
}

class _PhotoSlotViewState extends ConsumerState<_PhotoSlotView> {
  Placement? _live; // during a gesture
  Placement? _start;
  Offset _startFocal = Offset.zero;

  Placement? get _p => _live ?? widget.placement;

  Size get _slotPx => Size(widget.slot.w * widget.k, widget.slot.h * widget.k);

  Placement _clamp(Placement p) {
    final photo = widget.photo;
    if (photo == null) return p;
    final s = _slotPx;
    final base = math.max(s.width / photo.width, s.height / photo.height);
    final scale = p.scale.clamp(1.0, 4.0);
    final dw = photo.width * base * scale, dh = photo.height * base * scale;
    final mx = (dw - s.width) / 2 / s.width, my = (dh - s.height) / 2 / s.height;
    return p.copyWith(scale: scale, dx: p.dx.clamp(-mx, mx), dy: p.dy.clamp(-my, my));
  }

  bool get _editable => widget.interactive && widget.selected && widget.placement != null;

  void _commit() {
    if (_live != null) widget.onChanged?.call(_live!);
    _live = null;
    _start = null;
  }

  @override
  Widget build(BuildContext context) {
    final s = _slotPx;
    final r = widget.slot.radius * widget.k;
    final p = _p;
    Widget content;
    if (p == null || widget.photo == null) {
      content = widget.interactive ? _empty(s) : const SizedBox.expand();
    } else {
      final bytes = ref.watch(photoPreviewProvider(p.photoId)).value;
      final photo = widget.photo!;
      final base = math.max(s.width / photo.width, s.height / photo.height);
      final dw = photo.width * base * p.scale, dh = photo.height * base * p.scale;
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: (s.width - dw) / 2 + p.dx * s.width,
            top: (s.height - dh) / 2 + p.dy * s.height,
            width: dw,
            height: dh,
            child: bytes == null
                ? const ColoredBox(color: NColors.surfaceAlt)
                : Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true),
          ),
        ],
      );
    }

    Widget clipped = switch (widget.slot.shape) {
      SlotShape.ellipse => ClipOval(child: content),
      SlotShape.rounded => ClipRRect(borderRadius: BorderRadius.circular(r), child: content),
      SlotShape.rect => ClipRect(child: content),
    };

    if (widget.interactive) {
      clipped = Stack(
        fit: StackFit.expand,
        children: [
          clipped,
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.slot.shape == SlotShape.rect ? 0 : r),
                border: widget.selected
                    ? Border.all(color: NColors.sage, width: 3)
                    : null,
              ),
            ),
          ),
        ],
      );
    }

    if (!widget.interactive) return clipped;

    return Listener(
      onPointerSignal: (e) {
        if (!_editable || e is! PointerScrollEvent) return;
        final next = _clamp(widget.placement!.copyWith(
            scale: widget.placement!.scale * (e.scrollDelta.dy > 0 ? .93 : 1.07)));
        widget.onChanged?.call(next);
      },
      child: MouseRegion(
        cursor: _editable ? SystemMouseCursors.move : SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onScaleStart: _editable
              ? (d) {
                  _start = widget.placement;
                  _startFocal = d.focalPoint;
                }
              : null,
          onScaleUpdate: _editable
              ? (d) {
                  final st = _start!;
                  final delta = d.focalPoint - _startFocal;
                  setState(() => _live = _clamp(st.copyWith(
                        scale: st.scale * d.scale,
                        dx: st.dx + delta.dx / s.width,
                        dy: st.dy + delta.dy / s.height,
                      )));
                }
              : null,
          onScaleEnd: _editable ? (_) => _commit() : null,
          child: clipped,
        ),
      ),
    );
  }

  Widget _empty(Size s) {
    final icon = (math.min(s.width, s.height) * .22).clamp(14.0, 40.0);
    return Container(
      color: NColors.surface.withValues(alpha: widget.selected ? .75 : .55),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_a_photo_outlined, size: icon, color: NColors.sageDark),
            if (s.width > 90)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('أضيفي صورة',
                    style: TextStyle(fontSize: icon * .42, color: NColors.sageDark)),
              ),
          ],
        ),
      ),
    );
  }
}

class _CoverElementView extends ConsumerStatefulWidget {
  const _CoverElementView({
    required this.element,
    required this.photo,
    required this.size,
    required this.interactive,
    this.onChanged,
    this.onTap,
  });

  final CoverElement element;
  final PhotoRef? photo;
  final Size size;
  final bool interactive;
  final ValueChanged<CoverElement>? onChanged;
  final VoidCallback? onTap;

  @override
  ConsumerState<_CoverElementView> createState() => _CoverElementViewState();
}

class _CoverElementViewState extends ConsumerState<_CoverElementView> {
  CoverElement? _live, _start;
  Offset _startFocal = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final e = _live ?? widget.element;
    final photo = widget.photo;
    if (photo == null) return const SizedBox.shrink();
    final w = e.width * widget.size.width;
    final h = w * photo.height / photo.width;
    final bytes = ref.watch(photoPreviewProvider(e.photoId)).value;
    Widget img = bytes == null
        ? const ColoredBox(color: NColors.surfaceAlt)
        : Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true);
    img = ClipRRect(borderRadius: BorderRadius.circular(w * .04), child: img);
    if (widget.interactive) {
      img = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border.all(
              color: _live != null ? NColors.sage : NColors.sage.withValues(alpha: .5),
              width: 2),
          borderRadius: BorderRadius.circular(w * .04),
        ),
        child: img,
      );
    }
    return Positioned(
      left: e.cx * widget.size.width - w / 2,
      top: e.cy * widget.size.height - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: e.rotation,
        child: !widget.interactive
            ? img
            : MouseRegion(
                cursor: SystemMouseCursors.move,
                child: Listener(
                  onPointerSignal: (ev) {
                    if (ev is! PointerScrollEvent) return;
                    final f = ev.scrollDelta.dy > 0 ? .95 : 1.05;
                    widget.onChanged?.call(
                        widget.element.copyWith(width: (widget.element.width * f).clamp(.12, 1.0)));
                  },
                  child: GestureDetector(
                    onTap: widget.onTap,
                    onScaleStart: (d) {
                      _start = widget.element;
                      _startFocal = d.focalPoint;
                    },
                    onScaleUpdate: (d) {
                      final st = _start!;
                      final delta = d.focalPoint - _startFocal;
                      setState(() => _live = st.copyWith(
                            cx: (st.cx + delta.dx / widget.size.width).clamp(0.0, 1.0),
                            cy: (st.cy + delta.dy / widget.size.height).clamp(0.0, 1.0),
                            width: (st.width * d.scale).clamp(.12, 1.0),
                            rotation: st.rotation + d.rotation,
                          ));
                    },
                    onScaleEnd: (_) {
                      if (_live != null) widget.onChanged?.call(_live!);
                      setState(() {
                        _live = null;
                        _start = null;
                      });
                    },
                    child: img,
                  ),
                ),
              ),
      ),
    );
  }
}

/// A read-only page scaled to fill its parent (cropping the few mm where the
/// cover's aspect differs from the page's).
class FittedPage extends StatelessWidget {
  const FittedPage({super.key, required this.template, required this.draft});
  final PageTemplate template;
  final BookDraft draft;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: template.widthMm * 4,
        height: template.heightMm * 4,
        child: PageCanvas(template: template, draft: draft),
      ),
    );
  }
}
