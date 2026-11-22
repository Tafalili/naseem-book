import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/admin/admin_entry.dart' deferred as admin;
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
  static String product(String slug, {String? line}) => line == null ? '/p/$slug' : '/p/$slug?line=$line';
  /// [book] is a book id: the product slug, or `slug~suffix` for another child.
  static String editor(String book) => '/design/$book';
  static String preview(String book) => '/design/$book/preview';
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
              child: ProductPage(slug: s.pathParameters['slug']!, lineId: s.uri.queryParameters['line']),
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
        path: '/design/:book',
        builder: (_, s) => EditorPage(book: s.pathParameters['book']!),
        routes: [
          GoRoute(
            path: 'preview',
            builder: (_, s) => PreviewPage(book: s.pathParameters['book']!),
          ),
        ],
      ),
      GoRoute(path: Routes.styleGuide, builder: (_, _) => const StyleGuidePage()),
      GoRoute(
        path: '/admin',
        pageBuilder: (_, s) => NoTransitionPage(child: _AdminLoader(location: s.uri.path)),
        routes: [
          GoRoute(
            path: 'orders/:id',
            pageBuilder: (_, s) =>
                NoTransitionPage(child: _AdminLoader(location: s.uri.path, orderId: s.pathParameters['id'])),
          ),
          GoRoute(
            path: 'products',
            pageBuilder: (_, s) => NoTransitionPage(child: _AdminLoader(location: s.uri.path)),
          ),
          GoRoute(
            path: 'templates',
            pageBuilder: (_, s) => NoTransitionPage(child: _AdminLoader(location: s.uri.path)),
          ),
          GoRoute(
            path: 'settings',
            pageBuilder: (_, s) => NoTransitionPage(child: _AdminLoader(location: s.uri.path)),
          ),
        ],
      ),
    ],
  );
});

final _adminLib = admin.loadLibrary();

class _AdminLoader extends StatelessWidget {
  const _AdminLoader({required this.location, this.orderId});
  final String location;
  final String? orderId;

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _adminLib,
        builder: (context, snap) {
          if (snap.hasError) {
            return const Scaffold(body: Center(child: Text('تعذّر تحميل لوحة الإدارة. حدّث الصفحة.')));
          }
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return admin.adminPage(location, orderId: orderId);
        },
      );
}
