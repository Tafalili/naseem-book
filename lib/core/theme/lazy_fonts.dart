import 'package:flutter/services.dart';

import 'typography.dart';

/// Book fonts (printed text, cover name) are not bundled with the storefront's
/// startup fonts: they are fetched the first time a page that draws the book
/// needs them. Text already on screen re-lays out once they arrive.
abstract final class LazyFonts {
  static Future<void>? _loading;

  static const _files = {
    NFonts.naskh: ['Amiri-Regular.ttf', 'Amiri-Bold.ttf'],
    NFonts.ruqaa: ['ArefRuqaa-Regular.ttf', 'ArefRuqaa-Bold.ttf'],
    NFonts.playful: ['Marhey-Variable.ttf'],
  };

  /// Starts loading (once) and completes when every book font is ready.
  static Future<void> ensure() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      await Future.wait([
        for (final e in _files.entries)
          (FontLoader(e.key)
                ..addFontsOf(e.value))
              .load(),
      ]);
    } catch (_) {
      _loading = null; // let a later page try again
    }
  }
}

extension on FontLoader {
  void addFontsOf(List<String> files) {
    for (final f in files) {
      addFont(rootBundle.load('assets/fonts/lazy/$f'));
    }
  }
}
