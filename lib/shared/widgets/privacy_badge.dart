import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';

class PrivacyBadge extends StatelessWidget {
  const PrivacyBadge({super.key, this.dense = false});
  final bool dense;

  static const text = 'صورك مشفرة ومحفوظة بشكل خاص، وتُحذف تلقائياً بعد طباعة كتابك';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: dense ? NSpace.sm + 4 : NSpace.md, vertical: dense ? 6 : NSpace.sm),
      decoration: BoxDecoration(
        color: NColors.surface.withValues(alpha: .9),
        borderRadius: const BorderRadius.all(NRadius.pill),
        border: Border.all(color: NColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: dense ? 15 : 18, color: NColors.sageDark),
          const SizedBox(width: NSpace.sm),
          Flexible(
            child: Text(text,
                style: (dense ? t.labelSmall : t.labelMedium)
                    ?.copyWith(color: NColors.sageDark)),
          ),
        ],
      ),
    );
  }
}
