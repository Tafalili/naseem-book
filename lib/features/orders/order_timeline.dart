import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/order.dart';

String _date(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} · ${two(d.hour)}:${two(d.minute)}';
}

/// Visual timeline: every step of the flow, done / current / upcoming,
/// plus the "photos deleted" privacy event.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({super.key, required this.order});
  final OrderView order;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final reached = <OrderStatus, StatusEvent>{};
    for (final e in order.history) {
      reached[e.status] = e;
    }
    final cancelled = order.status == OrderStatus.cancelled;
    final currentIdx = OrderStatus.flow.indexOf(order.status);

    final steps = <({String emoji, String label, String? sub, int state})>[];
    for (var i = 0; i < OrderStatus.flow.length; i++) {
      final s = OrderStatus.flow[i];
      final e = reached[s];
      final state = cancelled
          ? (e != null ? 2 : 0)
          : i < currentIdx
              ? 2
              : i == currentIdx
                  ? 1
                  : 0;
      if (cancelled && e == null) continue;
      steps.add((emoji: s.emoji, label: s.label, sub: e == null ? null : _date(e.at), state: state));
    }
    if (cancelled) {
      final e = reached[OrderStatus.cancelled];
      steps.add((emoji: '❌', label: 'ملغي', sub: e?.note ?? (e == null ? null : _date(e.at)), state: 1));
    }
    if (order.imagesPurgedAt != null) {
      steps.add((
        emoji: '🔒',
        label: 'حُذفت صور طفلك من السيرفر بأمان',
        sub: _date(order.imagesPurgedAt!),
        state: 2,
      ));
    }

    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 40,
              child: Column(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: switch (steps[i].state) {
                      2 => NColors.sageSoft,
                      1 => NColors.sandSoft,
                      _ => NColors.surfaceAlt,
                    },
                    border: steps[i].state == 1 ? Border.all(color: NColors.sand, width: 2) : null,
                  ),
                  child: Opacity(
                    opacity: steps[i].state == 0 ? .35 : 1,
                    child: Text(steps[i].emoji, style: const TextStyle(fontSize: 16)),
                  ),
                ),
                if (i < steps.length - 1)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: steps[i].state == 2 ? NColors.sage : NColors.line,
                    ),
                  ),
              ]),
            ),
            const SizedBox(width: NSpace.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 6, bottom: NSpace.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    steps[i].label,
                    style: (steps[i].state == 1 ? t.titleSmall : t.bodyLarge)?.copyWith(
                      color: steps[i].state == 0 ? NColors.inkMuted : NColors.ink,
                    ),
                  ),
                  if (steps[i].sub != null) Text(steps[i].sub!, style: t.bodySmall),
                ]),
              ),
            ),
          ]),
        ),
    ]);
  }
}
