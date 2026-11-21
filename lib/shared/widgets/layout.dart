import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';

/// Centers content at max width with responsive side gutters.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.vertical = 0});
  final Widget child;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final gutter = w < NBreakpoints.tablet ? NSpace.md : NSpace.xl;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: NBreakpoints.maxContent),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter, vertical: vertical),
          child: child,
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: t.headlineMedium),
        if (subtitle != null) ...[
          const SizedBox(height: NSpace.xs),
          Text(subtitle!, style: t.bodyLarge?.copyWith(color: NColors.inkMuted)),
        ],
      ],
    );
  }
}

bool isMobile(BuildContext context) =>
    MediaQuery.sizeOf(context).width < NBreakpoints.tablet;

/// Small hover lift used by cards (web).
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(NRadius.lg),
            boxShadow: _hover ? NShadow.lifted : const [],
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Generic async error card with retry.
class LoadError extends StatelessWidget {
  const LoadError({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(NSpace.xl),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, color: NColors.inkMuted, size: 32),
          const SizedBox(height: NSpace.sm),
          Text('تعذّر التحميل، تحققي من الاتصال', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: NSpace.sm),
          OutlinedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
        ],
      ),
    );
  }
}
