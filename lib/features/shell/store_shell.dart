import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/privacy_badge.dart';
import '../cart/cart_controller.dart';
import '../cart/shop_cart.dart';

/// Header + scrollable page + footer for all storefront routes.
class StoreShell extends StatelessWidget {
  const StoreShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar(
            pinned: true,
            toolbarHeight: 68,
            titleSpacing: 0,
            backgroundColor: NColors.paper,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: _Header(),
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, color: NColors.line),
            ),
          ),
          SliverToBoxAdapter(child: child),
          const SliverToBoxAdapter(child: _Footer()),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inCart = ref.watch(cartProvider).length + ref.watch(shopCartProvider).length;
    final mobile = isMobile(context);
    return ContentWidth(
      child: Row(
        children: [
          InkWell(
            onTap: () => context.go(Routes.home),
            borderRadius: const BorderRadius.all(NRadius.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/brand/logo.png', width: 44, height: 44, filterQuality: FilterQuality.medium),
                const SizedBox(width: NSpace.sm),
                Text('كتاب نسيم',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 22)),
              ],
            ),
          ),
          const Spacer(),
          if (!mobile) ...[
            TextButton(onPressed: () => context.go(Routes.home), child: const Text('الرئيسية')),
            TextButton(
              onPressed: () => context.go('${Routes.home}?s=products'),
              child: const Text('منتجاتنا'),
            ),
            const SizedBox(width: NSpace.sm),
          ],
          IconButton(
            tooltip: 'السلة',
            onPressed: () => context.go(Routes.cart),
            icon: Badge(
              isLabelVisible: inCart > 0,
              label: Text('$inCart'),
              backgroundColor: NColors.sand,
              textColor: NColors.ink,
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(width: NSpace.xs),
          OutlinedButton.icon(
            onPressed: () => context.go(Routes.track),
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: const Text('تتبّع طلبك'),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: mobile ? 12 : 18, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(top: NSpace.xxxl),
      color: NColors.surfaceAlt,
      child: ContentWidth(
        vertical: NSpace.xl,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: NSpace.lg,
          runSpacing: NSpace.md,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('كتاب نسيم', style: t.titleLarge?.copyWith(fontFamily: NFonts.display)),
                Text('كتب ذكريات تُطبع وتُجلَّد يدوياً في العراق', style: t.bodySmall),
              ],
            ),
            const PrivacyBadge(dense: true),
            Text('© ${DateTime.now().year} كتاب نسيم', style: t.bodySmall),
          ],
        ),
      ),
    );
  }
}
