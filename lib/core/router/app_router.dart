import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/editor/editor_page.dart';
import '../../features/home/home_page.dart';
import '../../features/product/product_page.dart';
import '../../features/shell/store_shell.dart';
import '../../features/style_guide/style_guide_page.dart';

abstract final class Routes {
  static const home = '/';
  static const styleGuide = '/style';
  static String product(String slug) => '/p/$slug';
  static String editor(String slug) => '/design/$slug';
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
        ],
      ),
      GoRoute(
        path: '/design/:slug',
        builder: (_, s) => EditorPage(slug: s.pathParameters['slug']!),
      ),
      GoRoute(path: Routes.styleGuide, builder: (_, _) => const StyleGuidePage()),
    ],
  );
});
