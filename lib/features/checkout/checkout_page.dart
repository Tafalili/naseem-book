import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/models/page_template.dart';
import '../../data/models/product.dart';
import '../../data/models/public_settings.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/privacy_badge.dart';
import '../cart/cart_controller.dart';
import '../cart/pricing.dart';
import '../editor/draft/book_draft.dart';
import '../editor/draft/draft_controller.dart';
import '../editor/draft/readiness.dart';
import 'checkout_controller.dart';

const iraqGovernorates = [
  'بغداد', 'البصرة', 'نينوى', 'أربيل', 'السليمانية', 'دهوك', 'حلبجة', 'كركوك', 'الأنبار',
  'بابل', 'كربلاء', 'النجف', 'واسط', 'ديالى', 'صلاح الدين', 'القادسية', 'ذي قار', 'ميسان', 'المثنى',
];

/// Iraqi mobile: 07XXXXXXXXX, +9647XXXXXXXXX or 9647XXXXXXXXX → 07XXXXXXXXX.
String? normalizeIraqiPhone(String raw) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var s = raw.split('').map((c) => ar.contains(c) ? '${ar.indexOf(c)}' : c).join();
  s = s.replaceAll(RegExp(r'[\s\-()]'), '');
  final m = RegExp(r'^(?:\+?964|0)?(7\d{9})$').firstMatch(s);
  return m == null ? null : '0${m.group(1)}';
}

class CheckoutPage extends ConsumerStatefulWidget {
  const CheckoutPage({super.key});

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _notes = TextEditingController();
  String? _city;
  String? _loadedSlug;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(cartProvider);
    final t = Theme.of(context).textTheme;
    if (items.isEmpty) {
      return ContentWidth(
        vertical: NSpace.xxl,
        child: Column(children: [
          Text('لا يوجد كتاب في سلتك', style: t.titleLarge),
          const SizedBox(height: NSpace.md),
          FilledButton(onPressed: () => context.go(Routes.cart), child: const Text('العودة للسلة')),
        ]),
      );
    }
    final item = items.first;
    if (_loadedSlug != item.slug) {
      _loadedSlug = item.slug;
      Future.microtask(() => ref.read(draftProvider.notifier).load(item.slug));
    }
    final draft = ref.watch(draftProvider).draft;
    final pages = ref.watch(templatesProvider(item.slug));
    final product = ref.watch(productBySlugProvider(item.slug));
    final settings = ref.watch(publicSettingsProvider);

