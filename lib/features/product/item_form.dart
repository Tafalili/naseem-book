import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/product.dart';
import '../cart/shop_cart.dart';
import '../editor/draft/photo_store.dart';

/// Order form of a shop item: quantity and the fields the store asks for.
/// With [lineId] it edits that cart line instead of adding a new one.
class ItemOrderForm extends ConsumerStatefulWidget {
  const ItemOrderForm({super.key, required this.product, this.lineId});
  final Product product;
  final String? lineId;

  @override
  ConsumerState<ItemOrderForm> createState() => _ItemOrderFormState();
}

class _ItemOrderFormState extends ConsumerState<ItemOrderForm> {
  late int _qty;
  final _texts = <String, TextEditingController>{};
  final _photos = <String, List<String>>{};
  String? _error;
  bool _busy = false;
  bool _loaded = false;

  ItemOptions get _o => widget.product.options;

  @override
  void initState() {
    super.initState();
    _qty = _o.minQty;
    for (final f in _o.fields.where((f) => f.type != FieldType.photos)) {
      _texts[f.id] = TextEditingController();
    }
  }

  void _fillFrom(ShopLine l) {
    _qty = l.qty.clamp(_o.minQty, _o.maxQty);
    l.texts.forEach((k, v) => _texts[k]?.text = v);
    _photos
      ..clear()
      ..addAll({for (final e in l.photos.entries) e.key: [...e.value]});
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  ShopLine get _line => ShopLine(
        id: widget.lineId ?? ShopCartController.newId(),
        slug: widget.product.slug,
        qty: _qty,
        texts: {for (final e in _texts.entries) if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim()},
        photos: {for (final e in _photos.entries) if (e.value.isNotEmpty) e.key: e.value},
      );

  Future<void> _addPhotos(ItemField f) async {
    final have = _photos[f.id]?.length ?? 0;
    if (have >= f.max) return;
    setState(() => _busy = true);
    final ids = await ShopCartController.importPhotos(multiple: f.max - have > 1);
    if (!mounted) return;
    final keep = ids.take(f.max - have).toList();
    for (final extra in ids.skip(keep.length)) {
      await PhotoStore.instance.delete(extra);
    }
    setState(() {
      _busy = false;
      _photos[f.id] = [...?_photos[f.id], ...keep];
      if (ids.length > keep.length) _error = 'الحد الأقصى ${f.max} صورة لهذا الحقل';
    });
  }

  Future<void> _removePhoto(String field, String id) async {
    setState(() => _photos[field]?.remove(id));
    // a saved line still points at it until the customer saves again
    if (widget.lineId == null) await PhotoStore.instance.delete(id);
  }

  Future<void> _submit() async {
    final line = _line;
    final missing = line.missing(widget.product);
    if (missing != null) {
      setState(() => _error = 'أكملي: $missing');
      return;
    }
    final cart = ref.read(shopCartProvider.notifier);
    if (widget.lineId == null && cart.full) {
      setState(() => _error = 'السلة ممتلئة');
      return;
    }
    await cart.put(line);
    if (!mounted) return;
    context.go(Routes.cart);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (!_loaded && widget.lineId != null) {
      final l = ref.watch(shopCartProvider).where((e) => e.id == widget.lineId).firstOrNull;
      if (l != null) {
        _fillFrom(l);
        _loaded = true;
      }
    }
    final p = widget.product;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final f in _o.fields) ...[
          if (f.type == FieldType.photos)
            _PhotoField(
              field: f,
              ids: _photos[f.id] ?? const [],
              busy: _busy,
              onAdd: () => _addPhotos(f),
              onRemove: (id) => _removePhoto(f.id, id),
            )
          else
            TextField(
              controller: _texts[f.id],
              maxLength: f.max,
              maxLines: f.type == FieldType.longtext ? 4 : 1,
              keyboardType: switch (f.type) {
                FieldType.date || FieldType.time => TextInputType.datetime,
                _ => TextInputType.text,
              },
              decoration: InputDecoration(
                labelText: f.required ? '${f.label} *' : f.label,
                hintText: f.hint ??
                    switch (f.type) {
                      FieldType.date => 'مثال: 2026/11/22',
                      FieldType.time => 'مثال: 10:30 مساءً',
                      _ => null,
                    },
                counterText: '',
              ),
              onChanged: (_) => _error == null ? null : setState(() => _error = null),
            ),
          const SizedBox(height: NSpace.md),
        ],
        Row(
          children: [
            Text('الكمية', style: t.titleSmall),
            const Spacer(),
            _QtyStepper(
              value: _qty,
              min: _o.minQty,
              max: _o.maxQty,
              onChanged: (v) => setState(() => _qty = v),
            ),
          ],
        ),
        if (_o.minQty > 1)
          Text('أقل كمية ${_o.minQty} ${_o.unitLabel}', style: t.bodySmall),
        const SizedBox(height: NSpace.md),
        if (_error != null) ...[
          Text(_error!, style: t.bodyMedium?.copyWith(color: NColors.danger)),
          const SizedBox(height: NSpace.sm),
        ],
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: _busy ? null : _submit,
          icon: const Icon(Icons.shopping_bag_outlined),
          label: Text(widget.lineId == null
              ? 'أضيفي للسلة · ${formatIqd(p.basePrice * _qty)}'
              : 'حفظ التعديل · ${formatIqd(p.basePrice * _qty)}'),
        ),
      ],
    );
  }
}

