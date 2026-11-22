import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/order.dart';
import 'admin_shell.dart';
import 'data/admin_repository.dart';

typedef _Filter = ({OrderStatus? status, String query});

final _filterProvider = NotifierProvider<_FilterNotifier, _Filter>(_FilterNotifier.new);

class _FilterNotifier extends Notifier<_Filter> {
  @override
  _Filter build() => (status: null, query: '');
  void status(OrderStatus? s) => state = (status: s, query: state.query);
  void query(String q) => state = (status: state.status, query: q);
}

final adminOrdersProvider = FutureProvider<List<AdminOrderRow>>((ref) {
  final f = ref.watch(_filterProvider);
  return ref.watch(adminRepositoryProvider).orders(status: f.status, query: f.query);
});

final adminCountsProvider = FutureProvider((ref) => ref.watch(adminRepositoryProvider).counts());

class AdminOrdersPage extends ConsumerStatefulWidget {
  const AdminOrdersPage({super.key});
  @override
  ConsumerState<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends ConsumerState<AdminOrdersPage> {
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search.text = ref.read(_filterProvider).query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(adminOrdersProvider);
    ref.invalidate(adminCountsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final f = ref.watch(_filterProvider);
    final counts = ref.watch(adminCountsProvider).value ?? const {};
    final orders = ref.watch(adminOrdersProvider);
    final total = counts.values.fold(0, (a, b) => a + b);

    Widget chip(OrderStatus? s) {
      final n = s == null ? total : (counts[s] ?? 0);
      final label = s == null ? 'الكل' : '${s.emoji} ${adminStatus(s)}';
      return ChoiceChip(
        label: Text('$label ($n)'),
        selected: f.status == s,
        onSelected: (_) => ref.read(_filterProvider.notifier).status(s),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(NSpace.md),
        children: [
          Row(children: [
            Expanded(child: Text('الطلبات', style: t.headlineSmall)),
            IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh_rounded)),
          ]),
          const SizedBox(height: NSpace.sm),
          TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'بحث برمز الطلب أو الاسم أو رقم الهاتف',
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), () => ref.read(_filterProvider.notifier).query(v));
            },
          ),
          const SizedBox(height: NSpace.md),
          Wrap(spacing: NSpace.sm, runSpacing: NSpace.sm, children: [
            chip(null),
            for (final s in OrderStatus.values) chip(s),
          ]),
          const SizedBox(height: NSpace.md),
          orders.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(NSpace.xl), child: Center(child: CircularProgressIndicator())),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(NSpace.xl),
              child: Column(children: [
                const Text('تعذّر تحميل الطلبات.'),
                TextButton(onPressed: _refresh, child: const Text('إعادة المحاولة')),
              ]),
            ),
            data: (rows) => rows.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(NSpace.xl),
                    child: Text('لا توجد طلبات هنا.', textAlign: TextAlign.center, style: t.bodyLarge),
                  )
                : Column(children: [for (final r in rows) _OrderTile(row: r)]),
          ),
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.row});
  final AdminOrderRow row;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = statusColor(row.status.key);
    return Padding(
      padding: const EdgeInsets.only(bottom: NSpace.sm),
      child: Material(
        color: NColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(NRadius.md),
          side: BorderSide(color: NColors.line),
        ),
        child: InkWell(
          borderRadius: const BorderRadius.all(NRadius.md),
          onTap: () => context.go(AdminRoutes.order(row.id)),
          child: Padding(
            padding: const EdgeInsets.all(NSpace.md),
            child: Row(children: [
              Container(width: 4, height: 48, decoration: BoxDecoration(color: c, borderRadius: const BorderRadius.all(NRadius.pill))),
              const SizedBox(width: NSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(row.code, style: t.titleMedium?.copyWith(letterSpacing: 1)),
                    const SizedBox(width: NSpace.sm),
                    Flexible(
                      child: Text('${row.status.emoji} ${adminStatus(row.status)}',
                          overflow: TextOverflow.ellipsis, style: t.labelMedium?.copyWith(color: c)),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    '${row.customerName} · ${row.city}${(row.childName ?? '').isNotEmpty ? ' · 👶 ${row.childName}' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: t.bodyMedium,
                  ),
                  Text(shortDate(row.createdAt), style: t.bodySmall),
                ]),
              ),
              const SizedBox(width: NSpace.sm),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatIqd(row.total), style: t.titleSmall),
                Text('عربون ${formatIqd(row.depositAmount)}', style: t.bodySmall),
                if (row.hasReceipt && row.status == OrderStatus.depositReview)
                  Text('وصل مرفوع', style: t.labelSmall?.copyWith(color: NColors.warning)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
