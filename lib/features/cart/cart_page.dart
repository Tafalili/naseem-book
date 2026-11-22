import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/page_template.dart';
import '../../data/models/product.dart';
import '../../data/models/public_settings.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/privacy_badge.dart';
import '../editor/draft/book_draft.dart';
import '../editor/draft/draft_controller.dart';
import '../editor/draft/readiness.dart';
import '../editor/widgets/page_canvas.dart';
import 'cart_controller.dart';
import 'pricing.dart';

class CartPage extends ConsumerWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(cartProvider);
    final t = Theme.of(context).textTheme;
    return ContentWidth(
      vertical: NSpace.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('سلتك', style: t.headlineMedium),
          const SizedBox(height: NSpace.lg),
          if (items.isEmpty) const _Empty() else _CartBody(items: items),
        ],
      ),
    );
  }
}

/// Everything one cart line needs, loaded.
class CartBook {
  const CartBook({required this.item, required this.product, required this.draft, required this.pages});
  final CartItem item;
  final Product product;
  final BookDraft draft;
  final List<PageTemplate> pages;
}

/// Loads every book in the cart. Null while loading; throws on load errors.
List<CartBook>? watchCartBooks(WidgetRef ref, List<CartItem> items) {
  final out = <CartBook>[];
  var loading = false;
  for (final it in items) {
    final draft = ref.watch(savedDraftProvider(it.book));
    final pages = ref.watch(templatesProvider(it.slug));
    final product = ref.watch(productBySlugProvider(it.slug));
    for (final a in [draft, pages, product]) {
      if (a.hasError) throw a.error!;
    }
    if (!draft.hasValue || !pages.hasValue || !product.hasValue) {
      loading = true;
      continue;
    }
    final p = product.value;
    if (p == null) continue; // product withdrawn; the line is dropped
    out.add(CartBook(item: it, product: p, draft: draft.value!, pages: pages.value!));
  }
  return loading ? null : out;
}

OrderQuote quoteCart(List<CartBook> books, PublicSettings settings) => OrderQuote([
      for (final b in books)
        buildQuote(
          product: b.product,
          settings: settings,
          draft: b.draft,
          item: b.item,
          pages: b.pages,
          multiBook: books.length > 1,
        ),
    ], settings);

String bookTitle(CartBook b, int index) {
  final name = b.draft.cover.childName.trim();
  return name.isEmpty ? 'الكتاب ${index + 1}' : 'كتاب $name';
}

class _CartBody extends ConsumerWidget {
  const _CartBody({required this.items});
  final List<CartItem> items;

  void _retry(WidgetRef ref) {
    for (final it in items) {
      ref.invalidate(savedDraftProvider(it.book));
      ref.invalidate(templatesProvider(it.slug));
      ref.invalidate(productBySlugProvider(it.slug));
    }
    ref.invalidate(publicSettingsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(publicSettingsProvider);
    List<CartBook>? books;
    try {
      books = watchCartBooks(ref, items);
      if (settings.hasError) throw settings.error!;
    } catch (_) {
      return LoadError(onRetry: () => _retry(ref));
    }
    if (books == null || !settings.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(NSpace.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (books.isEmpty) return const _Empty();
    final quote = quoteCart(books, settings.value!);

    final left = Column(children: [
      for (var i = 0; i < books.length; i++) ...[
        _BookCard(book: books[i], title: books.length > 1 ? 'الكتاب ${i + 1} من ${books.length}' : null),
        const SizedBox(height: NSpace.md),
        _Extras(book: books[i], settings: settings.value!, quote: quote.books[i]),
        const SizedBox(height: NSpace.lg),
      ],
      _AddChild(slug: books.first.product.slug, settings: settings.value!, count: books.length),
    ]);
    final right = _Summary(quote: quote, books: books);

    if (MediaQuery.sizeOf(context).width >= 1000) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: left),
        const SizedBox(width: NSpace.lg),
        SizedBox(width: 380, child: right),
      ]);
    }
    return Column(children: [left, const SizedBox(height: NSpace.lg), right]);
  }
}

