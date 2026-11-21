import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../shared/widgets/privacy_badge.dart';

/// Verifies the client can reach Supabase through the public RPC.
final backendHealthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final res = await Supabase.instance.client.rpc('get_public_settings');
  return Map<String, dynamic>.from(res as Map);
});

class StyleGuidePage extends StatelessWidget {
  const StyleGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: NBreakpoints.maxContent),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: NSpace.md, vertical: NSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Hero(),
                  _Section(title: 'الألوان', child: _Palette()),
                  _Section(title: 'خطوط العناوين (اختر واحداً)', child: _HeadingFonts()),
                  _Section(title: 'الخطوط داخل الكتاب', child: _BookFonts()),
                  _Section(title: 'سُلّم الأحجام', child: _TypeScale()),
                  _Section(title: 'العناصر', child: _Components()),
                  _Section(title: 'الخط الزمني لتتبع الطلب', child: _Timeline()),
                  _Section(title: 'الاتصال بالسيرفر', child: _BackendHealth()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(NSpace.xl),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [NColors.sageSoft, NColors.sandSoft, NColors.skySoft],
        ),
        borderRadius: BorderRadius.all(NRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('كتاب نسيم', style: t.displayMedium),
          const SizedBox(height: NSpace.sm),
          Text('أول ذكريات طفلك، في كتاب يُصنع باليد خصيصاً له',
              style: t.titleLarge?.copyWith(fontWeight: FontWeight.w400)),
          const SizedBox(height: NSpace.lg),
          const PrivacyBadge(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: NSpace.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: NSpace.md),
          child,
        ],
      ),
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette();

  static const _swatches = <(String, String, Color)>[
    ('ورق (الخلفية)', 'paper', NColors.paper),
    ('سطح ثانوي', 'surfaceAlt', NColors.surfaceAlt),
    ('حدود', 'line', NColors.line),
    ('حبر (النص)', 'ink', NColors.ink),
    ('نص ثانوي', 'inkMuted', NColors.inkMuted),
    ('مريمية (أساسي)', 'sage', NColors.sage),
    ('مريمية داكن', 'sageDark', NColors.sageDark),
    ('مريمية فاتح', 'sageSoft', NColors.sageSoft),
    ('رملي (ثانوي)', 'sand', NColors.sand),
    ('رملي فاتح', 'sandSoft', NColors.sandSoft),
    ('سماوي (مكمّل)', 'sky', NColors.sky),
    ('سماوي فاتح', 'skySoft', NColors.skySoft),
    ('ذهبي التجليد', 'gold', NColors.gold),
    ('نجاح', 'success', NColors.success),
    ('تنبيه', 'warning', NColors.warning),
    ('خطأ', 'danger', NColors.danger),
  ];

  String _hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Wrap(
      spacing: NSpace.md,
      runSpacing: NSpace.md,
      children: [
        for (final (label, token, color) in _swatches)
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 72,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: const BorderRadius.all(NRadius.md),
                    border: Border.all(color: NColors.line),
                  ),
                ),
                const SizedBox(height: NSpace.xs),
                Text(label, style: t.labelLarge),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('$token  ${_hex(color)}', style: t.labelSmall),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FontSample extends StatelessWidget {
  const _FontSample({
    required this.name,
    required this.family,
    required this.sample,
    this.size = 34,
    this.note,
  });
  final String name;
  final String family;
  final String sample;
  final double size;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(name, style: t.labelLarge?.copyWith(color: NColors.sageDark)),
                if (note != null) ...[
                  const SizedBox(width: NSpace.sm),
                  Text(note!, style: t.labelSmall),
                ],
              ],
            ),
            const SizedBox(height: NSpace.sm),
            Text(sample,
                style: TextStyle(
                    fontFamily: family, fontSize: size, height: 1.6, color: NColors.ink)),
          ],
        ),
      ),
    );
  }
}

class _HeadingFonts extends StatelessWidget {
  const _HeadingFonts();

  @override
  Widget build(BuildContext context) {
    const s = 'اصنعي كتاب ذكريات طفلك الأول';
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NSpace.md,
      children: [
        _FontSample(name: 'أ) ريم كوفي', family: NFonts.display, sample: s, note: '(المقترح)'),
        _FontSample(name: 'ب) مرحي', family: NFonts.playful, sample: s, note: 'طفولي ومرح'),
        _FontSample(name: 'ج) تجوّل', family: NFonts.tajawal, sample: s, note: 'بسيط وعصري'),
        _FontSample(
            name: 'خط الواجهة والنصوص', family: NFonts.ui, size: 20, note: 'IBM Plex Sans Arabic',
            sample: 'ارفعي صور طفلك، ورتّبيها داخل الإطارات، ثم راجعي الكتاب صفحةً صفحة قبل الطلب.'),
      ],
    );
  }
}

