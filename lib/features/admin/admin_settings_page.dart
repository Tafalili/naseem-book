import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/order.dart';
import '../../data/repositories/catalog_repository.dart';
import 'admin_shell.dart';
import 'data/admin_repository.dart';

final _settingsProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).settings());
final _productsProvider = FutureProvider.autoDispose(
    (ref) async => (await ref.watch(adminRepositoryProvider).products()).where((p) => p.kind == 'book').toList());
final _teamProvider = FutureProvider.autoDispose((ref) => ref.watch(adminRepositoryProvider).team());

const _priceKeys = [
  ('child_name', 'اسم الطفل على الغلاف'),
  ('photos', 'الصور داخل الكتاب (سعر كل الصور، ويُحسب بالنسبة)'),
  ('printed_text', 'النص المطبوع'),
  ('designer_cover', '«اتركه لذوقكم» (الغلاف من تصميمنا)'),
  ('gift_wrap', 'تغليف الهدية'),
  ('extra_copy', 'النسخة الإضافية (للنسخة الواحدة)'),
];

class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(adminMeProvider).value;
    final t = Theme.of(context).textTheme;
    if (me == null) return const SizedBox.shrink();
    if (!me.isOwner) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(NSpace.xl),
          child: Text('الإعدادات متاحة للمالك فقط.', style: t.bodyLarge),
        ),
      );
    }
    final settings = ref.watch(_settingsProvider);
    final products = ref.watch(_productsProvider);
    if (settings.hasError || products.hasError) {
      return Center(
        child: TextButton(
          onPressed: () {
            ref.invalidate(_settingsProvider);
            ref.invalidate(_productsProvider);
          },
          child: const Text('تعذّر التحميل. إعادة المحاولة'),
        ),
      );
    }
    if (!settings.hasValue || !products.hasValue) return const Center(child: CircularProgressIndicator());
    return _SettingsForm(settings: settings.value!, products: products.value!, me: me);
  }
}

class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings, required this.products, required this.me});
  final Settings settings;
  final List<AdminProduct> products;
  final AdminMe me;
  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final Map<String, TextEditingController> _prices;
  late final Map<String, TextEditingController> _base;
  late final Map<String, TextEditingController> _wallets;
  late final TextEditingController _depositPct, _depositRound, _email, _purgeHours, _purgeDays;
  bool _busy = false;

  TextEditingController _c(Object v) => TextEditingController(text: '$v');

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    _prices = {for (final k in _priceKeys) k.$1: _c(s.prices[k.$1] ?? 0)};
    _base = {for (final p in widget.products) p.id: _c(p.basePrice)};
    _wallets = {for (final k in Wallets.labels.keys) k: _c(s.wallets[k] ?? '')};
    _depositPct = _c(s.depositPercent.round());
    _depositRound = _c(s.depositRound);
    _email = _c(s.notifyEmail ?? '');
    _purgeHours = _c(s.purgeAfterPrintHours);
    _purgeDays = _c(s.purgeMaxDays);
  }

  int _int(TextEditingController c) => int.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final pct = _int(_depositPct);
    if (pct < 0 || pct > 100) {
      messenger.showSnackBar(const SnackBar(content: Text('نسبة العربون بين 0 و100.')));
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(adminRepositoryProvider);
      await repo.saveSettings({
        'prices': {
          ...widget.settings.prices,
          for (final e in _prices.entries) e.key: _int(e.value),
        },
        'deposit_percent': pct,
        'deposit_round': _int(_depositRound).clamp(1, 100000),
        'wallets': {for (final e in _wallets.entries) e.key: e.value.text.trim()},
        'notify_email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'purge_after_print_hours': _int(_purgeHours).clamp(1, 24 * 30),
        'purge_max_days': _int(_purgeDays).clamp(1, 90),
      });
      for (final p in widget.products) {
        final v = _int(_base[p.id]!);
        if (v != p.basePrice) await repo.setBasePrice(p.id, v);
      }
      ref.invalidate(publicSettingsProvider);
      ref.invalidate(productsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('تم حفظ الإعدادات.')));
    } on AdminFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذّر الحفظ. حاول مجدداً.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _money(String label, TextEditingController c) => Padding(
        padding: const EdgeInsets.only(bottom: NSpace.sm),
        child: TextField(
          controller: c,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: label, suffixText: 'د.ع'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pct = _int(_depositPct);
    final round = _int(_depositRound).clamp(1, 100000);
    int dep(int total) {
      final d = ((total * pct / 100) / round).ceil() * round;
      return d > total ? total : d;
    }

    final base = widget.products.isEmpty ? 0 : _int(_base[widget.products.first.id]!);

    return ListView(
      padding: const EdgeInsets.all(NSpace.md),
      children: [
        Row(children: [
          Expanded(child: Text('الإعدادات', style: t.headlineSmall)),
          FilledButton.icon(
            onPressed: _busy ? null : _save,
            icon: _busy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: const Text('حفظ'),
          ),
        ]),
        const SizedBox(height: NSpace.md),
        Wrap(spacing: NSpace.md, runSpacing: NSpace.md, children: [
          _box(AdminCard(
            title: 'الأسعار',
            child: Column(children: [
              for (final p in widget.products) _money('سعر ${p.title} (بدون إضافات)', _base[p.id]!),
              for (final k in _priceKeys) _money(k.$2, _prices[k.$1]!),
              Text('السعر 0 يظهر للزبون «قريباً».', style: t.bodySmall),
            ]),
          )),
          _box(AdminCard(
            title: 'العربون',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _depositPct,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'النسبة من الإجمالي', suffixText: '%'),
              ),
              const SizedBox(height: NSpace.sm),
              TextField(
                controller: _depositRound,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'التقريب لأعلى إلى مضاعفات', suffixText: 'د.ع'),
              ),
              const SizedBox(height: NSpace.sm),
              if (base > 0)
                Text('مثال: كتاب بـ ${formatIqd(base)} ← عربون ${formatIqd(dep(base))}', style: t.bodyMedium),
            ]),
          )),
          _box(AdminCard(
            title: 'أرقام المحافظ (تظهر للزبون عند دفع العربون)',
            child: Column(children: [
              for (final e in Wallets.labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: NSpace.sm),
                  child: TextField(
                    controller: _wallets[e.key],
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: e.value),
                  ),
                ),
            ]),
          )),
          _box(AdminCard(
            title: 'الإشعارات والخصوصية',
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'بريد إشعارات الطلبات'),
              ),
              Text('يجب أن يكون نفس بريد حساب Resend.', style: t.bodySmall),
              const SizedBox(height: NSpace.md),
              TextField(
                controller: _purgeHours,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'حذف صور الطلب بعد الطباعة بـ', suffixText: 'ساعة'),
              ),
              const SizedBox(height: NSpace.sm),
              TextField(
                controller: _purgeDays,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'أو بعد إنشاء الطلب بحد أقصى', suffixText: 'يوم'),
              ),
            ]),
          )),
          _box(_TeamCard(me: widget.me)),
        ]),
      ],
    );
  }

  Widget _box(Widget child) => LayoutBuilder(builder: (context, _) {
        final w = MediaQuery.sizeOf(context).width;
        final cardW = w >= 1300 ? (w - 140) / 2 - NSpace.md : w;
        return SizedBox(width: cardW.clamp(280, 900), child: child);
      });
}