/// Starts another book (another child) of the same product.
class _AddChild extends ConsumerWidget {
  const _AddChild({required this.slug, required this.settings, required this.count});
  final String slug;
  final PublicSettings settings;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    if (count >= CartController.maxBooks) return const SizedBox.shrink();
    final save = settings.priceOf(Addon.childName);
    return Container(
      padding: const EdgeInsets.all(NSpace.md),
      decoration: BoxDecoration(
        color: NColors.sage.withValues(alpha: .08),
        borderRadius: const BorderRadius.all(NRadius.lg),
        border: Border.all(color: NColors.sage.withValues(alpha: .35)),
      ),
      child: Builder(builder: (context) {
        final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('عندك أكثر من طفل؟', style: t.titleSmall),
          Text(
              save > 0
                  ? 'صمّمي كتاباً لكل طفل في نفس الطلب، ويصبح تخصيص الغلاف مجانياً لكل كتاب (توفير ${formatIqd(save)} للكتاب).'
                  : 'صمّمي كتاباً لكل طفل في نفس الطلب.',
              style: t.bodySmall),
        ]);
        final button = FilledButton.tonalIcon(
          onPressed: () => context.go(Routes.editor(newBookId(slug))),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('كتاب لطفل آخر'),
        );
        const icon = Icon(Icons.child_care_rounded, color: NColors.sageDark);
        if (isMobile(context)) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [icon, const SizedBox(width: NSpace.md), Expanded(child: text)]),
            const SizedBox(height: NSpace.sm),
            button,
          ]);
        }
        return Row(children: [
          icon,
          const SizedBox(width: NSpace.md),
          Expanded(child: text),
          const SizedBox(width: NSpace.sm),
          button,
        ]);
      }),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: NSpace.xxl, horizontal: NSpace.lg),
      decoration: const BoxDecoration(
        color: NColors.surface,
        borderRadius: BorderRadius.all(NRadius.lg),
      ),
      child: Column(children: [
        const Icon(Icons.shopping_bag_outlined, size: 48, color: NColors.sage),
        const SizedBox(height: NSpace.md),
        Text('سلتك فارغة', style: t.titleLarge),
        const SizedBox(height: NSpace.xs),
        Text('صمّمي كتاب طفلك أولاً، ثم أضيفيه إلى السلة من شاشة المعاينة.',
            textAlign: TextAlign.center, style: t.bodyMedium),
        const SizedBox(height: NSpace.lg),
        FilledButton(
          onPressed: () => context.go(Routes.product('naseem-classic')),
          child: const Text('صمّمي كتابك'),
        ),
      ]),
    );
  }
}

BoxDecoration get _card => const BoxDecoration(
      color: NColors.surface,
      borderRadius: BorderRadius.all(NRadius.lg),
      boxShadow: NShadow.soft,
    );

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.book, this.title});
  final CartBook book;
  final String? title;

  Product get product => book.product;
  BookDraft get draft => book.draft;
  List<PageTemplate> get pages => book.pages;
  CartItem get item => book.item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final ready = Readiness.of(draft, pages);
    final cover = pages.firstWhere((e) => e.isCover);
    final name = draft.cover.childName.trim();
    final mobile = isMobile(context);

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) Text(title!, style: t.labelLarge?.copyWith(color: NColors.sageDark)),
        Text(name.isEmpty ? product.title : '${product.title} · $name', style: t.titleLarge),
        const SizedBox(height: NSpace.sm),
        Text('${product.pageCount} صفحة · ${ready.totalSlots - ready.emptySlots} من ${ready.totalSlots} صورة',
            style: t.bodyMedium),
        Text(draft.cover.mode == CoverMode.designer ? 'الغلاف: نصممه لكِ' : 'الغلاف: من تصميمك',
            style: t.bodyMedium),
        if (ready.emptySlots > 0)
          Padding(
            padding: const EdgeInsets.only(top: NSpace.xs),
            child: Text('إطارات بلا صورة: ${ready.emptySlots}',
                style: t.bodySmall?.copyWith(color: NColors.warning)),
          ),
        const SizedBox(height: NSpace.md),
        Wrap(spacing: NSpace.sm, runSpacing: NSpace.sm, children: [
          OutlinedButton.icon(
            onPressed: () => context.go(Routes.preview(item.book)),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('معاينة'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go(Routes.editor(item.book)),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('تعديل'),
          ),
          TextButton.icon(
            onPressed: () => _confirmRemove(context, ref),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            label: const Text('إزالة'),
            style: TextButton.styleFrom(foregroundColor: NColors.danger),
          ),
        ]),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(NSpace.md),
      decoration: _card,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: mobile ? 96 : 140,
          decoration: const BoxDecoration(boxShadow: NShadow.soft),
          child: AspectRatio(
            aspectRatio: cover.widthMm / cover.heightMm,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              child: FittedPage(template: cover, draft: draft),
            ),
          ),
        ),
        const SizedBox(width: NSpace.md),
        Expanded(child: info),
      ]),
    );
  }

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إزالة الكتاب من السلة؟'),
        content: const Text('يبقى تصميمك وصورك محفوظة على جهازك، ويمكنك إضافته مرة أخرى.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إزالة')),
        ],
      ),
    );
    if (ok == true) await ref.read(cartProvider.notifier).remove(item.book);
  }
}

