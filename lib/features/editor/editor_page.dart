import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/page_template.dart';
import '../../data/models/public_settings.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/widgets/layout.dart';
import 'draft/book_draft.dart';
import 'draft/draft_controller.dart';
import 'widgets/cover_panel.dart';
import 'widgets/page_canvas.dart';
import 'widgets/photo_tray.dart';

class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key, required this.slug});
  final String slug;

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  int _index = 0; // 0 = cover
  String? _selected;

  @override
  void initState() {
    super.initState();
    ref.read(draftProvider.notifier).load(widget.slug);
  }

  void _go(int i, int count) => setState(() {
        _index = i.clamp(0, count - 1);
        _selected = null;
      });

  @override
  Widget build(BuildContext context) {
    final templates = ref.watch(templatesProvider(widget.slug));
    final draft = ref.watch(draftProvider.select((s) => s.draft));

    return Scaffold(
      body: SafeArea(
        child: templates.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => LoadError(onRetry: () => ref.invalidate(templatesProvider(widget.slug))),
          data: (pages) {
            if (draft == null || pages.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            return _EditorBody(
              slug: widget.slug,
              pages: pages,
              draft: draft,
              index: _index.clamp(0, pages.length - 1),
              selected: _selected,
              onIndex: (i) => _go(i, pages.length),
              onSelect: (id) => setState(() => _selected = id),
            );
          },
        ),
      ),
    );
  }
}

class _EditorBody extends ConsumerWidget {
  const _EditorBody({
    required this.slug,
    required this.pages,
    required this.draft,
    required this.index,
    required this.selected,
    required this.onIndex,
    required this.onSelect,
  });

  final String slug;
  final List<PageTemplate> pages;
  final BookDraft draft;
  final int index;
  final String? selected;
  final ValueChanged<int> onIndex;
  final ValueChanged<String?> onSelect;

  PageTemplate get page => pages[index];

  List<String> get _allSlotIds => [for (final p in pages) ...p.photoSlots.map((s) => s.id)];

  /// Where a tray photo goes: the selected slot, else the first empty slot on this page.
  String? _targetSlot() {
    if (selected != null && page.photoSlots.any((s) => s.id == selected)) return selected;
    for (final s in page.photoSlots) {
      if (!draft.placements.containsKey(s.id)) return s.id;
    }
    return null;
  }

  Future<void> _assign(BuildContext context, WidgetRef ref, String photoId) async {
    final target = _targetSlot();
    if (target == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اختاري إطاراً في الصفحة أولاً، أو انتقلي لصفحة فيها إطار فارغ')));
      return;
    }
    final replacing = target == selected;
    await ref.read(draftProvider.notifier).place(target, photoId);
    // Filling an empty frame keeps the next tap going to the next empty one;
    // replacing keeps the frame selected for adjustment.
    if (!replacing) onSelect(null);
  }

  Future<void> _onSlotTap(BuildContext context, WidgetRef ref, PhotoSlot s) async {
    if (draft.placements.containsKey(s.id)) {
      onSelect(selected == s.id ? null : s.id);
      return;
    }
    onSelect(s.id);
    final ids = await ref.read(draftProvider.notifier).importPhotos(multiple: false);
    if (ids.isNotEmpty) await ref.read(draftProvider.notifier).place(s.id, ids.first);
  }

