import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../editor/draft/image_tools.dart';
import 'data/admin_repository.dart';

final _shopProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).shopProducts());

/// Shop items (frames, cards, tags...): price, quantity rules, what the customer fills in, photo.
class AdminProductsPage extends ConsumerWidget {
  const AdminProductsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_shopProvider);
    final t = Theme.of(context).textTheme;
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => Center(
        child: FilledButton(onPressed: () => ref.invalidate(_shopProvider), child: const Text('إعادة المحاولة')),
      ),
      data: (items) => ListView(
        padding: const EdgeInsets.all(NSpace.lg),
        children: [
          Row(children: [
            Expanded(child: Text('منتجات المتجر', style: t.headlineSmall)),
            FilledButton.icon(
              onPressed: () => _edit(context, ref, null, true),
              icon: const Icon(Icons.add_rounded),
              label: const Text('منتج جديد'),
            ),
          ]),
          Text('الهدايا والتوزيعات التي تُطلب مع الكتاب أو وحدها. أسعار الكتب في الإعدادات.', style: t.bodySmall),
          const SizedBox(height: NSpace.md),
          for (final (p, active) in items)
            Card(
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: const BorderRadius.all(NRadius.sm),
                  child: SizedBox.square(
                    dimension: 52,
                    child: p.coverImage == null
                        ? const ColoredBox(color: NColors.sandSoft)
                        : Image(image: p.coverImage!, fit: BoxFit.cover),
                  ),
                ),
                title: Text(p.title),
                subtitle: Text(
                    '${formatIqd(p.basePrice)} لل${p.options.unitLabel}'
                    '${p.options.minQty > 1 ? ' · أقل كمية ${p.options.minQty}' : ''}'
                    ' · ${p.options.fields.length} حقول',
                    style: t.bodySmall),
                trailing: active
                    ? const Chip(label: Text('معروض'))
                    : const Chip(label: Text('مخفي'), backgroundColor: NColors.surfaceAlt),
                onTap: () => _edit(context, ref, p, active),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Product? p, bool active) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ProductDialog(product: p, active: active),
    );
    if (saved == true) {
      ref.invalidate(_shopProvider);
      ref.invalidate(productsProvider);
      if (p != null) ref.invalidate(productBySlugProvider(p.slug));
    }
  }
}

class _ProductDialog extends ConsumerStatefulWidget {
  const _ProductDialog({required this.product, required this.active});
  final Product? product;
  final bool active;

