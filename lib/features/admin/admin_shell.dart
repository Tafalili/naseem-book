import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import '../../data/models/order.dart';
import '../orders/web_push.dart';
import 'admin_login_page.dart';
import 'data/admin_repository.dart';

abstract final class AdminRoutes {
  static const orders = '/admin';
  static String order(String id) => '/admin/orders/$id';
  static const templates = '/admin/templates';
  static const products = '/admin/products';
  static const settings = '/admin/settings';
}

/// Auth gate + navigation for every /admin page.
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(adminMeProvider);
    return me.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const AdminLoginPage(),
      data: (m) => m == null ? const AdminLoginPage() : _Frame(me: m, location: location, child: child),
    );
  }
}

class _Frame extends ConsumerWidget {
  const _Frame({required this.me, required this.location, required this.child});
  final AdminMe me;
  final String location;
  final Widget child;

  static const _items = [
    (AdminRoutes.orders, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'الطلبات'),
    (AdminRoutes.products, Icons.storefront_outlined, Icons.storefront_rounded, 'المنتجات'),
    (AdminRoutes.templates, Icons.dashboard_customize_outlined, Icons.dashboard_customize_rounded, 'القوالب'),
    (AdminRoutes.settings, Icons.tune_outlined, Icons.tune_rounded, 'الإعدادات'),
  ];

  int get _index {
    if (location.startsWith(AdminRoutes.products)) return 1;
    if (location.startsWith(AdminRoutes.templates)) return 2;
    if (location.startsWith(AdminRoutes.settings)) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final t = Theme.of(context).textTheme;

    final bar = AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: NColors.surface,
      surfaceTintColor: Colors.transparent,
      titleSpacing: NSpace.md,
      title: Row(children: [
        const Icon(Icons.menu_book_rounded, color: NColors.sageDark),
        const SizedBox(width: NSpace.sm),
        Text('لوحة كتاب نسيم', style: t.titleLarge),
      ]),
      actions: [
        const _PushButton(),
        PopupMenuButton<String>(
          tooltip: 'الحساب',
          icon: const Icon(Icons.account_circle_outlined),
          itemBuilder: (_) => [
            PopupMenuItem(
              enabled: false,
              child: Text('${me.name ?? me.email}\n${me.isOwner ? 'المالك' : 'موظف'}', style: t.bodySmall),
            ),
            const PopupMenuItem(value: 'store', child: Text('فتح المتجر')),
            const PopupMenuItem(value: 'out', child: Text('تسجيل الخروج')),
          ],
          onSelected: (v) async {
            if (v == 'store') context.go('/');
            if (v == 'out') await ref.read(adminRepositoryProvider).signOut();
          },
        ),
        const SizedBox(width: NSpace.sm),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: NColors.line),
      ),
    );

    if (wide) {
      return Scaffold(
        appBar: bar,
        body: Row(children: [
          NavigationRail(
            selectedIndex: _index,
            labelType: NavigationRailLabelType.all,
            backgroundColor: NColors.surface,
            onDestinationSelected: (i) => context.go(_items[i].$1),
            destinations: [
              for (final it in _items)
                NavigationRailDestination(icon: Icon(it.$2), selectedIcon: Icon(it.$3), label: Text(it.$4)),
            ],
          ),
          const VerticalDivider(width: 1, color: NColors.line),
          Expanded(child: child),
        ]),
      );
    }
    return Scaffold(
      appBar: bar,
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => context.go(_items[i].$1),
        destinations: [
          for (final it in _items)
            NavigationDestination(icon: Icon(it.$2), selectedIcon: Icon(it.$3), label: it.$4),
        ],
      ),
    );
  }
}

final _hasPushProvider = FutureProvider((ref) => ref.watch(adminRepositoryProvider).hasPush());

/// Turns on browser notifications for new orders and receipts on this device.
class _PushButton extends ConsumerStatefulWidget {
  const _PushButton();
  @override
  ConsumerState<_PushButton> createState() => _PushButtonState();
}

class _PushButtonState extends ConsumerState<_PushButton> {
  bool _busy = false;

  Future<void> _enable() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!WebPush.supported) {
      messenger.showSnackBar(const SnackBar(
          content: Text('هذا المتصفح لا يدعم الإشعارات. على آيفون: أضف اللوحة إلى الشاشة الرئيسية أولاً.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final sub = await WebPush.subscribe();
      if (sub == null) {
        messenger.showSnackBar(const SnackBar(content: Text('لم يُسمح بالإشعارات من إعدادات المتصفح.')));
        return;
      }
      await ref.read(adminRepositoryProvider).savePush(sub.endpoint, sub.p256dh, sub.auth);
      ref.invalidate(_hasPushProvider);
      messenger.showSnackBar(const SnackBar(content: Text('ستصلك إشعارات الطلبات الجديدة والوصولات على هذا الجهاز.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذّر تفعيل الإشعارات. حاول مجدداً.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(_hasPushProvider).value ?? false;
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.all(NSpace.md),
        child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return IconButton(
      tooltip: on ? 'الإشعارات مفعّلة على هذا الجهاز' : 'تفعيل إشعارات الطلبات',
      onPressed: _enable,
      icon: Icon(on ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
          color: on ? NColors.sageDark : null),
    );
  }
}

/// Small card container used across admin pages.
class AdminCard extends StatelessWidget {
  const AdminCard({super.key, required this.child, this.title, this.trailing, this.padding = NSpace.md});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: NColors.surface,
        borderRadius: const BorderRadius.all(NRadius.md),
        border: Border.all(color: NColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(children: [
              Expanded(child: Text(title!, style: t.titleMedium)),
              ?trailing,
            ]),
            const SizedBox(height: NSpace.sm),
          ],
          child,
        ],
      ),
    );
  }
}

/// Status names as the team says them (the customer sees OrderStatus.label).
String adminStatus(OrderStatus s) => switch (s) {
      OrderStatus.pendingDeposit => 'بانتظار العربون',
      OrderStatus.depositReview => 'وصل للمراجعة',
      OrderStatus.confirmed => 'مؤكد',
      OrderStatus.designing => 'قيد التصميم',
      OrderStatus.printing => 'قيد الطباعة',
      OrderStatus.shipped => 'تم الشحن',
      OrderStatus.delivered => 'تم التسليم',
      OrderStatus.cancelled => 'ملغي',
    };

Color statusColor(String key) => switch (key) {
      'pending_deposit' => NColors.inkMuted,
      'deposit_review' => NColors.warning,
      'confirmed' => NColors.sage,
      'designing' => NColors.sky,
      'printing' => NColors.gold,
      'shipped' => NColors.sageDark,
      'delivered' => NColors.success,
      'cancelled' => NColors.danger,
      _ => NColors.inkMuted,
    };

String shortDate(DateTime d) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${d.year}/${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
