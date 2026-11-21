import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/style_guide/style_guide_page.dart';

abstract final class Routes {
  static const home = '/';
  static const styleGuide = '/style';
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: Routes.styleGuide,
    routes: [
      // Phase 1 replaces home with the storefront.
      GoRoute(path: Routes.home, redirect: (_, _) => Routes.styleGuide),
      GoRoute(
        path: Routes.styleGuide,
        builder: (_, _) => const StyleGuidePage(),
      ),
    ],
  );
});
