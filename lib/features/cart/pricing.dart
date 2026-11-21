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
  Quote(this.lines, this.depositPercent);
  final List<QuoteLine> lines;
  final double depositPercent;

  int get total => lines.fold(0, (s, l) => s + l.amount);
  int get deposit => (total * depositPercent / 100).round();
  bool get hasUnpriced => lines.any((l) => l.unpriced);
}

Quote buildQuote({
  required Product product,
  required PublicSettings settings,
  required BookDraft draft,
  required CartItem item,
}) {
  int p(Addon a) => settings.priceOf(a);
  return Quote([
    QuoteLine(product.title, product.basePrice),
    if (draft.hasPrintedText) QuoteLine(Addon.printedText.label, p(Addon.printedText), auto: true),
    if (draft.cover.mode == CoverMode.designer)
      QuoteLine(Addon.designerCover.label, p(Addon.designerCover), auto: true),
    if (item.giftWrap) QuoteLine(Addon.giftWrap.label, p(Addon.giftWrap)),
    if (item.extraCopies > 0)
      QuoteLine(Addon.extraCopy.label, p(Addon.extraCopy), qty: item.extraCopies),
  ], settings.depositPercent);
}
