import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web/web.dart' as web;

import 'app.dart';
import 'core/config/env.dart';
import 'core/storage/web_storage.dart';

/// Shows a startup error on the loading screen (index.html), so a phone that
/// fails to open the site tells us why.
void _report(Object e, [StackTrace? st]) {
  final text = '$e${st == null ? '' : '\n${st.toString().split('\n').take(4).join('\n')}'}';
  try {
    if (globalContext.has('naseemReportError')) {
      globalContext.callMethod('naseemReportError'.toJS, text.toJS);
    }
  } catch (_) {}
  // ignore: avoid_print
  print('startup error: $text');
}

Future<void> _initSupabase() async {
  // Without browser storage the session lives in memory for this visit only.
  final auth = WebStorage.available
      ? const FlutterAuthClientOptions()
      : const FlutterAuthClientOptions(localStorage: EmptyLocalStorage());
  try {
    await Supabase.initialize(
        url: Env.supabaseUrl, publishableKey: Env.supabasePublishableKey, authOptions: auth);
  } catch (e, st) {
    // A stored session this browser can no longer read must not keep the site closed:
    // drop it and start signed out.
    _report(e, st);
    try {
      final ls = web.window.localStorage;
      for (var i = ls.length - 1; i >= 0; i--) {
        final k = ls.key(i);
        if (k != null && k.startsWith('sb-')) ls.removeItem(k);
      }
    } catch (_) {}
    await Supabase.initialize(
        url: Env.supabaseUrl,
        publishableKey: Env.supabasePublishableKey,
        authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()));
  }
}

Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    PlatformDispatcher.instance.onError = (e, st) {
      _report(e, st);
      return true;
    };
    FlutterError.onError = (d) {
      _report(d.exception, d.stack);
      FlutterError.presentError(d);
    };
    usePathUrlStrategy();
    // Drafts and the cart are kept in memory when the browser blocks storage.
    // ignore: invalid_use_of_visible_for_testing_member
    if (!WebStorage.available) SharedPreferences.setMockInitialValues({});
    try {
      await _initSupabase();
    } catch (e, st) {
      _report(e, st);
    }
    runApp(const ProviderScope(child: NaseemApp()));
  }, _report);
}
