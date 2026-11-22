import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/format/money.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/theme/typography.dart';
import '../../../data/models/public_settings.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../draft/book_draft.dart';
import '../draft/draft_controller.dart';

class CoverPanel extends ConsumerStatefulWidget {
  const CoverPanel({super.key});

  @override
  ConsumerState<CoverPanel> createState() => _CoverPanelState();
}

class _CoverPanelState extends ConsumerState<CoverPanel> {
  late final TextEditingController _name;
  late final TextEditingController _notes;

  static const _fonts = <(String, String)>[
    (NFonts.ruqaa, 'رقعة'),
    (NFonts.display, 'كوفي'),
    (NFonts.naskh, 'نسخ'),
    (NFonts.playful, 'مرح'),
  ];
  static const _colors = <int>[0xFF2B2622, 0xFF4F7A6C, 0xFFBF9A5A, 0xFF6D8FB3, 0xFFC97B84];

  @override
  void initState() {
    super.initState();
    final c = ref.read(draftProvider).draft!.cover;
    _name = TextEditingController(text: c.childName);
    _notes = TextEditingController(text: c.designerNotes);
  }

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  CoverDesign get _c => ref.read(draftProvider).draft!.cover;
  void _update(CoverDesign c) => ref.read(draftProvider.notifier).updateCover(c);

  Future<void> _addPhoto() async {
    final ids = await ref.read(draftProvider.notifier).importPhotos(multiple: false);
    if (ids.isNotEmpty) _update(_c.copyWith(element: CoverElement(photoId: ids.first)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cover = ref.watch(draftProvider.select((s) => s.draft!.cover));
    final settings = ref.watch(publicSettingsProvider).value;
    final designerPrice = settings?.priceOf(Addon.designerCover) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('الغلاف', style: t.titleLarge),
        const SizedBox(height: NSpace.md),
        SegmentedButton<CoverMode>(
          segments: const [
            ButtonSegment(value: CoverMode.manual, label: Text('أصمّمه بنفسي'), icon: Icon(Icons.brush_outlined)),
            ButtonSegment(value: CoverMode.designer, label: Text('اتركه لذوقكم'), icon: Icon(Icons.auto_awesome_outlined)),
          ],
          selected: {cover.mode},
          onSelectionChanged: (s) => _update(cover.copyWith(mode: s.first)),
        ),
        const SizedBox(height: NSpace.lg),
        TextField(
          controller: _name,
          maxLength: 20,
          decoration: const InputDecoration(labelText: 'اسم الطفل على الغلاف', hintText: 'مثال: نسيم'),
          onChanged: (v) => _update(_c.copyWith(childName: v)),
        ),
        if (cover.mode == CoverMode.manual) ...[
          const SizedBox(height: NSpace.sm),
          Text('الخط', style: t.labelLarge),
          const SizedBox(height: NSpace.xs),
          Wrap(
            spacing: NSpace.sm,
            runSpacing: NSpace.sm,
            children: [
              for (final (family, label) in _fonts)
                ChoiceChip(
                  selected: cover.font == family,
                  onSelected: (_) => _update(cover.copyWith(font: family)),
                  label: Text(
                    cover.childName.trim().isEmpty ? label : cover.childName.trim(),
                    style: TextStyle(fontFamily: family, fontSize: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NSpace.md),
          Text('لون الاسم', style: t.labelLarge),
          const SizedBox(height: NSpace.xs),
          Wrap(
            spacing: NSpace.sm,
            children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => _update(cover.copyWith(color: c)),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: cover.color == c ? NColors.ink : NColors.line,
                          width: cover.color == c ? 3 : 1),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: NSpace.lg),
          Text('صورة أو ملصق على الغلاف (اختياري)', style: t.labelLarge),
          const SizedBox(height: NSpace.xs),
          if (cover.element == null)
            OutlinedButton.icon(
              onPressed: _addPhoto,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('أضيفي صورة على الغلاف'),
            )
          else ...[
            Text('اسحبي الصورة لتحريكها، وكبّريها أو دوّريها بإصبعين (أو بعجلة الفأرة).',
                style: t.bodySmall),
            const SizedBox(height: NSpace.xs),
            Wrap(spacing: NSpace.sm, children: [
              OutlinedButton(onPressed: _addPhoto, child: const Text('تغيير الصورة')),
              TextButton(
                onPressed: () => _update(cover.copyWith(clearElement: true)),
                child: const Text('إزالة'),
              ),
            ]),
          ],
          const SizedBox(height: NSpace.xs),
          Text('الملصقات الجاهزة تُضاف قريباً.', style: t.bodySmall),
        ] else ...[
          const SizedBox(height: NSpace.sm),
          Container(
            padding: const EdgeInsets.all(NSpace.md),
            decoration: const BoxDecoration(
              color: NColors.sageSoft,
              borderRadius: BorderRadius.all(NRadius.md),
            ),
            child: Text(
              'يصمم فريقنا غلافاً خاصاً باسم طفلك، ونرسل لكِ صورته قبل الطباعة.'
              '${designerPrice > 0 ? ' (+ ${formatIqd(designerPrice)})' : ''}',
              style: t.bodyMedium?.copyWith(color: NColors.sageDark),
            ),
          ),
          const SizedBox(height: NSpace.md),
          TextField(
            controller: _notes,
            maxLines: 3,
            maxLength: 300,
            decoration: const InputDecoration(
                labelText: 'ملاحظات للمصمم (اختياري)', hintText: 'ألوان تحبينها، فكرة معينة...'),
            onChanged: (v) => _update(_c.copyWith(designerNotes: v)),
          ),
        ],
      ],
    );
  }
}