    if (pages.hasError || product.hasError || settings.hasError) {
      return ContentWidth(
        vertical: NSpace.xl,
        child: LoadError(onRetry: () {
          ref.invalidate(templatesProvider(item.slug));
          ref.invalidate(productBySlugProvider(item.slug));
          ref.invalidate(publicSettingsProvider);
        }),
      );
    }
    if (draft == null || draft.productSlug != item.slug || !pages.hasValue ||
        !product.hasValue || !settings.hasValue || product.value == null) {
      return const Padding(
        padding: EdgeInsets.all(NSpace.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final ready = Readiness.of(draft, pages.value!);
    final quote = buildQuote(product: product.value!, settings: settings.value!, draft: draft, item: item);
    final form = _formCard(context, draft, pages.value!, item, ready);
    final summary = _SummaryCard(quote: quote, product: product.value!, draft: draft, settings: settings.value!);

    return ContentWidth(
      vertical: NSpace.xl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(alignment: AlignmentDirectional.centerStart),
            onPressed: () => context.go(Routes.cart),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('السلة'),
          ),
          Text('إتمام الطلب', style: t.headlineMedium),
          const SizedBox(height: NSpace.lg),
          if (MediaQuery.sizeOf(context).width >= 1000)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: form),
              const SizedBox(width: NSpace.lg),
              SizedBox(width: 380, child: summary),
            ])
          else
            Column(children: [form, const SizedBox(height: NSpace.lg), summary]),
        ],
      ),
    );
  }

  Widget _formCard(BuildContext context, BookDraft draft, List<PageTemplate> pages, CartItem item, Readiness ready) {
    final t = Theme.of(context).textTheme;
    final st = ref.watch(checkoutProvider);
    return Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: const BoxDecoration(
        color: NColors.surface,
        borderRadius: BorderRadius.all(NRadius.lg),
        boxShadow: NShadow.soft,
      ),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('بيانات التوصيل', style: t.titleMedium),
            const SizedBox(height: NSpace.md),
            TextFormField(
              controller: _name,
              enabled: !st.busy,
              textInputAction: TextInputAction.next,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'الاسم الكامل', counterText: ''),
              validator: (v) => (v ?? '').trim().length < 2 ? 'اكتبي اسمك' : null,
            ),
            const SizedBox(height: NSpace.md),
            TextFormField(
              controller: _phone,
              enabled: !st.busy,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.right,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩+\s\-]'))],
              decoration: const InputDecoration(
                labelText: 'رقم الهاتف (واتساب)',
                hintText: '07XX XXX XXXX',
                hintTextDirection: TextDirection.ltr,
              ),
              validator: (v) => normalizeIraqiPhone(v ?? '') == null ? 'اكتبي رقماً عراقياً صحيحاً يبدأ بـ 07' : null,
            ),
            const SizedBox(height: NSpace.md),
            DropdownButtonFormField<String>(
              initialValue: _city,
              decoration: const InputDecoration(labelText: 'المحافظة'),
              items: [for (final g in iraqGovernorates) DropdownMenuItem(value: g, child: Text(g))],
              onChanged: st.busy ? null : (v) => setState(() => _city = v),
              validator: (v) => v == null ? 'اختاري المحافظة' : null,
            ),
            const SizedBox(height: NSpace.md),
            TextFormField(
              controller: _address,
              enabled: !st.busy,
              maxLines: 2,
              maxLength: 300,
              decoration: const InputDecoration(
                  labelText: 'العنوان بالتفصيل', hintText: 'المنطقة، الشارع، أقرب نقطة دالة'),
              validator: (v) => (v ?? '').trim().length < 3 ? 'اكتبي العنوان' : null,
            ),
            const SizedBox(height: NSpace.sm),
            TextFormField(
              controller: _notes,
              enabled: !st.busy,
              maxLines: 2,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
            ),
            if (ready.nameMissing)
              _Banner(
                color: NColors.danger,
                text: 'اسم الطفل على الغلاف غير مكتوب. أكمليه من التصميم قبل إرسال الطلب.',
                action: TextButton(
                    onPressed: () => context.go(Routes.editor(item.slug)), child: const Text('فتح التصميم')),
              ),
            if (st.error != null) _Banner(color: NColors.danger, text: st.error!),
            const SizedBox(height: NSpace.md),
            if (st.busy) ...[
              LinearProgressIndicator(
                value: st.toUpload == 0 ? null : st.uploaded / st.toUpload,
                minHeight: 6,
                borderRadius: const BorderRadius.all(NRadius.pill),
              ),
              const SizedBox(height: NSpace.sm),
              Text(
                st.toUpload == 0 ? st.stage : '${st.stage} (${st.uploaded} من ${st.toUpload})',
                textAlign: TextAlign.center,
                style: t.bodyMedium,
              ),
              Text('لا تغلقي الصفحة حتى يكتمل الإرسال.', textAlign: TextAlign.center, style: t.bodySmall),
            ] else
              FilledButton.icon(
                onPressed: ready.nameMissing ? null : () => _submit(draft, pages, item),
                icon: const Icon(Icons.send_rounded),
                label: const Text('إرسال الطلب'),
              ),
            const SizedBox(height: NSpace.md),
            const PrivacyBadge(dense: true),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(BookDraft draft, List<PageTemplate> pages, CartItem item) async {
    if (!_form.currentState!.validate()) return;
    final code = await ref.read(checkoutProvider.notifier).submit(
          draft: draft,
          pages: pages,
          item: item,
          customer: CustomerInfo(
            name: _name.text.trim(),
            phone: normalizeIraqiPhone(_phone.text)!,
            city: _city!,
            address: _address.text.trim(),
            notes: _notes.text.trim(),
          ),
        );
    if (code != null && mounted) context.go(Routes.order(code));
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text, this.action});
  final Color color;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: NSpace.md),
      padding: const EdgeInsets.symmetric(horizontal: NSpace.md, vertical: NSpace.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: const BorderRadius.all(NRadius.md),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, color: color, size: 20),
        const SizedBox(width: NSpace.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ?action,
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.quote, required this.product, required this.draft, required this.settings});
  final Quote quote;
  final Product product;
  final BookDraft draft;
  final PublicSettings settings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final priced = !quote.hasUnpriced;
    Widget line(String a, String b, {TextStyle? style}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(a, style: style ?? t.bodyMedium)),
            Text(b, style: style ?? t.bodyMedium),
          ]),
        );
    final name = draft.cover.childName.trim();
    return Container(
      padding: const EdgeInsets.all(NSpace.lg),
      decoration: const BoxDecoration(
        color: NColors.surface,
        borderRadius: BorderRadius.all(NRadius.lg),
        boxShadow: NShadow.soft,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name.isEmpty ? product.title : '${product.title} · $name', style: t.titleMedium),
          const SizedBox(height: NSpace.sm),
          for (final l in quote.lines)
            line(l.qty > 1 ? '${l.label} × ${l.qty}' : l.label, l.unpriced ? 'قريباً' : formatIqd(l.amount)),
          const Divider(height: NSpace.lg, color: NColors.line),
          line('الإجمالي', priced ? formatIqd(quote.total) : 'يُحدد عند التأكيد', style: t.titleMedium),
          if (priced && quote.depositPercent > 0)
            line('العربون الآن (${quote.depositPercent.round()}%)', formatIqd(quote.deposit),
                style: t.bodyMedium?.copyWith(color: NColors.sageDark, fontWeight: FontWeight.w600)),
          const SizedBox(height: NSpace.md),
          Container(
            padding: const EdgeInsets.all(NSpace.md),
            decoration: const BoxDecoration(color: NColors.sageSoft, borderRadius: BorderRadius.all(NRadius.md)),
            child: Text(
              'بعد الإرسال تظهر لكِ أرقام الدفع (زين كاش، كي كارد، FIB). ادفعي العربون وارفعي صورة الإيصال، '
              'ونبدأ بكتابك بعد مراجعته.',
              style: t.bodySmall?.copyWith(color: NColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}
