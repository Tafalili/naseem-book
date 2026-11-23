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
    this.onCoverNameChanged,
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
  final ValueChanged<NamePos>? onCoverNameChanged;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: template.widthMm / template.heightMm,
      child: LayoutBuilder(builder: (context, c) {
        final k = c.maxWidth / template.widthMm; // px per mm
        final size = Size(c.maxWidth, c.maxWidth * template.heightMm / template.widthMm);
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
                if (template.isCover &&
                    t.kind == TextKind.childName &&
                    draft.cover.childName.trim().isNotEmpty)
                  _CoverNameView(
                    slot: t,
                    k: k,
                    size: size,
                    cover: draft.cover,
                    interactive: interactive && onCoverNameChanged != null,
                    onChanged: onCoverNameChanged,
                  )
                else
                  _positioned(k, t.x, t.y, t.w, t.h, t.rotation, _textSlot(t, k)),
              if (template.isCover && draft.cover.element != null)
                _CoverElementView(
                  element: draft.cover.element!,
                  photo: draft.photo(draft.cover.element!.photoId),
                  size: size,
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
        child: Manipulator(
          enabled: _editable,
          onTap: widget.onTap,
          onStart: (d) {
            _start = widget.placement;
            _startFocal = d.focalPoint;
          },
          onUpdate: (d) {
            final st = _start;
            if (st == null) return;
            final delta = d.focalPoint - _startFocal;
            setState(() => _live = _clamp(st.copyWith(
                  scale: st.scale * d.scale,
                  dx: st.dx + delta.dx / s.width,
                  dy: st.dy + delta.dy / s.height,
                )));
          },
          onEnd: () => setState(_commit),
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
                  child: Manipulator(
                    onTap: widget.onTap,
                    onStart: (d) {
                      _start = widget.element;
                      _startFocal = d.focalPoint;
                    },
                    onUpdate: (d) {
                      final st = _start;
                      if (st == null) return;
                      final delta = d.focalPoint - _startFocal;
                      setState(() => _live = st.copyWith(
                            cx: (st.cx + delta.dx / widget.size.width).clamp(0.0, 1.0),
                            cy: (st.cy + delta.dy / widget.size.height).clamp(0.0, 1.0),
                            width: (st.width * d.scale).clamp(.12, 1.0),
                            rotation: st.rotation + d.rotation,
                          ));
                    },
                    onEnd: () {
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

/// The child's name on the cover: drag to move, pinch (or mouse wheel) to resize.
class _CoverNameView extends StatefulWidget {
  const _CoverNameView({
    required this.slot,
    required this.k,
    required this.size,
    required this.cover,
    required this.interactive,
    this.onChanged,
  });

  final TextSlot slot;
  final double k;
  final Size size;
  final CoverDesign cover;
  final bool interactive;
  final ValueChanged<NamePos>? onChanged;

  @override
  State<_CoverNameView> createState() => _CoverNameViewState();
}

class _CoverNameViewState extends State<_CoverNameView> {
  NamePos? _live, _start;
  Offset _startFocal = Offset.zero;

  NamePos _clamp(NamePos p) {
    final t = widget.slot, sz = widget.size, k = widget.k;
    final cx0 = (t.x + t.w / 2) * k / sz.width, cy0 = (t.y + t.h / 2) * k / sz.height;
    return NamePos(
      dx: p.dx.clamp(-cx0, 1 - cx0),
      dy: p.dy.clamp(-cy0, 1 - cy0),
      scale: p.scale.clamp(NamePos.minScale, NamePos.maxScale),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.slot, k = widget.k, sz = widget.size, cover = widget.cover;
    final np = _live ?? cover.namePos;
    final w = t.w * k * np.scale, h = t.h * k * np.scale;
    final cx = (t.x + t.w / 2) * k + np.dx * sz.width;
    final cy = (t.y + t.h / 2) * k + np.dy * sz.height;

    Widget text = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        cover.childName.trim(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: cover.font,
          fontSize: t.fontSizeMm * k * np.scale,
          height: 1.25,
          color: Color(cover.color),
        ),
      ),
    );
    if (widget.interactive) {
      text = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          border: Border.all(
              color: _live != null ? NColors.sage : NColors.sage.withValues(alpha: .45),
              width: _live != null ? 2 : 1),
        ),
        child: text,
      );
      text = Listener(
        onPointerSignal: (e) {
          if (e is! PointerScrollEvent) return;
          final p = cover.namePos;
          widget.onChanged?.call(_clamp(p.copyWith(scale: p.scale * (e.scrollDelta.dy > 0 ? .95 : 1.05))));
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Manipulator(
            onStart: (d) {
              _start = cover.namePos;
              _startFocal = d.focalPoint;
            },
            onUpdate: (d) {
              final st = _start;
              if (st == null) return;
              final delta = d.focalPoint - _startFocal;
              setState(() => _live = _clamp(st.copyWith(
                    dx: st.dx + delta.dx / sz.width,
                    dy: st.dy + delta.dy / sz.height,
                    scale: st.scale * d.scale,
                  )));
            },
            onEnd: () {
              if (_live != null) widget.onChanged?.call(_live!);
              setState(() {
                _live = null;
                _start = null;
              });
            },
            child: text,
          ),
        ),
      );
    }
    return Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      width: w,
      height: h,
      child: t.rotation == 0 ? text : Transform.rotate(angle: _rad(t.rotation), child: text),
    );
  }
}

/// Drag / pinch / rotate that wins over the page's scrolling as soon as a
/// finger touches it (otherwise on phones the scroll view takes every drag).
/// A short touch without movement still counts as a tap.
class Manipulator extends StatefulWidget {
  const Manipulator({
    super.key,
    required this.child,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final GestureScaleStartCallback onStart;
  final GestureScaleUpdateCallback onUpdate;
  final VoidCallback onEnd;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  State<Manipulator> createState() => _ManipulatorState();
}

class _ManipulatorState extends State<Manipulator> {
  Offset _origin = Offset.zero;
  double _travel = 0;
  bool _multi = false;
  DateTime _t0 = DateTime.now();

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onTap, child: widget.child);
    }
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _EagerScaleRecognizer: GestureRecognizerFactoryWithHandlers<_EagerScaleRecognizer>(
          () => _EagerScaleRecognizer(debugOwner: this),
          (r) => r
            ..onStart = (d) {
              _origin = d.focalPoint;
              _travel = 0;
              _multi = d.pointerCount > 1;
              _t0 = DateTime.now();
              widget.onStart(d);
            }
            ..onUpdate = (d) {
              _travel = math.max(_travel, (d.focalPoint - _origin).distance);
              if (d.pointerCount > 1) _multi = true;
              widget.onUpdate(d);
            }
            ..onEnd = (_) {
              final tap = !_multi &&
                  _travel < 8 &&
                  DateTime.now().difference(_t0) < const Duration(milliseconds: 350);
              widget.onEnd();
              if (tap) widget.onTap?.call();
            },
        ),
      },
      child: widget.child,
    );
  }
}

class _EagerScaleRecognizer extends ScaleGestureRecognizer {
  _EagerScaleRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
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
