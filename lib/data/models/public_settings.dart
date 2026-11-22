/// Optional paid features shown on the product page. Keys mirror app_settings.prices.
enum Addon {
  childName('child_name', 'اسم الطفل على الغلاف', 'بدل «نسيم» نكتب اسم طفلك على الواجهة'),
  photos('photos', 'صورك داخل الكتاب', 'تملئين الإطارات بصورك، حتى 34 صورة'),
  printedText('printed_text', 'نص مطبوع داخل الصفحات', 'بدل الأسطر الفارغة التي تكتبينها بيدك'),
  designerCover('designer_cover', 'اتركي الغلاف للمصمم', 'نصمم الغلاف لكِ باسم طفلك'),
  smartManuscript('smart_manuscript', 'المخطوطة الذكية', 'نصوص مقترحة جاهزة لكل صفحة'),
  giftWrap('gift_wrap', 'تغليف هدية', 'علبة وتغليف أنيق جاهز للإهداء'),
  extraCopy('extra_copy', 'نسخة إضافية', 'نسخة ثانية من نفس الكتاب');

  const Addon(this.key, this.label, this.hint);
  final String key;
  final String label;
  final String hint;
}

class PublicSettings {
  const PublicSettings({
    required this.prices,
    required this.depositPercent,
    required this.purgeAfterPrintHours,
    required this.purgeMaxDays,
  });

  final Map<String, int> prices;
  final double depositPercent;
  final int purgeAfterPrintHours;
  final int purgeMaxDays;

  int priceOf(Addon a) => prices[a.key] ?? 0;

  factory PublicSettings.fromJson(Map<String, dynamic> j) => PublicSettings(
        prices: ((j['prices'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k as String, (v as num).toInt())),
        depositPercent: (j['deposit_percent'] as num?)?.toDouble() ?? 0,
        purgeAfterPrintHours: (j['purge_after_print_hours'] as num?)?.toInt() ?? 48,
        purgeMaxDays: (j['purge_max_days'] as num?)?.toInt() ?? 14,
      );
}