  @override
  ConsumerState<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends ConsumerState<_ProductDialog> {
  late final p = widget.product;
  late final _title = TextEditingController(text: p?.title ?? '');
  late final _slug = TextEditingController(text: p?.slug ?? '');
  late final _tagline = TextEditingController(text: p?.tagline ?? '');
  late final _desc = TextEditingController(text: p?.description ?? '');
  late final _price = TextEditingController(text: p == null ? '' : '${p!.basePrice}');
  late final _unit = TextEditingController(text: p?.options.unitLabel ?? 'قطعة');
  late final _min = TextEditingController(text: '${p?.options.minQty ?? 1}');
  late final _max = TextEditingController(text: '${p?.options.maxQty ?? 99}');
  late bool _active = widget.active;
  late String? _image = p?.coverImagePath;
  late final List<_FieldDraft> _fields = [for (final f in p?.options.fields ?? const <ItemField>[]) _FieldDraft(f)];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_title, _slug, _tagline, _desc, _price, _unit, _min, _max]) {
      c.dispose();
    }
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  int _int(TextEditingController c, int d) => int.tryParse(c.text.replaceAll(RegExp(r'\D'), '')) ?? d;

  Future<void> _pickImage() async {
    final slug = _slug.text.trim();
    if (slug.isEmpty) {
      setState(() => _error = 'اكتب الرابط المختصر أولاً');
      return;
    }
    final files = await pickFiles(accept: 'image/png,image/jpeg,image/webp');
    if (files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final f = files.first;
      final path = await ref.read(adminRepositoryProvider).uploadProductImage(slug, await blobBytes(f), f.type);
      setState(() => _image = path);
    } catch (_) {
      setState(() => _error = 'تعذّر رفع الصورة');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final slug = _slug.text.trim().toLowerCase();
    if (_title.text.trim().isEmpty || !RegExp(r'^[a-z0-9-]{2,40}$').hasMatch(slug)) {
      setState(() => _error = 'الاسم مطلوب، والرابط المختصر بحروف إنجليزية صغيرة وأرقام و- فقط');
      return;
    }
    final ids = <String>{};
    for (final f in _fields) {
      if (f.label.text.trim().isEmpty) {
        setState(() => _error = 'كل حقل يحتاج اسماً');
        return;
      }
      if (!ids.add(f.id)) {
        setState(() => _error = 'يوجد حقلان بنفس المعرّف');
        return;
      }
    }
    final minQ = _int(_min, 1).clamp(1, 1000);
    final options = ItemOptions(
      minQty: minQ,
      maxQty: _int(_max, 99).clamp(minQ, 1000),
      unitLabel: _unit.text.trim().isEmpty ? 'قطعة' : _unit.text.trim(),
      fields: [for (final f in _fields) f.build()],
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).saveProduct(p?.id, {
        'title': _title.text.trim(),
        'slug': slug,
        'tagline': _tagline.text.trim().isEmpty ? null : _tagline.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'base_price': _int(_price, 0),
        'is_active': _active,
        'cover_image_path': _image,
        'options': options.toJson(),
      });
      if (mounted) Navigator.pop(context, true);
    } on AdminFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    Widget row(List<Widget> c) => Padding(
          padding: const EdgeInsets.only(bottom: NSpace.sm),
          child: Row(children: [
            for (var i = 0; i < c.length; i++) ...[if (i > 0) const SizedBox(width: NSpace.sm), Expanded(child: c[i])],
          ]),
        );
    return AlertDialog(
      title: Text(p == null ? 'منتج جديد' : p!.title),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              ClipRRect(
                borderRadius: const BorderRadius.all(NRadius.md),
                child: SizedBox.square(
                  dimension: 96,
                  child: catalogPreview(_image),
                ),
              ),
              const SizedBox(width: NSpace.md),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                icon: const Icon(Icons.image_outlined),
                label: const Text('صورة المنتج'),
              ),
              const Spacer(),
              const Text('معروض في المتجر'),
              Switch(value: _active, onChanged: (v) => setState(() => _active = v)),
            ]),
            const SizedBox(height: NSpace.md),
            row([
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'اسم المنتج')),
              TextField(
                controller: _slug,
                enabled: p == null,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'الرابط المختصر (إنجليزي)', hintText: 'birth-frame'),
              ),
            ]),
            row([TextField(controller: _tagline, decoration: const InputDecoration(labelText: 'سطر قصير تحت الاسم'))]),
            row([
              TextField(
                controller: _desc,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
            ]),
            row([
              TextField(
                  controller: _price,
                  inputFormatters: digits,
                  decoration: const InputDecoration(labelText: 'السعر (د.ع) للوحدة')),
              TextField(controller: _unit, decoration: const InputDecoration(labelText: 'اسم الوحدة', hintText: 'قطعة')),
              TextField(controller: _min, inputFormatters: digits, decoration: const InputDecoration(labelText: 'أقل كمية')),
              TextField(controller: _max, inputFormatters: digits, decoration: const InputDecoration(labelText: 'أكثر كمية')),
            ]),
            const SizedBox(height: NSpace.sm),
            Row(children: [
              Expanded(child: Text('ما يكتبه الزبون أو يرفعه', style: t.titleSmall)),
              TextButton.icon(
                onPressed: () => setState(() => _fields.add(_FieldDraft(null))),
                icon: const Icon(Icons.add_rounded),
                label: const Text('حقل'),
              ),
            ]),
            for (final f in _fields)
              _FieldRow(
                key: ObjectKey(f),
                field: f,
                onChanged: () => setState(() {}),
                onRemove: () => setState(() {
                  _fields.remove(f);
                  f.dispose();
                }),
              ),
            if (_error != null) ...[
              const SizedBox(height: NSpace.sm),
              Text(_error!, style: t.bodyMedium?.copyWith(color: NColors.danger)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('حفظ')),
      ],
    );
  }
}

