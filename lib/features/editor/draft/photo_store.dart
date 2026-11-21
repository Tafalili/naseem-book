import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Minimal IndexedDB store for draft photos (full + preview JPEG blobs).
/// Keys: `id:full`, `id:preview`.
class PhotoStore {
  PhotoStore._();
  static final instance = PhotoStore._();

  static const _dbName = 'naseem_drafts';
  static const _store = 'photos';
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
        final c = Completer<web.IDBDatabase>();
        final req = web.window.indexedDB.open(_dbName, 1);
        req.onupgradeneeded = ((web.Event _) {
          final db = req.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
        }).toJS;
        req.onsuccess = ((web.Event _) => c.complete(req.result as web.IDBDatabase)).toJS;
        req.onerror = ((web.Event _) => c.completeError(StateError('IndexedDB unavailable'))).toJS;
        return c.future;
      }();

  Future<T> _request<T>(web.IDBRequest req, T Function(JSAny?) map) {
    final c = Completer<T>();
    req.onsuccess = ((web.Event _) => c.complete(map(req.result))).toJS;
    req.onerror = ((web.Event _) => c.completeError(StateError('IndexedDB request failed'))).toJS;
    return c.future;
  }

  Future<web.IDBObjectStore> _tx(String mode) async {
    final db = await _open();
    return db.transaction(_store.toJS, mode).objectStore(_store);
  }

  Future<void> put(String id, {required web.Blob full, required web.Blob preview}) async {
    final s = await _tx('readwrite');
    await _request(s.put(full, '$id:full'.toJS), (_) => null);
    final s2 = await _tx('readwrite');
    await _request(s2.put(preview, '$id:preview'.toJS), (_) => null);
  }

  Future<Uint8List?> _bytes(String key) async {
    final s = await _tx('readonly');
    final blob = await _request<web.Blob?>(s.get(key.toJS), (r) => r as web.Blob?);
    if (blob == null) return null;
    final buf = await blob.arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  }

  Future<Uint8List?> preview(String id) => _bytes('$id:preview');
  Future<Uint8List?> full(String id) => _bytes('$id:full');

  Future<void> delete(String id) async {
    for (final k in ['$id:full', '$id:preview']) {
      final s = await _tx('readwrite');
      await _request(s.delete(k.toJS), (_) => null);
    }
  }
}
