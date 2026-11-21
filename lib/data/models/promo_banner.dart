import '../storage_urls.dart';

enum BannerTheme { sage, sand, sky }

class PromoBanner {
  const PromoBanner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imagePath,
    this.theme = BannerTheme.sage,
    this.ctaLabel,
    this.productSlug,
    this.externalUrl,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? imagePath;
  final BannerTheme theme;
  final String? ctaLabel;
  final String? productSlug;
  final String? externalUrl;

  static const columns =
      'id,title,subtitle,image_path,theme,cta_label,external_url,product:products(slug)';

  factory PromoBanner.fromJson(Map<String, dynamic> j) => PromoBanner(
        id: j['id'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        imagePath: j['image_path'] as String?,
        theme: BannerTheme.values.asNameMap()[j['theme']] ?? BannerTheme.sage,
        ctaLabel: j['cta_label'] as String?,
        productSlug: (j['product'] as Map?)?['slug'] as String?,
        externalUrl: j['external_url'] as String?,
      );

  String? get imageUrl => templatesUrl(imagePath);
}
