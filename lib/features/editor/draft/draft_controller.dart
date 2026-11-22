import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'book_draft.dart';
import 'image_tools.dart';
import 'photo_store.dart';

class DraftState {
  const DraftState({this.draft, this.importing = 0, this.error});
  final BookDraft? draft;
  final int importing; // photos currently being compressed
  final String? error;

  DraftState copyWith({BookDraft? draft, int? importing, String? error, bool clearError = false}) =>
      DraftState(
        draft: draft ?? this.draft,
        importing: importing ?? this.importing,
        error: clearError ? null : (error ?? this.error),
      );
}

class DraftController extends Notifier<DraftState> {
  static String _key(String slug) => 'draft:$slug';
  final _rand = math.Random();

  @override
  DraftState build() => const DraftState();

  Future<void> load(String slug) async {
    if (state.draft?.productSlug == slug) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(slug));
    BookDraft draft;
    try {
      draft = raw == null
          ? BookDraft(productSlug: slug)
          : BookDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      draft = BookDraft(productSlug: slug);
    }
    state = DraftState(draft: draft);
  }

  Future<void> _save(BookDraft d) async {
    state = state.copyWith(draft: d);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(d.productSlug), jsonEncode(d.toJson()));
  }

  BookDraft get _d => state.draft!;

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 20).toRadixString(36)}';

  /// Picks and compresses photos; returns the new photo ids in pick order.
  Future<List<String>> importPhotos({bool multiple = true}) async {
    final files = await pickImages(multiple: multiple);
    if (files.isEmpty) return const [];
    state = state.copyWith(importing: state.importing + files.length, clearError: true);
    final ids = <String>[];
    var failed = 0;
    for (final f in files) {
      try {
        final c = await compressPhoto(f);
        final id = _newId();
        await PhotoStore.instance.put(id, full: c.full, preview: c.preview);
        ids.add(id);
        await _save(_d.copyWith(photos: [..._d.photos, PhotoRef(id: id, width: c.width, height: c.height)]));
      } catch (_) {
        failed++;
      } finally {
        state = state.copyWith(importing: state.importing - 1);
      }
    }
    if (failed > 0) {
      state = state.copyWith(error: 'تعذّر قراءة $failed من الصور. جرّبي صيغة JPG أو PNG.');
    }
    return ids;
  }

  Future<void> removePhoto(String id) async {
    final placements = {..._d.placements}..removeWhere((_, p) => p.photoId == id);
    var cover = _d.cover;
    if (cover.element?.photoId == id) cover = cover.copyWith(clearElement: true);
    await _save(_d.copyWith(
      photos: _d.photos.where((p) => p.id != id).toList(),
      placements: placements,
      cover: cover,
    ));
    await PhotoStore.instance.delete(id);
  }

  Future<void> place(String slotId, String photoId) =>
      _save(_d.copyWith(placements: {..._d.placements, slotId: Placement(photoId: photoId)}));

  Future<void> updatePlacement(String slotId, Placement p) =>
      _save(_d.copyWith(placements: {..._d.placements, slotId: p}));

  Future<void> clearSlot(String slotId) =>
      _save(_d.copyWith(placements: {..._d.placements}..remove(slotId)));

  /// Fills empty slots (in page order) with photos not used yet.
  Future<int> autoFill(List<String> slotIdsInOrder) async {
    final used = _d.usedPhotoIds;
    final free = _d.photos.where((p) => !used.contains(p.id)).map((p) => p.id).toList();
    final placements = {..._d.placements};
    var n = 0;
    for (final s in slotIdsInOrder) {
      if (free.isEmpty) break;
      if (placements.containsKey(s)) continue;
      placements[s] = Placement(photoId: free.removeAt(0));
      n++;
    }
    await _save(_d.copyWith(placements: placements));
    return n;
  }

  Future<void> setText(String slotId, String text) {
    final texts = {..._d.texts};
    if (text.trim().isEmpty) {
      texts.remove(slotId);
    } else {
      texts[slotId] = text.trim();
    }
    return _save(_d.copyWith(texts: texts));
  }

  Future<void> updateCover(CoverDesign cover) => _save(_d.copyWith(cover: cover));

  /// After a successful order: drop the local draft and its photos.
  Future<void> discard(String slug) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(slug));
    if (raw != null) {
      try {
        final d = BookDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        for (final p in d.photos) {
          await PhotoStore.instance.delete(p.id);
        }
      } catch (_) {}
    }
    await prefs.remove(_key(slug));
    if (state.draft?.productSlug == slug) state = DraftState(draft: BookDraft(productSlug: slug));
  }
}

final draftProvider = NotifierProvider<DraftController, DraftState>(DraftController.new);

/// Preview bytes for a stored photo (cached per id).
final photoPreviewProvider = FutureProvider.family<Uint8List?, String>(
    (ref, id) => PhotoStore.instance.preview(id));