Widget catalogPreview(String? path) {
  final img = path == null ? null : Product.fromJson({'id': '', 'slug': '', 'title': '', 'cover_image_path': path}).coverImage;
  return img == null
      ? const ColoredBox(color: NColors.sandSoft, child: Icon(Icons.image_outlined, color: NColors.inkMuted))
      : Image(image: img, fit: BoxFit.cover);
}

class _FieldDraft {
  _FieldDraft(ItemField? f)
      : id = f?.id ?? 'f${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        label = TextEditingController(text: f?.label ?? ''),
        hint = TextEditingController(text: f?.hint ?? ''),
        max = TextEditingController(text: '${f?.max ?? 30}'),
        type = f?.type ?? FieldType.text,
        required = f?.required ?? false;
  final String id;
  final TextEditingController label, hint, max;
  FieldType type;
  bool required;

  ItemField build() => ItemField(
        id: id,
        label: label.text.trim(),
        type: type,
        required: required,
        max: (int.tryParse(max.text) ?? (type == FieldType.photos ? 10 : 60)).clamp(1, type == FieldType.photos ? 50 : 500),
        hint: hint.text.trim().isEmpty ? null : hint.text.trim(),
      );

  void dispose() {
    label.dispose();
    hint.dispose();
    max.dispose();
  }
}

const _typeLabels = {
  FieldType.text: 'نص قصير',
  FieldType.longtext: 'نص طويل',
  FieldType.date: 'تاريخ',
  FieldType.time: 'وقت',
  FieldType.photos: 'صور',
};

class _FieldRow extends StatelessWidget {
  const _FieldRow({super.key, required this.field, required this.onChanged, required this.onRemove});
  final _FieldDraft field;
  final VoidCallback onChanged, onRemove;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: NSpace.sm),
        padding: const EdgeInsets.all(NSpace.sm),
        decoration: BoxDecoration(
          border: Border.all(color: NColors.line),
          borderRadius: const BorderRadius.all(NRadius.md),
        ),
        child: Column(children: [
          Row(children: [
            Expanded(
              flex: 3,
              child: TextField(controller: field.label, decoration: const InputDecoration(labelText: 'اسم الحقل', isDense: true)),
            ),
            const SizedBox(width: NSpace.sm),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<FieldType>(
                initialValue: field.type,
                isDense: true,
                decoration: const InputDecoration(labelText: 'النوع', isDense: true),
                items: [for (final e in _typeLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) {
                  field.type = v ?? FieldType.text;
                  onChanged();
                },
              ),
            ),
            const SizedBox(width: NSpace.sm),
            SizedBox(
              width: 84,
              child: TextField(
                controller: field.max,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: field.type == FieldType.photos ? 'أقصى صور' : 'أقصى حروف', isDense: true),
              ),
            ),
            IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline_rounded, color: NColors.danger)),
          ]),
          Row(children: [
            Expanded(
              child: TextField(
                  controller: field.hint, decoration: const InputDecoration(labelText: 'مثال أو توضيح', isDense: true)),
            ),
            const SizedBox(width: NSpace.sm),
            const Text('إلزامي'),
            Switch(
              value: field.required,
              onChanged: (v) {
                field.required = v;
                onChanged();
              },
            ),
          ]),
        ]),
      );
}
