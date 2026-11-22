import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/product.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/widgets/book_mock.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/privacy_badge.dart';
import 'hero_slider.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.scrollTo});
  final String? scrollTo;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final _productsKey = GlobalKey();

  @override
  void didUpdateWidget(HomePage old) {
    super.didUpdateWidget(old);
    _maybeScroll();
  }

  @override
  void initState() {
    super.initState();
    _maybeScroll();
  }

  void _maybeScroll() {
    if (widget.scrollTo != 'products') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _productsKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(bannersProvider);
    final products = ref.watch(productsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ContentWidth(
          vertical: NSpace.lg,
          child: banners.when(
            loading: () => const _SliderSkeleton(),
            error: (_, _) => const SizedBox.shrink(),
            data: (b) => b.isEmpty
                ? const SizedBox.shrink()
                : HeroSlider(
                    banners: b,
                    productCovers: {
                      for (final p in products.value ?? const <Product>[])
                        if (p.coverImage != null) p.slug: p.coverImage!,
                    },
                  ),
          ),
        ),
        products.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(NSpace.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => LoadError(onRetry: () => ref.invalidate(productsProvider)),
          data: (list) {
            final books = list.where((p) => !p.isItem).toList();
            final items = list.where((p) => p.isItem).toList();
            final featured = books.where((p) => p.isFeatured).firstOrNull ?? books.firstOrNull;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (featured != null) _FeaturedProduct(product: featured),
                if (featured != null && featured.galleryImages.length > 1)
                  _InsideBook(product: featured),
                const _HowItWorks(),
                ContentWidth(
                  key: _productsKey,
                  vertical: NSpace.xxl,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionHeader(
                          title: 'كتبنا', subtitle: 'كل كتاب يُطبع ويُجلَّد يدوياً بعناية'),
                      const SizedBox(height: NSpace.lg),
                      _ProductGrid(products: books),
                      if (items.isNotEmpty) ...[
                        const SizedBox(height: NSpace.xxl),
                        const SectionHeader(
                            title: 'هدايا وتوزيعات', subtitle: 'تُطلب مع الكتاب في نفس السلة، أو وحدها'),
                        const SizedBox(height: NSpace.lg),
                        _ProductGrid(products: items),
                      ],
                    ],
                  ),
                ),
                const _PrivacySection(),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SliderSkeleton extends StatelessWidget {
  const _SliderSkeleton();
  @override
  Widget build(BuildContext context) => Container(
        height: isMobile(context) ? 460 : 420,
        decoration: const BoxDecoration(
          color: NColors.surfaceAlt,
          borderRadius: BorderRadius.all(NRadius.lg),
        ),
      );
}

class _FeaturedProduct extends StatelessWidget {
  const _FeaturedProduct({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mobile = isMobile(context);
    final points = <(IconData, String)>[
      (Icons.photo_library_outlined, '${product.photoCapacity} صورة لأجمل لحظات سنته الأولى'),
      (Icons.menu_book_outlined, '${product.pageCount} صفحة مصممة بألوان تناسب الأولاد والبنات'),
      if (product.paperLabel != null) (Icons.layers_outlined, product.paperLabel!),
      (Icons.edit_note_rounded, 'أسطر فارغة تكتبين فيها بخط يدك، أو نص مطبوع إن رغبتِ'),
    ];

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (product.badge != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: const BoxDecoration(
              color: NColors.sandSoft,
              borderRadius: BorderRadius.all(NRadius.pill),
            ),
            child: Text(product.badge!,
                style: t.labelMedium?.copyWith(color: const Color(0xFF9A6A48))),
          ),
        const SizedBox(height: NSpace.md),
        Text(product.title, style: mobile ? t.displaySmall : t.displayMedium),
        if (product.tagline != null) ...[
          const SizedBox(height: NSpace.sm),
          Text(product.tagline!, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400)),
        ],
        const SizedBox(height: NSpace.lg),
        for (final (icon, label) in points)
          Padding(
            padding: const EdgeInsets.only(bottom: NSpace.sm + 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                      color: NColors.sageSoft, shape: BoxShape.circle),
                  child: Icon(icon, size: 18, color: NColors.sageDark),
                ),
                const SizedBox(width: NSpace.sm + 4),
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(label, style: t.bodyLarge),
                )),
              ],
            ),
          ),
        const SizedBox(height: NSpace.md),
        Wrap(
          spacing: NSpace.md,
          runSpacing: NSpace.md,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton(
              onPressed: () => context.go(Routes.product(product.slug)),
              child: const Text('صمّمي كتاب طفلك'),
            ),
            Text(priceOrSoon(product.basePrice),
                style: t.headlineSmall?.copyWith(color: NColors.sageDark)),
          ],
        ),
      ],
    );

    final visual = SizedBox(
      height: mobile ? 300 : 440,
      child: Center(child: BookMock(image: product.coverImage)),
    );

    return Container(
      margin: const EdgeInsets.only(top: NSpace.xl),
      color: NColors.surface,
      child: ContentWidth(
        vertical: mobile ? NSpace.xl : NSpace.xxxl,
        child: mobile
            ? Column(children: [visual, const SizedBox(height: NSpace.xl), info])
            : Row(
                children: [
                  Expanded(flex: 5, child: info),
                  const SizedBox(width: NSpace.xxl),
                  Expanded(flex: 4, child: visual),
                ],
              ),
      ),
    );
  }
}

