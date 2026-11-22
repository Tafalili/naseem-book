import '../../../data/models/page_template.dart';
import 'book_draft.dart';

/// What still needs attention before the book can go to the cart.
class Readiness {
  const Readiness({
    required this.nameMissing,
    required this.emptyPages,
    required this.emptySlots,
    required this.totalSlots,
  });

  final bool nameMissing;
  final List<int> emptyPages; // page numbers with at least one empty frame
  final int emptySlots, totalSlots;

  /// Nothing blocks: the name and the photos are paid options.
  bool get blocking => false;
  bool get complete => !nameMissing && emptySlots == 0;

  factory Readiness.of(BookDraft d, List<PageTemplate> pages) {
    final empty = <int>[];
    var emptySlots = 0, total = 0;
    for (final p in pages) {
      var pageEmpty = false;
      for (final s in p.photoSlots) {
        total++;
        if (!d.placements.containsKey(s.id)) {
          emptySlots++;
          pageEmpty = true;
        }
      }
      if (pageEmpty) empty.add(p.pageNumber);
    }
    return Readiness(
      nameMissing: d.cover.childName.trim().isEmpty,
      emptyPages: empty,
      emptySlots: emptySlots,
      totalSlots: total,
    );
  }
}
