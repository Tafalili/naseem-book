import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/product.dart';
import '../../data/models/public_settings.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/widgets/book_mock.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/privacy_badge.dart';

class ProductPage extends ConsumerWidget {
  const ProductPage({super.key, required this.slug});
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final product = ref.watch(productBySlugProvider(slug));
    return product.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(NSpace.xxxl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => LoadError(onRetry: () => ref.invalidate(productBySlugProvider(slug))),
      data: (p) => p == null ? const _NotFound() : _ProductView(product: p),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();
  @override
  Widget build(BuildContext context) => ContentWidth(
        vertical: NSpace.xxxl,
        child: Column(
          children: [
            Text('هذا المنتج غير متوفر حالياً', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: NSpace.md),
            FilledButton(
                onPressed: () => context.go(Routes.home), child: const Text('العودة للمتجر')),
          ],
        ),
      );
}

class _ProductView extends ConsumerStatefulWidget {
  const _ProductView({required this.product});
  final Product product;

  @override
  ConsumerState<_ProductView> createState() => _ProductViewState();
}

class _ProductViewState extends ConsumerState<_ProductView> {
  int _image = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final mobile = isMobile(context);
    final images = [if (p.coverUrl != null) p.coverUrl!, ...p.galleryUrls];

    final gallery = Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: const BoxDecoration(
              color: NColors.sandSoft,
              borderRadius: BorderRadius.all(NRadius.lg),
            ),
            padding: const EdgeInsets.all(NSpace.xl),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: images.isEmpty
                  ? const Center(child: BookMock())
                  : ClipRRect(
                      key: ValueKey(_image),
                      borderRadius: const BorderRadius.all(NRadius.md),
                      child: Image.network(images[_image], fit: BoxFit.contain),
                    ),
            ),
          ),
        ),
        if (images.length > 1) ...[
          const SizedBox(height: NSpace.sm),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, _) => const SizedBox(width: NSpace.sm),
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => setState(() => _image = i),
                child: Container(
                  width: 72,
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.all(NRadius.sm),
                    border: Border.all(
                        color: i == _image ? NColors.sage : NColors.line,
                        width: i == _image ? 2 : 1),
                    image: DecorationImage(image: NetworkImage(images[i]), fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );

    return ContentWidth(
      vertical: NSpace.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Breadcrumb(title: p.title),
          const SizedBox(height: NSpace.lg),
          if (mobile) ...[
            gallery,
            const SizedBox(height: NSpace.xl),
            _Details(product: p),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: _Details(product: p)),
                const SizedBox(width: NSpace.xxl),
                Expanded(flex: 5, child: gallery),
              ],
            ),
        ],
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        InkWell(
          onTap: () => context.go(Routes.home),
          child: Text('الرئيسية', style: t.labelMedium?.copyWith(color: NColors.sageDark)),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          // Always point left (towards the current page in RTL reading order).
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Icon(Icons.chevron_left_rounded, size: 18, color: NColors.inkMuted),
          ),
        ),
        Text(title, style: t.labelMedium?.copyWith(color: NColors.inkMuted)),
      ],
    );
  }
}

class _Details extends ConsumerWidget {
  const _Details({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final settings = ref.watch(publicSettingsProvider).value;
    final p = product;
    final specs = <(String, String)>[
      ('عدد الصفحات', '${p.pageCount} صفحة'),
      ('عدد الصور', 'حتى ${p.photoCapacity} صورة'),
      if (p.trimSizeLabel != null) ('المقاس', p.trimSizeLabel!),
      if (p.paperLabel != null) ('الورق', p.paperLabel!),
      ('التجليد', 'تجليد يدوي'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (p.badge != null)
          Text(p.badge!, style: t.labelMedium?.copyWith(color: const Color(0xFF9A6A48))),
        Text(p.title, style: t.displaySmall),
        if (p.tagline != null) ...[
          const SizedBox(height: NSpace.xs),
          Text(p.tagline!, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w400)),
        ],
        const SizedBox(height: NSpace.md),
        Text(priceOrSoon(p.basePrice), style: t.headlineMedium?.copyWith(color: NColors.sageDark)),
        if (settings != null && settings.depositPercent > 0 && p.basePrice > 0)
          Text('عربون ${settings.depositPercent.toStringAsFixed(0)}٪ عند الطلب، والباقي عند الاستلام',
              style: t.bodySmall),
        if (p.description != null) ...[
          const SizedBox(height: NSpace.md),
          Text(p.description!, style: t.bodyLarge),
        ],
        const SizedBox(height: NSpace.lg),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('محرر الكتاب يصل في التحديث القادم'))),
          icon: const Icon(Icons.auto_stories_outlined),
          label: const Text('ابدئي تصميم كتابك'),
        ),
        const SizedBox(height: NSpace.md),
        const PrivacyBadge(dense: true),
        const SizedBox(height: NSpace.xl),
        Text('المواصفات', style: t.titleLarge),
        const SizedBox(height: NSpace.sm),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < specs.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: NColors.line),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: NSpace.md, vertical: 12),
                  child: Row(
                    children: [
                      Text(specs[i].$1, style: t.bodyMedium?.copyWith(color: NColors.inkMuted)),
                      const Spacer(),
                      Text(specs[i].$2, style: t.titleSmall),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: NSpace.xl),
        Text('إضافات اختيارية', style: t.titleLarge),
        Text('من لا تختار أي إضافة تدفع سعر الكتاب فقط', style: t.bodySmall),
        const SizedBox(height: NSpace.sm),
        for (final a in Addon.values)
          Padding(
            padding: const EdgeInsets.only(bottom: NSpace.sm),
            child: Container(
              padding: const EdgeInsets.all(NSpace.md),
              decoration: BoxDecoration(
                color: NColors.surface,
                borderRadius: const BorderRadius.all(NRadius.md),
                border: Border.all(color: NColors.line),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.label, style: t.titleSmall),
                        Text(a.hint, style: t.bodySmall),
                      ],
                    ),
                  ),
                  const SizedBox(width: NSpace.sm),
                  Text(
                    settings == null
                        ? '…'
                        : (settings.priceOf(a) > 0 ? '+ ${formatIqd(settings.priceOf(a))}' : 'قريباً'),
                    style: t.labelLarge?.copyWith(color: NColors.sageDark),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
