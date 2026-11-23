import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:turnable_page/turnable_page.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/page_template.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/widgets/layout.dart';
import '../cart/cart_controller.dart';
import '../editor/draft/book_draft.dart';
import '../editor/draft/draft_controller.dart';
import '../editor/draft/readiness.dart';
import '../editor/widgets/page_canvas.dart';
import '../../core/theme/lazy_fonts.dart';

/// Flip-through preview of the finished book: cover, endpaper, 34 pages,
/// endpaper, back cover. Right-to-left, two-page spreads on wide screens.
class PreviewPage extends ConsumerStatefulWidget {
  const PreviewPage({super.key, required this.book});
  final String book; // book id: the product slug, or slug~suffix for another child
  String get slug => slugOfBook(book);

  @override
  ConsumerState<PreviewPage> createState() => _PreviewPageState();
}

class _PreviewPageState extends ConsumerState<PreviewPage> {
  final _flip = PageFlipController();
  int _left = 0, _right = 0;

  @override
  void initState() {
    super.initState();
    LazyFonts.ensure();
    ref.read(draftProvider.notifier).load(widget.book);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftProvider).draft;
    final pages = ref.watch(templatesProvider(widget.slug));
    final product = ref.watch(productBySlugProvider(widget.slug));

    Widget body;
    if (pages.hasError || product.hasError) {
      body = LoadError(onRetry: () {
        ref.invalidate(templatesProvider(widget.slug));
        ref.invalidate(productBySlugProvider(widget.slug));
      });
    } else if (draft == null || draft.bookId != widget.book || !pages.hasValue || !product.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else if (product.value == null) {
      body = const Center(child: Text('هذا المنتج غير متوفر حالياً'));
    } else {
      body = _content(context, draft, pages.value!, product.value!);
    }

    return Scaffold(
      backgroundColor: NColors.paper,
      body: SafeArea(child: body),
    );
  }

  Widget _content(BuildContext context, BookDraft draft, List<PageTemplate> pages, Product product) {
    final cover = pages.firstWhere((p) => p.isCover);
    final inner = pages.where((p) => !p.isCover).toList()
      ..sort((a, b) => a.pageNumber.compareTo(b.pageNumber));
    final ready = Readiness.of(draft, pages, needsName: product.coverCustom);
    final count = inner.length + 4;

    Widget pageAt(int i) {
      Widget img(ImageProvider? p) => p == null
          ? const ColoredBox(color: NColors.surface)
          : Image(image: p, fit: BoxFit.cover, gaplessPlayback: true);
      if (i == 0) return FittedPage(template: cover, draft: draft);
      if (i == 1 || i == count - 2) return img(product.endpaperImage);
      if (i == count - 1) return img(product.backCoverImage);
      return FittedPage(template: inner[i - 2], draft: draft);
    }

    String label(int i) {
      if (i == 0) return 'الغلاف';
      if (i == 1 || i == count - 2) return 'باطن الغلاف';
      if (i == count - 1) return 'الغلاف الخلفي';
      return 'صفحة ${inner[i - 2].pageNumber}';
    }

    // Covers stand alone; a spread shows both facing pages.
    final shown = (_left == 0 || _right == 0)
        ? [0]
        : (_left == count - 1 || _right == count - 1)
            ? [count - 1]
            : ({_left, _right}.toList()..sort());
    final caption = shown.map(label).join('  ·  ');

    final book = LayoutBuilder(builder: (context, c) {
      final single = c.maxWidth < 600;
      final ratio = BookGeometry.pageW / BookGeometry.pageH * (single ? 1 : 2);
      return TurnablePage(
        key: ValueKey(single),
        controller: _flip,
        pageCount: count,
        pageViewMode: single ? PageViewMode.single : PageViewMode.double,
        aspectRatio: ratio,
        textDirection: TextDirection.rtl,
        paperBoundaryDecoration: PaperBoundaryDecoration.none,
        settings: FlipSettings(
          showCover: true,
          flippingTime: 650,
          pageBackgroundColor: NColors.paper,
        ),
        onPageChanged: (l, r) => setState(() {
          _left = l;
          _right = r < 0 ? l : r;
        }),
        builder: (context, i, _) => pageAt(i),
      );
    });

    final controls = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: 'السابقة',
          onPressed: () => _flip.previousPage(),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: NSpace.md),
          child: SizedBox(
            width: 220,
            child: Text(caption,
                textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleSmall),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'التالية',
          onPressed: () => _flip.nextPage(),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );

    final summary = _Summary(
      draft: draft,
      title: product.title,
      coverCustom: product.coverCustom,
      ready: ready,
      inCart: ref.watch(cartProvider).any((e) => e.book == widget.book),
      onEdit: () => context.go(Routes.editor(widget.book)),
      onAdd: () => _addToCart(context, ready),
      onCart: () => context.go(Routes.cart),
    );

    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final top = _TopBar(onBack: () => context.go(Routes.editor(widget.book)));