class _QtyStepper extends StatefulWidget {
  const _QtyStepper({required this.value, required this.min, required this.max, required this.onChanged});
  final int value, min, max;
  final ValueChanged<int> onChanged;

  @override
  State<_QtyStepper> createState() => _QtyStepperState();
}

class _QtyStepperState extends State<_QtyStepper> {
  late final _c = TextEditingController(text: '${widget.value}');

  @override
  void didUpdateWidget(_QtyStepper old) {
    super.didUpdateWidget(old);
    if (int.tryParse(_c.text) != widget.value) _c.text = '${widget.value}';
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // big packs move in tens
  int get _step => widget.min >= 10 ? 5 : 1;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.outlined(
            onPressed: widget.value - _step >= widget.min ? () => widget.onChanged(widget.value - _step) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _c,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(isDense: true),
              onSubmitted: (v) => widget.onChanged((int.tryParse(v) ?? widget.min).clamp(widget.min, widget.max)),
              onTapOutside: (_) =>
                  widget.onChanged((int.tryParse(_c.text) ?? widget.min).clamp(widget.min, widget.max)),
            ),
          ),
          IconButton.outlined(
            onPressed: widget.value + _step <= widget.max ? () => widget.onChanged(widget.value + _step) : null,
            icon: const Icon(Icons.add),
          ),
        ],
      );
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.field,
    required this.ids,
    required this.busy,
    required this.onAdd,
    required this.onRemove,
  });
  final ItemField field;
  final List<String> ids;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(field.required ? '${field.label} *' : field.label, style: t.titleSmall),
        Text(field.hint ?? (field.max > 1 ? 'حتى ${field.max} صور' : 'صورة واحدة'), style: t.bodySmall),
        const SizedBox(height: NSpace.sm),
        Wrap(
          spacing: NSpace.sm,
          runSpacing: NSpace.sm,
          children: [
            for (final id in ids) ShopPhotoThumb(id: id, size: 76, onRemove: () => onRemove(id)),
            if (ids.length < field.max)
              InkWell(
                onTap: busy ? null : onAdd,
                borderRadius: const BorderRadius.all(NRadius.md),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: NColors.surfaceAlt,
                    borderRadius: const BorderRadius.all(NRadius.md),
                    border: Border.all(color: NColors.line),
                  ),
                  child: busy
                      ? const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator()))
                      : const Icon(Icons.add_photo_alternate_outlined, color: NColors.sageDark),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Square preview of a photo kept on the device.
class ShopPhotoThumb extends StatelessWidget {
  const ShopPhotoThumb({super.key, required this.id, this.size = 56, this.onRemove});
  final String id;
  final double size;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(NRadius.md),
              child: FutureBuilder(
                future: PhotoStore.instance.preview(id),
                builder: (_, s) => s.data == null
                    ? const ColoredBox(color: NColors.surfaceAlt)
                    : Image.memory(s.data!, fit: BoxFit.cover, gaplessPlayback: true),
              ),
            ),
            if (onRemove != null)
              PositionedDirectional(
                top: 2,
                end: 2,
                child: InkWell(
                  onTap: onRemove,
                  child: const CircleAvatar(
                    radius: 11,
                    backgroundColor: Color(0xCC000000),
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      );
}
