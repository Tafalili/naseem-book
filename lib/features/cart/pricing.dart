import '../../data/models/page_template.dart';
import '../../data/models/product.dart';
import '../../data/models/public_settings.dart';
import '../editor/draft/book_draft.dart';
import 'cart_controller.dart';

class QuoteLine {
  const QuoteLine(this.label, this.unit, {this.qty = 1, this.auto = false});
  final String label;
  final int unit; // IQD per unit; 0 = not priced yet
  final int qty;
  final bool auto; // added because of a choice inside the editor
  int get amount => unit * qty;
  bool get unpriced => unit <= 0;
}

/// Client-side estimate. The order total is recomputed on the server by
/// submit_order() from app_settings, using the same rules.
class Quote {
  Quote(this.lines, this.settings);
  final List<QuoteLine> lines;
  final PublicSettings settings;

  int get total => lines.fold(0, (s, l) => s + l.amount);
  int get deposit => settings.depositFor(total);
  bool get hasDeposit => settings.depositPercent > 0;
  bool get hasUnpriced => lines.any((l) => l.unpriced);
}

Quote buildQuote({
  required Product product,
  required PublicSettings settings,
  required BookDraft draft,
  required CartItem item,
  required List<PageTemplate> pages,
}) {
  int p(Addon a) => settings.priceOf(a);
  final slotIds = {for (final pg in pages) ...pg.photoSlots.map((s) => s.id)};
  final filled = draft.placements.keys.where(slotIds.contains).length;
  return Quote([
    QuoteLine(product.title, product.basePrice),
    // One cover charge: «اتركه لذوقكم» already includes the name.
    if (draft.cover.childName.trim().isNotEmpty && draft.cover.mode != CoverMode.designer)
      QuoteLine(Addon.childName.label, p(Addon.childName), auto: true),
    if (filled > 0)
      QuoteLine('${Addon.photos.label} ($filled من ${slotIds.length})',
          photosPrice(p(Addon.photos), filled, slotIds.length),
          auto: true),
    if (draft.hasPrintedText) QuoteLine(Addon.printedText.label, p(Addon.printedText), auto: true),
    if (draft.cover.mode == CoverMode.designer)
      QuoteLine(Addon.designerCover.label, p(Addon.designerCover), auto: true),
    if (item.giftWrap) QuoteLine(Addon.giftWrap.label, p(Addon.giftWrap)),
    if (item.extraCopies > 0)
      QuoteLine(Addon.extraCopy.label, p(Addon.extraCopy), qty: item.extraCopies),
  ], settings);
}

/// Photos are priced pro rata: [full] buys every frame; rounded up to 250 IQD.
int photosPrice(int full, int filled, int totalSlots) {
  if (full <= 0 || filled <= 0 || totalSlots <= 0) return 0;
  if (filled >= totalSlots) return full;
  return ((full * filled / totalSlots) / 250).ceil() * 250;
}
