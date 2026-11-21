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
          if (items.isEmpty)
            const _Empty()
          else
            // One designed book per product; the store sells one book today.
            _CartLine(item: items.first),
        ],
      ),
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

class _CartLine extends ConsumerStatefulWidget {
  const _CartLine({required this.item});
  final CartItem item;

  @override
  ConsumerState<_CartLine> createState() => _CartLineState();
}

class _CartLineState extends ConsumerState<_CartLine> {
  @override
  void initState() {
    super.initState();
    ref.read(draftProvider.notifier).load(widget.item.slug);
  }

  @override
  Widget build(BuildContext context) {
    final slug = widget.item.slug;
    final draft = ref.watch(draftProvider).draft;
    final pages = ref.watch(templatesProvider(slug));
    final product = ref.watch(productBySlugProvider(slug));
    final settings = ref.watch(publicSettingsProvider);

    if (pages.hasError || product.hasError || settings.hasError) {
      return LoadError(onRetry: () {
        ref.invalidate(templatesProvider(slug));
        ref.invalidate(productBySlugProvider(slug));
        ref.invalidate(publicSettingsProvider);
      });
    }
    if (draft == null ||
        draft.productSlug != slug ||
        !pages.hasValue ||
        !product.hasValue ||
        !settings.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(NSpace.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final p = product.value;
    if (p == null) {
      return const Text('هذا المنتج لم يعد متوفراً. احذفيه من السلة.');
    }

    final item = widget.item;
    final quote = buildQuote(product: p, settings: settings.value!, draft: draft, item: item);
    final left = Column(children: [
      _BookCard(product: p, draft: draft, pages: pages.value!, item: item),
      const SizedBox(height: NSpace.lg),
      _Extras(item: item, settings: settings.value!, draft: draft),
    ]);
    final right = _Summary(quote: quote);

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

BoxDecoration get _card => const BoxDecoration(
      color: NColors.surface,
      borderRadius: BorderRadius.all(NRadius.lg),
      boxShadow: NShadow.soft,
    );

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.product, required this.draft, required this.pages, required this.item});
  final Product product;
  final BookDraft draft;
  final List<PageTemplate> pages;
  final CartItem item;

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
            onPressed: () => context.go(Routes.preview(item.slug)),
            icon: const Icon(Icons.menu_book_outlined, size: 18),
            label: const Text('معاينة'),
          ),
          OutlinedButton.icon(
            onPressed: () => context.go(Routes.editor(item.slug)),
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
    if (ok == true) await ref.read(cartProvider.notifier).remove(item.slug);
  }
}

class _Extras extends ConsumerWidget {
  const _Extras({required this.item, required this.settings, required this.draft});
  final CartItem item;
  final PublicSettings settings;
  final BookDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final cart = ref.read(cartProvider.notifier);
    String price(Addon a) => settings.priceOf(a) > 0 ? '+ ${formatIqd(settings.priceOf(a))}' : 'السعر قريباً';

    Widget auto(Addon a, String why) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle_rounded, color: NColors.sage),
          title: Text(a.label),
          subtitle: Text(why),
          trailing: Text(price(a), style: t.labelLarge),
        );

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
          const Divider(color: NColors.line),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Addon.extraCopy.label, style: t.bodyLarge),
                Text('${Addon.extraCopy.hint} · ${price(Addon.extraCopy)} للنسخة', style: t.bodySmall),
              ]),
            ),
            IconButton.outlined(
              tooltip: 'إنقاص',
              onPressed: item.extraCopies > 0
                  ? () => cart.update(item.copyWith(extraCopies: item.extraCopies - 1))
                  : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 36,
              child: Text('${item.extraCopies}', textAlign: TextAlign.center, style: t.titleMedium),
            ),
            IconButton.outlined(
              tooltip: 'زيادة',
              onPressed: item.extraCopies < CartItem.maxExtraCopies
                  ? () => cart.update(item.copyWith(extraCopies: item.extraCopies + 1))
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ]),
          if (draft.hasPrintedText || draft.cover.mode == CoverMode.designer) ...[
            const Divider(color: NColors.line),
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
  const _Summary({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    String amount(QuoteLine l) => l.unpriced ? 'قريباً' : formatIqd(l.amount);
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
          for (final l in quote.lines)
            line(l.qty > 1 ? '${l.label} × ${l.qty}' : l.label, amount(l)),
          const Divider(height: NSpace.lg, color: NColors.line),
          line('الإجمالي', priced ? formatIqd(quote.total) : 'قريباً', style: t.titleMedium),
          if (priced && quote.depositPercent > 0)
            line('العربون (${quote.depositPercent.round()}%)', formatIqd(quote.deposit),
                style: t.bodyMedium?.copyWith(color: NColors.sageDark, fontWeight: FontWeight.w600)),
          if (!priced)
            Padding(
              padding: const EdgeInsets.only(top: NSpace.xs),
              child: Text('الأسعار تُعلن قريباً، ويُحسب المبلغ النهائي عند تأكيد الطلب.',
                  style: t.bodySmall),
            ),
          const SizedBox(height: NSpace.lg),
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('إتمام الطلب ودفع العربون يُفعّل في التحديث القادم'))),
            child: const Text('متابعة لإتمام الطلب'),
          ),
          const SizedBox(height: NSpace.md),
          const PrivacyBadge(dense: true),
        ],
      ),
    );
  }
}
