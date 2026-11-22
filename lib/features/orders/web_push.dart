import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../core/config/env.dart';

/// Browser push for order updates. On iPhone this works only after the site
/// is added to the Home Screen (Safari 16.4+).
abstract final class WebPush {
  static bool get supported =>
      globalContext.has('PushManager') &&
      globalContext.has('Notification') &&
      web.window.navigator.has('serviceWorker');

  static bool get denied => supported && web.Notification.permission == 'denied';

  /// Asks for permission and subscribes. Returns null if refused/unsupported.
  static Future<({String endpoint, String p256dh, String auth})?> subscribe() async {
    if (!supported) return null;
    final perm = (await web.Notification.requestPermission().toDart).toDart;
    if (perm != 'granted') return null;
    final container = web.window.navigator.serviceWorker;
    await container.register('/push_sw.js'.toJS).toDart;
    final reg = await container.ready.toDart;
    final existing = await reg.pushManager.getSubscription().toDart;
    final sub = existing ??
        await reg.pushManager
            .subscribe(web.PushSubscriptionOptionsInit(
              userVisibleOnly: true,
              applicationServerKey: _b64urlDecode(Env.vapidPublicKey).toJS,
            ))
            .toDart;
    String key(String name) => _b64url(sub.getKey(name)!.toDart.asUint8List());
    return (endpoint: sub.endpoint, p256dh: key('p256dh'), auth: key('auth'));
  }

  static String _b64url(Uint8List b) => base64Url.encode(b).replaceAll('=', '');
  static Uint8List _b64urlDecode(String s) => base64Url.decode(base64Url.normalize(s));
}
