import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/promo_banner.dart';
import '../../shared/widgets/book_mock.dart';
import '../../shared/widgets/layout.dart';

/// Auto-playing promo carousel with dots, swipe and hover-pause.
class HeroSlider extends StatefulWidget {
  const HeroSlider({super.key, required this.banners});
  final List<PromoBanner> banners;

  @override
  State<HeroSlider> createState() => _HeroSliderState();
}

class _HeroSliderState extends State<HeroSlider> {
  final _controller = PageController();
  Timer? _timer;
  int _index = 0;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_paused || widget.banners.length < 2 || !_controller.hasClients) return;
      final next = (_index + 1) % widget.banners.length;
      _controller.animateToPage(next,
          duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _go(int i) => _controller.animateToPage(i,
      duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);

  @override
  Widget build(BuildContext context) {
    final mobile = isMobile(context);
    final height = mobile ? 460.0 : 420.0;
    return MouseRegion(
      onEnter: (_) => _paused = true,
      onExit: (_) => _paused = false,
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: ClipRRect(
              borderRadius: const BorderRadius.all(NRadius.lg),
              child: PageView.builder(
                controller: _controller,
                itemCount: widget.banners.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _Slide(banner: widget.banners[i], mobile: mobile),
              ),
            ),
          ),
          if (widget.banners.length > 1) ...[
            const SizedBox(height: NSpace.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.banners.length; i++)
                  GestureDetector(
                    onTap: () => _go(i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 28 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? NColors.sage : NColors.line,
                          borderRadius: const BorderRadius.all(NRadius.pill),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.banner, required this.mobile});
  final PromoBanner banner;
  final bool mobile;

  (List<Color>, Color) get _palette => switch (banner.theme) {
        BannerTheme.sage => ([NColors.sageSoft, NColors.skySoft], NColors.sandSoft),
        BannerTheme.sand => ([NColors.sandSoft, const Color(0xFFFBEFE6)], NColors.sageSoft),
        BannerTheme.sky => ([NColors.skySoft, NColors.sageSoft], NColors.surface),
      };

  IconData get _icon => switch (banner.theme) {
        BannerTheme.sage => Icons.auto_stories_rounded,
        BannerTheme.sand => Icons.card_giftcard_rounded,
        BannerTheme.sky => Icons.verified_user_outlined,
      };

  void _onCta(BuildContext context) {
    if (banner.productSlug != null) {
      context.go(Routes.product(banner.productSlug!));
    } else {
      context.go('${Routes.home}?s=products');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (gradient, bookColor) = _palette;
    final imageUrl = banner.imageUrl;

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(banner.title, style: mobile ? t.displaySmall : t.displayMedium),
        if (banner.subtitle != null) ...[
          const SizedBox(height: NSpace.sm),
          Text(banner.subtitle!,
              style: (mobile ? t.titleMedium : t.titleLarge)
                  ?.copyWith(fontWeight: FontWeight.w400, color: NColors.ink)),
        ],
        if (banner.ctaLabel != null) ...[
          const SizedBox(height: NSpace.lg),
          FilledButton.icon(
            onPressed: () => _onCta(context),
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            iconAlignment: IconAlignment.end,
            label: Text(banner.ctaLabel!),
          ),
        ],
      ],
    );

    final visual = imageUrl != null
        ? ClipRRect(
            borderRadius: const BorderRadius.all(NRadius.md),
            child: Image.network(imageUrl, fit: BoxFit.cover),
          )
        : banner.productSlug != null
            ? BookMock(color: bookColor)
            : Container(
                decoration: BoxDecoration(
                  color: NColors.surface.withValues(alpha: .7),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(NSpace.xl),
                child: Icon(_icon, size: 72, color: NColors.sageDark),
              );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: gradient,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(mobile ? NSpace.lg : NSpace.xxl),
        child: mobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Center(child: SizedBox(height: 200, child: visual))),
                  const SizedBox(height: NSpace.md),
                  text,
                ],
              )
            : Row(
                children: [
                  Expanded(flex: 6, child: text),
                  const SizedBox(width: NSpace.xl),
                  Expanded(
                    flex: 4,
                    child: Center(child: SizedBox(height: 300, child: visual)),
                  ),
                ],
              ),
      ),
    );
  }
}