class _Extras extends ConsumerWidget {
  const _Extras({required this.book, required this.settings, required this.quote});
  final CartBook book;
  final Quote quote;
  final PublicSettings settings;

  CartItem get item => book.item;
  BookDraft get draft => book.draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cart = ref.read(cartProvider.notifier);
    final photosLine = quote.lines.where((l) => l.label.startsWith(Addon.photos.label)).firstOrNull;
    String price(Addon a) => settings.priceOf(a) > 0 ? '+ ${formatIqd(settings.priceOf(a))}' : 'السعر قريباً';

    final free = quote.lines.any((l) => l.free);
    Widget auto(Addon a, String why, {QuoteLine? line}) {
      final isFree = free && (a == Addon.childName || a == Addon.designerCover);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.check_circle_rounded, color: NColors.sage),
        title: Text(line?.label ?? a.label),
        subtitle: Text(isFree ? '$why · مجاناً لأن طلبك فيه أكثر من كتاب' : why),
        trailing: Text(
            isFree
                ? 'مجاناً'
                : line != null && !line.unpriced
                    ? '+ ${formatIqd(line.amount)}'
                    : price(a),
            style: t.labelLarge?.copyWith(color: isFree ? NColors.sageDark : null)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(NSpace.md),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('إضافات اختيارية', style: t.titleMedium),
          Text('من لا تختار أي إضافة تدفع سعر الكتاب فقط.', style: t.bodySmall),
          const SizedBox(height: NSpace.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: item.giftWrap,
            onChanged: (v) => cart.update(item.copyWith(giftWrap: v)),
            title: Text(Addon.giftWrap.label),
            subtitle: Text('${Addon.giftWrap.hint} · ${price(Addon.giftWrap)}'),
          ),
          if (draft.hasPrintedText ||
              draft.cover.mode == CoverMode.designer ||
              draft.cover.childName.trim().isNotEmpty ||
              photosLine != null) ...[
            const Divider(color: NColors.line),
            if (draft.cover.childName.trim().isNotEmpty && draft.cover.mode != CoverMode.designer)
              auto(Addon.childName, 'أُضيف لأنك كتبتِ اسم طفلك على الغلاف'),
            if (photosLine != null)
              auto(Addon.photos, 'أُضيف لأنك وضعتِ صوراً داخل الكتاب', line: photosLine),
            if (draft.hasPrintedText)
              auto(Addon.printedText, 'أُضيف لأنك كتبتِ نصاً داخل الصفحات'),
            if (draft.cover.mode == CoverMode.designer)
              auto(Addon.designerCover, 'أُضيف لأنك اخترتِ «اتركه لذوقكم»'),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.quote, required this.books});
  final OrderQuote quote;
  final List<CartBook> books;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String amount(QuoteLine l) => l.free ? 'مجاناً' : l.unpriced ? 'قريباً' : formatIqd(l.amount);
    final multi = books.length > 1;
    final priced = !quote.hasUnpriced;

    Widget line(String a, String b, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(a, style: style ?? t.bodyMedium)),
            Text(b, style: style ?? t.bodyMedium),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: _card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ملخص الطلب', style: t.titleMedium),
          const SizedBox(height: NSpace.sm),
          for (var i = 0; i < books.length; i++) ...[
            if (multi)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : NSpace.sm),
                child: Text(bookTitle(books[i], i), style: t.labelLarge?.copyWith(color: NColors.sageDark)),
              ),
            for (final l in quote.books[i].lines)
              line(l.qty > 1 ? '${l.label} × ${l.qty}' : l.label, amount(l)),
          ],
          const Divider(height: NSpace.lg, color: NColors.line),
          if (quote.saved > 0)
            line('وفّرتِ (غلاف مجاني لكل كتاب)', formatIqd(quote.saved),
                style: t.bodyMedium?.copyWith(color: NColors.sageDark)),
          line('الإجمالي', priced ? formatIqd(quote.total) : 'قريباً', style: t.titleMedium),
          if (priced && quote.hasDeposit)
            line('العربون', formatIqd(quote.deposit),
                style: t.bodyMedium?.copyWith(color: NColors.sageDark, fontWeight: FontWeight.w600)),
          if (!priced)
            Padding(
              padding: const EdgeInsets.only(top: NSpace.xs),
              child: Text('الأسعار تُعلن قريباً، ويُحسب المبلغ النهائي عند تأكيد الطلب.',
                  style: t.bodySmall),
            ),
          const SizedBox(height: NSpace.lg),
          FilledButton(
            onPressed: () => context.go(Routes.checkout),
            child: const Text('متابعة لإتمام الطلب'),
          ),
          const SizedBox(height: NSpace.md),
          const PrivacyBadge(dense: true),
        ],
      ),
    );
  }
}