    if (wide) {
      return Column(children: [
        top,
        const Divider(height: 1, color: NColors.line),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(NSpace.lg),
                child: Column(children: [
                  Expanded(child: Center(child: book)),
                  const SizedBox(height: NSpace.md),
                  controls,
                ]),
              ),
            ),
            Container(
              width: 360,
              decoration: const BoxDecoration(
                color: NColors.surface,
                border: BorderDirectional(start: BorderSide(color: NColors.line)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(NSpace.lg),
                child: summary,
              ),
            ),
          ]),
        ),
      ]);
    }

    final h = MediaQuery.sizeOf(context).height;
    return Column(children: [
      top,
      const Divider(height: 1, color: NColors.line),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(NSpace.md),
          children: [
            SizedBox(height: (h * .62).clamp(320.0, 620.0), child: Center(child: book)),
            const SizedBox(height: NSpace.sm),
            controls,
            const SizedBox(height: NSpace.lg),
            summary,
          ],
        ),
      ),
    ]);
  }

  Future<void> _addToCart(BuildContext context, Readiness ready) async {
    if (ready.nameMissing) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('بدون اسم على الغلاف؟'),
          content: const Text('لم تكتبي اسم طفلك على الغلاف، فيُطبع الغلاف بتصميمه الأصلي. '
              'يمكنك إضافة الاسم الآن أو المتابعة بدونه.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('متابعة بدون اسم')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('أضيفي الاسم')),
          ],
        ),
      );
      if (ok == null || !context.mounted) return;
      if (!ok) {
        context.go(Routes.editor(widget.book));
        return;
      }
    }
    if (ready.emptySlots > 0) {
      final pagesList = ready.emptyPages.take(8).join('، ');
      final more = ready.emptyPages.length > 8 ? ' وغيرها' : '';
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text('إطارات بلا صورة: ${ready.emptySlots} من ${ready.totalSlots}'),
          content: Text('في الصفحات: $pagesList$more.\n'
              'الإطارات الفارغة تبقى كما هي في التصميم الأصلي. يمكنك إكمالها الآن أو المتابعة.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('أضيفي للسلة كما هو')),
            FilledButton(onPressed: () => Navigator.pop(c, false), child: const Text('أكملي الصور')),
          ],
        ),
      );
      if (ok == null || !context.mounted) return;
      if (!ok) {
        context.go(Routes.editor(widget.book));
        return;
      }
    }
    await ref.read(cartProvider.notifier).add(widget.book);
    if (context.mounted) context.go(Routes.cart);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: NSpace.sm, vertical: NSpace.sm),
      child: Row(children: [
        IconButton(
            tooltip: 'رجوع للتصميم', onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded)),
        Expanded(
          child: Text('معاينة كتابك',
              style: isMobile(context) ? t.titleMedium : t.titleLarge,
              overflow: TextOverflow.ellipsis),
        ),
        Text('اسحبي طرف الصفحة لتقليبها', style: t.labelSmall),
        const SizedBox(width: NSpace.md),
      ]),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.draft,
    required this.ready,
    required this.inCart,
    required this.onEdit,
    required this.onAdd,
    required this.onCart,
    this.title = 'كتاب نسيم',
    this.coverCustom = true,
  });

  final BookDraft draft;
  final String title;
  final bool coverCustom;
  final Readiness ready;
  final bool inCart;
  final VoidCallback onEdit, onAdd, onCart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final filled = ready.totalSlots - ready.emptySlots;
    final name = draft.cover.childName.trim();

    Widget row(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: NSpace.sm),
            Expanded(child: Text(text, style: t.bodyMedium)),
          ]),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(!coverCustom ? title : name.isEmpty ? title : '$title · $name', style: t.headlineSmall),
        const SizedBox(height: NSpace.md),
        if (coverCustom)
          ready.nameMissing
              ? row(Icons.info_outline_rounded, NColors.warning, 'بدون اسم على الغلاف')
              : row(Icons.check_circle_rounded, NColors.success, 'الاسم على الغلاف: $name'),
        ready.emptySlots == 0
            ? row(Icons.check_circle_rounded, NColors.success, 'كل الإطارات فيها صور ($filled)')
            : row(Icons.info_outline_rounded, NColors.warning,
                'الإطارات المملوءة بالصور: $filled من ${ready.totalSlots}'),
        if (coverCustom)
        row(
          draft.cover.mode == CoverMode.designer ? Icons.auto_awesome_outlined : Icons.brush_outlined,
          NColors.inkMuted,
          draft.cover.mode == CoverMode.designer ? 'الغلاف: نصممه لكِ' : 'الغلاف: من تصميمك',
        ),
        if (draft.hasPrintedText)
          row(Icons.edit_note_rounded, NColors.inkMuted, 'فيه نص مطبوع داخل الصفحات'),
        const SizedBox(height: NSpace.lg),
        if (inCart)
          FilledButton.icon(
            onPressed: onCart,
            icon: const Icon(Icons.shopping_bag_outlined),
            label: const Text('الكتاب في سلتك، اذهبي للسلة'),
          )
        else
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('أضيفي إلى السلة'),
          ),
        const SizedBox(height: NSpace.sm),
        OutlinedButton.icon(
          onPressed: onEdit,
          icon: const Icon(Icons.edit_outlined),
          label: const Text('عودي للتعديل'),
        ),
      ],
    );
  }
}