  Future<void> _editText(BuildContext context, WidgetRef ref, TextSlot t) async {
    final settings = ref.read(publicSettingsProvider).value;
    final price = settings?.priceOf(Addon.printedText) ?? 0;
    final c = TextEditingController(text: draft.texts[t.id] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نص مطبوع'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اختياري تماماً. إن تركتِه فارغاً تبقى الأسطر لتكتبي عليها بخط يدك.'
                '${price > 0 ? '\nالنص المطبوع إضافة بسعر ${formatIqd(price)} للكتاب.' : ''}',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: NSpace.md),
              TextField(
                controller: c,
                autofocus: true,
                maxLines: t.lines,
                maxLength: t.lines * 70,
                decoration: const InputDecoration(hintText: 'اكتبي هنا...'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('مسح')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('حفظ')),
        ],
      ),
    );
    if (result != null) await ref.read(draftProvider.notifier).setText(t.id, result);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final filled = _allSlotIds.where(draft.placements.containsKey).length;
    final total = _allSlotIds.length;

    final canvas = PageCanvas(
      template: page,
      draft: draft,
      interactive: true,
      selectedSlotId: selected,
      onSlotTap: (s) => _onSlotTap(context, ref, s),
      onTextTap: (t) => _editText(context, ref, t),
      onPlacementChanged: (id, p) => ref.read(draftProvider.notifier).updatePlacement(id, p),
      onCoverElementChanged: (e) =>
          ref.read(draftProvider.notifier).updateCover(draft.cover.copyWith(element: e)),
    );

    final panel = page.isCover
        ? const CoverPanel()
        : _PagePanel(
            page: page,
            draft: draft,
            selected: selected,
            onPick: (id) => _assign(context, ref, id),
            onAutoFill: () async {
              final n = await ref.read(draftProvider.notifier).autoFill(_allSlotIds);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(n == 0 ? 'لا توجد صور غير مستخدمة أو إطارات فارغة' : 'وُزّعت $n صورة على الإطارات الفارغة')));
              }
            },
            onClear: (id) {
              ref.read(draftProvider.notifier).clearSlot(id);
              onSelect(null);
            },
            onReset: (id) {
              final p = draft.placements[id];
              if (p != null) {
                ref.read(draftProvider.notifier).updatePlacement(id, p.copyWith(scale: 1, dx: 0, dy: 0));
              }
            },
          );

    final topBar = _TopBar(
      filled: filled,
      total: total,
      onBack: () => context.go(Routes.product(slug)),
      onPreview: () => context.go(Routes.preview(slug)),
    );

    final nav = _PageNav(
      index: index,
      count: pages.length,
      title: page.isCover ? 'الغلاف' : 'صفحة ${page.pageNumber} · ${page.title}',
      onIndex: onIndex,
    );

    if (wide) {
      return Column(
        children: [
          topBar,
          const Divider(height: 1, color: NColors.line),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 132,
                  child: _Thumbnails(pages: pages, draft: draft, index: index, onIndex: onIndex),
                ),
                const VerticalDivider(width: 1, color: NColors.line),
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(NSpace.lg),
                          child: Center(
                            child: Container(
                              decoration: const BoxDecoration(boxShadow: NShadow.lifted),
                              child: canvas,
                            ),
                          ),
                        ),
                      ),
                      nav,
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, color: NColors.line),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(NSpace.lg),
                    child: panel,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        topBar,
        SizedBox(
          height: 86,
          child: _Thumbnails(
              pages: pages, draft: draft, index: index, onIndex: onIndex, horizontal: true),
        ),
        const Divider(height: 1, color: NColors.line),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(NSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Container(
                      decoration: const BoxDecoration(boxShadow: NShadow.soft),
                      child: canvas,
                    ),
                  ),
                ),
                const SizedBox(height: NSpace.lg),
                panel,
              ],
            ),
          ),
        ),
        nav,
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.filled,
    required this.total,
    required this.onBack,
    required this.onPreview,
  });
  final int filled, total;
  final VoidCallback onBack, onPreview;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mobile = isMobile(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NSpace.sm, vertical: NSpace.sm),
      child: Row(
        children: [
          IconButton(
            tooltip: 'رجوع',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Text('تصميم كتاب نسيم',
                style: (mobile ? t.titleMedium : t.titleLarge), overflow: TextOverflow.ellipsis),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: NColors.sageSoft,
              borderRadius: BorderRadius.all(NRadius.pill),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.photo_outlined, size: 16, color: NColors.sageDark),
              const SizedBox(width: 6),
              Text('$filled / $total', style: t.labelLarge?.copyWith(color: NColors.sageDark)),
            ]),
          ),
          const SizedBox(width: NSpace.sm),
          if (!mobile) ...[
            const Icon(Icons.cloud_done_outlined, size: 18, color: NColors.inkMuted),
            const SizedBox(width: 4),
            Text('محفوظ على جهازك', style: t.labelSmall),
            const SizedBox(width: NSpace.md),
          ],
          FilledButton.icon(
            onPressed: onPreview,
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('معاينة'),
          ),
          const SizedBox(width: NSpace.sm),
        ],
      ),
    );
  }
}

