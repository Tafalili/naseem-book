import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/cart/cart_page.dart';
import '../../features/checkout/checkout_page.dart';
import '../../features/editor/editor_page.dart';
import '../../features/home/home_page.dart';
import '../../features/orders/order_page.dart';
import '../../features/preview/preview_page.dart';
import '../../features/product/product_page.dart';
import '../../features/shell/store_shell.dart';
import '../../features/style_guide/style_guide_page.dart';

abstract final class Routes {
  static const home = '/';
  static const styleGuide = '/style';
  static String product(String slug) => '/p/$slug';
  static String editor(String slug) => '/design/$slug';
  static String preview(String slug) => '/design/$slug/preview';
  static const cart = '/cart';
  static const checkout = '/checkout';
  static const track = '/track';
  static String order(String code) => '/order/$code';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      ShellRoute(
        builder: (_, _, child) => StoreShell(child: child),
        routes: [
          GoRoute(
            path: Routes.home,
            pageBuilder: (_, s) => NoTransitionPage(
              child: HomePage(scrollTo: s.uri.queryParameters['s']),
            ),
          ),
          GoRoute(
            path: '/p/:slug',
            pageBuilder: (_, s) => NoTransitionPage(
              child: ProductPage(slug: s.pathParameters['slug']!),
            ),
          ),
          GoRoute(
            path: Routes.cart,
            pageBuilder: (_, _) => const NoTransitionPage(child: CartPage()),
          ),
          GoRoute(
            path: Routes.checkout,
            pageBuilder: (_, _) => const NoTransitionPage(child: CheckoutPage()),
          ),
          GoRoute(
            path: Routes.track,
            pageBuilder: (_, _) => const NoTransitionPage(child: TrackPage()),
          ),
          GoRoute(
            path: '/order/:code',
            pageBuilder: (_, s) => NoTransitionPage(
              child: OrderPage(code: s.pathParameters['code']!.toUpperCase()),
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/design/:slug',
        builder: (_, s) => EditorPage(slug: s.pathParameters['slug']!),
        routes: [
          GoRoute(
            path: 'preview',
            builder: (_, s) => PreviewPage(slug: s.pathParameters['slug']!),
          ),
        ],
      ),
      GoRoute(path: Routes.styleGuide, builder: (_, _) => const StyleGuidePage()),
    ],
  );
});