class _BookFonts extends StatelessWidget {
  const _BookFonts();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NSpace.md,
      children: [
        _FontSample(name: 'اسم الطفل على الغلاف', family: NFonts.ruqaa, sample: 'نسيم', size: 64,
            note: 'Aref Ruqaa (رقعة)'),
        _FontSample(name: 'النص المطبوع داخل الصفحات', family: NFonts.naskh, size: 24,
            note: 'Amiri (نسخ)',
            sample: 'في هذا اليوم ابتسمتَ لأول مرة، فامتلأ البيت كلّه بالفرح.'),
      ],
    );
  }
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rows = <(String, TextStyle?)>[
      ('displayMedium 44', t.displayMedium),
      ('headlineMedium 28', t.headlineMedium),
      ('titleLarge 20', t.titleLarge),
      ('bodyLarge 17', t.bodyLarge),
      ('bodyMedium 15', t.bodyMedium),
      ('labelSmall 12', t.labelSmall),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: NSpace.sm,
          children: [
            for (final (k, s) in rows)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text('كتاب نسيم', style: s, maxLines: 1)),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(k, style: t.labelSmall),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Components extends StatelessWidget {
  const _Components();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: NSpace.lg,
      children: [
        Wrap(
          spacing: NSpace.md,
          runSpacing: NSpace.md,
          children: [
            FilledButton(onPressed: () {}, child: const Text('اطلبي الآن')),
            OutlinedButton(onPressed: () {}, child: const Text('معاينة الكتاب')),
            TextButton(onPressed: () {}, child: const Text('تفاصيل أكثر')),
            const FilledButton(onPressed: null, child: Text('غير متاح')),
          ],
        ),
        Wrap(
          spacing: NSpace.sm,
          runSpacing: NSpace.sm,
          children: const [
            Chip(label: Text('نص مطبوع')),
            Chip(label: Text('اتركه للمصمم')),
            Chip(label: Text('تغليف هدية')),
            Chip(
              avatar: Icon(Icons.check_rounded, size: 16, color: NColors.sageDark),
              label: Text('نسخة إضافية'),
              backgroundColor: NColors.sageSoft,
            ),
          ],
        ),
        const SizedBox(
          width: 420,
          child: TextField(decoration: InputDecoration(hintText: 'اسم الطفل')),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(
            width: 320,
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 185.5 / 274.5, // trim size
                    child: Container(
                      color: NColors.sandSoft,
                      alignment: Alignment.center,
                      child: Text('نسيم',
                          style: const TextStyle(
                              fontFamily: NFonts.ruqaa, fontSize: 56, color: NColors.sageDark)),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(NSpace.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('كتاب نسيم الكلاسيكي', style: t.titleMedium),
                        Text('34 صفحة · 36 صورة · ورق مطفي 250 غرام', style: t.bodySmall),
                        const SizedBox(height: NSpace.sm),
                        Text('— د.ع', style: t.titleLarge?.copyWith(color: NColors.sageDark)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline();

  static const _steps = <(String, String)>[
    ('🧾', 'استلمنا طلبك'),
    ('💳', 'نراجع العربون'),
    ('✅', 'تم تأكيد طلبك'),
    ('🎨', 'نصمم كتابك'),
    ('🖨️', 'قيد الطباعة والتجليد'),
    ('🚚', 'في الطريق إليك'),
    ('🎁', 'تم التسليم'),
  ];
  static const _current = 3;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NSpace.lg),
        child: Column(
          children: [
            for (var i = 0; i < _steps.length; i++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 40,
                      child: Column(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i <= _current ? NColors.sageSoft : NColors.surfaceAlt,
                              border: Border.all(
                                color: i == _current ? NColors.sage : NColors.line,
                                width: i == _current ? 2 : 1,
                              ),
                            ),
                            child: Opacity(
                              opacity: i <= _current ? 1 : .4,
                              child: Text(_steps[i].$1, style: const TextStyle(fontSize: 16)),
                            ),
                          ),
                          if (i < _steps.length - 1)
                            Expanded(
                              child: Container(
                                width: 2,
                                color: i < _current ? NColors.sage : NColors.line,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: NSpace.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 6, bottom: NSpace.lg),
                        child: Text(
                          _steps[i].$2,
                          style: (i == _current ? t.titleMedium : t.bodyMedium)?.copyWith(
                            color: i <= _current ? NColors.ink : NColors.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackendHealth extends ConsumerWidget {
  const _BackendHealth();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final health = ref.watch(backendHealthProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(NSpace.lg),
        child: health.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Row(children: [
            const Icon(Icons.error_outline, color: NColors.danger),
            const SizedBox(width: NSpace.sm),
            Expanded(child: Text('تعذّر الاتصال: $e', style: t.bodyMedium)),
          ]),
          data: (s) => Row(children: [
            const Icon(Icons.check_circle_outline, color: NColors.success),
            const SizedBox(width: NSpace.sm),
            Expanded(
              child: Text(
                'متصل بـ Supabase. نسبة العربون الحالية: ${s['deposit_percent']}٪، '
                'حذف الصور بعد ${s['purge_after_print_hours']} ساعة من الطباعة.',
                style: t.bodyMedium,
              ),
            ),
            IconButton(
              tooltip: 'نسخ',
              icon: const Icon(Icons.copy_rounded, size: 18),
              onPressed: () => Clipboard.setData(ClipboardData(text: s.toString())),
            ),
          ]),
        ),
      ),
    );
  }
}