class _PageNav extends StatelessWidget {
  const _PageNav({required this.index, required this.count, required this.title, required this.onIndex});
  final int index, count;
  final String title;
  final ValueChanged<int> onIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: NColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: NSpace.sm, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'السابقة',
            onPressed: index > 0 ? () => onIndex(index - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Text(title,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          IconButton(
            tooltip: 'التالية',
            onPressed: index < count - 1 ? () => onIndex(index + 1) : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _Thumbnails extends StatelessWidget {
  const _Thumbnails({
    required this.pages,
    required this.draft,
    required this.index,
    required this.onIndex,
    this.horizontal = false,
  });
  final List<PageTemplate> pages;
  final BookDraft draft;
  final int index;
  final ValueChanged<int> onIndex;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView.separated(
      scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
      padding: const EdgeInsets.all(NSpace.sm),
      itemCount: pages.length,
      separatorBuilder: (_, _) => const SizedBox(width: NSpace.sm, height: NSpace.sm),
      itemBuilder: (_, i) {
        final p = pages[i];
        final total = p.photoSlots.length;
        final filled = p.photoSlots.where((s) => draft.placements.containsKey(s.id)).length;
        final done = p.isCover ? draft.cover.childName.trim().isNotEmpty : filled == total;
        final bg = p.background;
        return GestureDetector(
          onTap: () => onIndex(i),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Container(
                      width: horizontal ? 44 : 96,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: i == index ? NColors.sage : NColors.line, width: i == index ? 3 : 1),
                        borderRadius: const BorderRadius.all(Radius.circular(4)),
                      ),
                      child: AspectRatio(
                        aspectRatio: p.widthMm / p.heightMm,
                        child: bg == null ? const SizedBox() : Image(image: bg, fit: BoxFit.cover),
                      ),
                    ),
                    if (total > 0 || p.isCover)
                      PositionedDirectional(
                        bottom: 2,
                        start: 2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: done ? NColors.sage : const Color(0xCC3B3631),
                            borderRadius: const BorderRadius.all(NRadius.pill),
                          ),
                          child: done
                              ? const Icon(Icons.check, size: 10, color: Colors.white)
                              : Text(p.isCover ? '!' : '$filled/$total',
                                  style: const TextStyle(color: Colors.white, fontSize: 9)),
                        ),
                      ),
                  ],
                ),
                if (!horizontal) ...[
                  const SizedBox(height: 2),
                  Text(p.isCover ? 'الغلاف' : '${p.pageNumber}', style: t.labelSmall),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PagePanel extends StatelessWidget {
  const _PagePanel({
    required this.page,
    required this.draft,
    required this.selected,
    required this.onPick,
    required this.onAutoFill,
    required this.onClear,
    required this.onReset,
  });

  final PageTemplate page;
  final BookDraft draft;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback onAutoFill;
  final ValueChanged<String> onClear, onReset;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final sel = page.photoSlots.where((s) => s.id == selected).firstOrNull;
    final selFilled = sel != null && draft.placements.containsKey(sel.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(page.title, style: t.titleLarge),
        const SizedBox(height: NSpace.xs),
        Text(
          page.photoSlots.isEmpty
              ? 'لا توجد صور في هذه الصفحة. تُطبع كما هي، وتكتبين عليها بخط يدك.'
              : 'اضغطي على إطار لإضافة صورة. بعد إضافتها اسحبيها لتحريكها، وكبّريها بإصبعين أو بعجلة الفأرة.',
          style: t.bodySmall,
        ),
        if (selFilled) ...[
          const SizedBox(height: NSpace.md),
          Wrap(spacing: NSpace.sm, runSpacing: NSpace.sm, children: [
            OutlinedButton.icon(
              onPressed: () => onReset(sel.id),
              icon: const Icon(Icons.fit_screen_outlined, size: 18),
              label: const Text('ملاءمة الإطار'),
            ),
            TextButton.icon(
              onPressed: () => onClear(sel.id),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('إزالة الصورة'),
            ),
          ]),
        ],
        const SizedBox(height: NSpace.lg),
        PhotoTray(onPick: onPick),
        if (draft.photos.isNotEmpty) ...[
          const SizedBox(height: NSpace.md),
          TextButton.icon(
            onPressed: onAutoFill,
            icon: const Icon(Icons.auto_fix_high_outlined),
            label: const Text('وزّعي الصور غير المستخدمة تلقائياً'),
          ),
        ],
      ],
    );
  }
}
