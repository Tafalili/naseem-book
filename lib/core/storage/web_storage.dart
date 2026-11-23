import 'package:web/web.dart' as web;

/// Whether this browser lets the site keep data (localStorage / IndexedDB).
/// Safari with "Block All Cookies" (and some in-app browsers) throws a
/// SecurityError on any access; the site then runs from memory only.
abstract final class WebStorage {
  static final bool available = _probe();

  static bool _probe() {
    try {
      final ls = web.window.localStorage;
      ls.setItem('_naseem_probe', '1');
      ls.removeItem('_naseem_probe');
      web.window.indexedDB; // throws in the same blocked contexts
      return true;
    } catch (_) {
      return false;
    }
  }
}