class _InsideBook extends StatelessWidget {
  const _InsideBook({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    // Wide images are spreads; skip the (portrait) back cover here.
    final spreads = product.gallery
        .where((p) => p.contains('spread'))
        .map((p) => product.galleryImages[product.gallery.indexOf(p)])
        .toList();
    if (spreads.isEmpty) return const SizedBox.shrink();
    final h = mobile ? 200.0 : 300.0;
    return Container(
      color: NColors.surface,
      padding: const EdgeInsets.only(bottom: NSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ContentWidth(
            child: SectionHeader(
                title: 'من داخل الكتاب', subtitle: 'صفحات مصممة لكل شهر من سنته الأولى'),
          ),
          const SizedBox(height: NSpace.lg),
          SizedBox(
            height: h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: mobile ? NSpace.md : NSpace.xl),
              itemCount: spreads.length,
              separatorBuilder: (_, _) => const SizedBox(width: NSpace.lg),
              itemBuilder: (_, i) => Container(
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.all(NRadius.sm),
                  boxShadow: NShadow.soft,
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 2 * 186 / 276,
                  child: Image(image: spreads[i], fit: BoxFit.cover),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  static const _steps = <(IconData, String, String)>[
    (Icons.add_photo_alternate_outlined, 'ارفعي الصور', 'اختاري صور طفلك من هاتفك مباشرة'),
    (Icons.crop_rounded, 'رتّبيها في الصفحات', 'حرّكي وكبّري كل صورة داخل إطارها'),
    (Icons.auto_stories_outlined, 'راجعي الكتاب', 'قلّبي الصفحات وشاهدي كتابك قبل الطلب'),
    (Icons.local_shipping_outlined, 'نطبعه ونوصله', 'طباعة وتجليد يدوي، وتوصيل لباب البيت'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mobile = isMobile(context);
    return ContentWidth(
      vertical: NSpace.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: 'كيف تصنعين كتابك؟', subtitle: 'أربع خطوات بسيطة من هاتفك'),
          const SizedBox(height: NSpace.lg),
          LayoutBuilder(builder: (context, c) {
            final cols = mobile ? 2 : 4;
            final w = (c.maxWidth - NSpace.md * (cols - 1)) / cols;
            return Wrap(
              spacing: NSpace.md,
              runSpacing: NSpace.md,
              children: [
                for (var i = 0; i < _steps.length; i++)
                  SizedBox(
                    width: w,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(NSpace.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(_steps[i].$1, color: NColors.sage, size: 28),
                                const Spacer(),
                                Text('${i + 1}',
                                    style: t.headlineMedium?.copyWith(color: NColors.line)),
                              ],
                            ),
                            const SizedBox(height: NSpace.md),
                            Text(_steps[i].$2, style: t.titleMedium),
                            const SizedBox(height: NSpace.xs),
                            Text(_steps[i].$3, style: t.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth < 520 ? 1 : (c.maxWidth < 900 ? 2 : 3);
      final w = (c.maxWidth - NSpace.lg * (cols - 1)) / cols;
      return Wrap(
        spacing: NSpace.lg,
        runSpacing: NSpace.lg,
        children: [for (final p in products) SizedBox(width: w, child: ProductCard(product: p))],
      );
    });
  }
}

class ProductCard extends StatelessWidget {
  const ProductCard({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return HoverLift(
      onTap: () => context.go(Routes.product(product.slug)),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                if (product.isItem)
                  Container(
                    height: 280,
                    width: double.infinity,
                    color: NColors.sandSoft,
                    child: product.coverImage == null
                        ? null
                        : Image(image: product.coverImage!, fit: BoxFit.cover),
                  )
                else
                  Container(
                    height: 280,
                    color: NColors.sandSoft,
                    padding: const EdgeInsets.symmetric(vertical: NSpace.lg),
                    child: Center(child: BookMock(image: product.coverImage, tilt: false)),
                  ),
                if (product.badge != null)
                  PositionedDirectional(
                    top: NSpace.md,
                    start: NSpace.md,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: const BoxDecoration(
                        color: NColors.surface,
                        borderRadius: BorderRadius.all(NRadius.pill),
                      ),
                      child: Text(product.badge!, style: t.labelSmall?.copyWith(color: NColors.ink)),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(NSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.title, style: t.titleMedium),
                  Text(
                      product.isItem
                          ? (product.tagline ?? '')
                          : '${product.pageCount} صفحة · ${product.photoCapacity} صورة',
                      style: t.bodySmall),
                  const SizedBox(height: NSpace.sm),
                  Row(
                    children: [
                      Text(priceOrSoon(product.basePrice),
                          style: t.titleLarge?.copyWith(color: NColors.sageDark)),
                      if (product.isItem && product.options.minQty > 1)
                        Text('  للقطعة', style: t.bodySmall),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_rounded, color: NColors.sage),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final mobile = isMobile(context);
    final items = <(IconData, String, String)>[
      (Icons.lock_outline_rounded, 'محفوظة بشكل خاص', 'لا يرى صورك إلا فريق الطباعة'),
      (Icons.delete_sweep_outlined, 'تُحذف تلقائياً', 'بعد طباعة كتابك تُمسح الصور من السيرفر'),
      (Icons.timeline_rounded, 'نُعلمك بكل خطوة', 'تتبّعي طلبك من الاستلام حتى التسليم'),
    ];
    return ContentWidth(
      child: Container(
        padding: EdgeInsets.all(mobile ? NSpace.lg : NSpace.xxl),
        decoration: const BoxDecoration(
          color: NColors.skySoft,
          borderRadius: BorderRadius.all(NRadius.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('صور طفلك أمانة عندنا', style: t.headlineMedium),
            const SizedBox(height: NSpace.md),
            const PrivacyBadge(),
            const SizedBox(height: NSpace.lg),
            Wrap(
              spacing: NSpace.xl,
              runSpacing: NSpace.md,
              children: [
                for (final (icon, title, sub) in items)
                  SizedBox(
                    width: mobile ? double.infinity : 300,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: NColors.sageDark),
                        const SizedBox(width: NSpace.sm + 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: t.titleSmall),
                              Text(sub, style: t.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
