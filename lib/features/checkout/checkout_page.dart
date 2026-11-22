import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/format/money.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/tokens.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/widgets/layout.dart';
import '../../shared/widgets/privacy_badge.dart';
import '../cart/cart_controller.dart';
import '../cart/cart_page.dart';
import '../cart/pricing.dart';
import '../editor/draft/draft_controller.dart';
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
    final settings = ref.watch(publicSettingsProvider);
    List<CartBook>? books;
    try {
      books = watchCartBooks(ref, items);
      if (settings.hasError) throw settings.error!;
    } catch (_) {
      return ContentWidth(
        vertical: NSpace.xl,
        child: LoadError(onRetry: () {
          for (final it in items) {
            ref.invalidate(savedDraftProvider(it.book));
            ref.invalidate(templatesProvider(it.slug));
            ref.invalidate(productBySlugProvider(it.slug));
          }
          ref.invalidate(publicSettingsProvider);
        }),
      );
    }
    if (books == null || books.isEmpty || !settings.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(NSpace.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final quote = quoteCart(books, settings.value!);
    final form = _formCard(context, books);
    final summary = _SummaryCard(quote: quote, books: books);

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

  Widget _formCard(BuildContext context, List<CartBook> books) {
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
                onPressed: () => _submit(books),
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

  Future<void> _submit(List<CartBook> books) async {
    if (!_form.currentState!.validate()) return;
    final code = await ref.read(checkoutProvider.notifier).submit(
          books: books,
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
  const _Banner({required this.color, required this.text});
  final Color color;
  final String text;

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
      ]),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.quote, required this.books});
  final OrderQuote quote;
  final List<CartBook> books;

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
    String amount(QuoteLine l) => l.free ? 'مجاناً' : l.unpriced ? 'قريباً' : formatIqd(l.amount);
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
          for (var i = 0; i < books.length; i++) ...[
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : NSpace.md, bottom: NSpace.xs),
              child: Text(
                  books.length > 1
                      ? bookTitle(books[i], i)
                      : books[i].draft.cover.childName.trim().isEmpty
                          ? books[i].product.title
                          : '${books[i].product.title} · ${books[i].draft.cover.childName.trim()}',
                  style: t.titleMedium),
            ),
            for (final l in quote.books[i].lines)
              line(l.qty > 1 ? '${l.label} × ${l.qty}' : l.label, amount(l)),
          ],
          const Divider(height: NSpace.lg, color: NColors.line),
          if (quote.saved > 0)
            line('وفّرتِ (غلاف مجاني لكل كتاب)', formatIqd(quote.saved),
                style: t.bodyMedium?.copyWith(color: NColors.sageDark)),
          line('الإجمالي', priced ? formatIqd(quote.total) : 'يُحدد عند التأكيد', style: t.titleMedium),
          if (priced && quote.hasDeposit)
            line('العربون الآن', formatIqd(quote.deposit),
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