class _TeamCard extends ConsumerWidget {
  const _TeamCard({required this.me});
  final AdminMe me;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final pass = TextEditingController();
    final name = TextEditingController();
    var role = AdminRole.staff;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('إضافة حساب للوحة'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'الاسم')),
              const SizedBox(height: NSpace.sm),
              TextField(
                controller: email,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'البريد'),
              ),
              const SizedBox(height: NSpace.sm),
              TextField(
                controller: pass,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'كلمة مرور مؤقتة (8 أحرف على الأقل)'),
              ),
              const SizedBox(height: NSpace.sm),
              SegmentedButton<AdminRole>(
                segments: const [
                  ButtonSegment(value: AdminRole.staff, label: Text('موظف')),
                  ButtonSegment(value: AdminRole.owner, label: Text('مالك')),
                ],
                selected: {role},
                onSelectionChanged: (v) => set(() => role = v.first),
              ),
              const SizedBox(height: NSpace.xs),
              Text(
                role == AdminRole.staff
                    ? 'الموظف: الطلبات والحالات والقوالب فقط.'
                    : 'المالك: كل الصلاحيات، ومنها الأسعار والمحافظ والفريق.',
                style: Theme.of(c).textTheme.bodySmall,
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(adminRepositoryProvider)
          .addMember(email: email.text, password: pass.text, role: role, name: name.text);
      ref.invalidate(_teamProvider);
      messenger.showSnackBar(SnackBar(content: Text('أُضيف ${email.text.trim()}. أرسل له كلمة المرور بنفسك.')));
    } on AdminFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, TeamMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الحساب'),
        content: Text('سيُحذف حساب ${m.email} ولن يتمكن من دخول اللوحة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: NColors.danger),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).removeMember(m.userId);
      ref.invalidate(_teamProvider);
    } on AdminFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final team = ref.watch(_teamProvider);
    return AdminCard(
      title: 'فريق اللوحة',
      trailing: TextButton.icon(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt_rounded),
        label: const Text('إضافة'),
      ),
      child: team.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => const Text('تعذّر تحميل الفريق.'),
        data: (list) => Column(children: [
          for (final m in list)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(m.role == AdminRole.owner ? Icons.workspace_premium_outlined : Icons.badge_outlined),
              title: Text(m.name?.isNotEmpty == true ? m.name! : m.email),
              subtitle: Text('${m.email} · ${m.role == AdminRole.owner ? 'مالك' : 'موظف'}', style: t.bodySmall),
              trailing: m.userId == me.userId
                  ? Text('أنت', style: t.labelMedium)
                  : IconButton(
                      tooltip: 'حذف',
                      onPressed: () => _remove(context, ref, m),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
            ),
        ]),
      ),
    );
  }
}
