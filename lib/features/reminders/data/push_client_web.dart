import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../domain/push_client.dart';

PushClient createPushClient() => WebPushClient();

/// Web Push pelo service worker da app (web/push_worker.js).
final class WebPushClient implements PushClient {
  WebPushClient() {
    if (_hasServiceWorker) {
      web.window.navigator.serviceWorker.addEventListener(
        'message',
        ((web.MessageEvent e) {
          final data = e.data.dartify();
          if (data is Map && data['type'] == 'fio-open') {
            final path = data['path'];
            if (path is String && path.startsWith('/')) _opened.add(path);
          }
        }).toJS,
      );
    }
  }

  final _opened = StreamController<String>.broadcast();

  static bool get _hasServiceWorker =>
      (web.window.navigator as JSObject).has('serviceWorker');

  static bool get _hasPush =>
      _hasServiceWorker &&
      globalContext.has('PushManager') &&
      globalContext.has('Notification');

  static bool get _isIos {
    final ua = web.window.navigator.userAgent;
    // O iPad em modo "computador" diz que é um Mac, mas tem ecrã tátil.
    return RegExp('iPhone|iPad|iPod').hasMatch(ua) ||
        (ua.contains('Macintosh') && web.window.navigator.maxTouchPoints > 1);
  }

  @override
  PushSupport get support => _hasPush
      ? PushSupport.available
      : _isIos
      ? PushSupport.needsInstall
      : PushSupport.unsupported;

  @override
  PushPermission get permission {
    if (!_hasPush) return PushPermission.denied;
    return _permissionOf(web.Notification.permission);
  }

  static PushPermission _permissionOf(String value) => switch (value) {
    'granted' => PushPermission.granted,
    'denied' => PushPermission.denied,
    _ => PushPermission.prompt,
  };

  @override
  String get timeZone {
    try {
      final intl = globalContext.getProperty<JSObject>('Intl'.toJS);
      final format = intl.callMethod<JSObject>('DateTimeFormat'.toJS);
      final options = format.callMethod<JSObject>('resolvedOptions'.toJS);
      return options.getProperty<JSString>('timeZone'.toJS).toDart;
    } on Object {
      return 'Europe/Lisbon';
    }
  }

  @override
  Future<PushPermission> requestPermission() async {
    if (!_hasPush) return PushPermission.denied;
    final result = await web.Notification.requestPermission().toDart;
    return _permissionOf(result.toDart);
  }

  Future<web.ServiceWorkerRegistration> _registration() async {
    final container = web.window.navigator.serviceWorker;
    // O carregador do Flutter regista-o; se ainda não o fez, regista-se aqui
    // (o mesmo ficheiro).
    final existing = await container.getRegistration().toDart;
    if (existing == null) {
      await container.register('flutter_service_worker.js'.toJS).toDart;
    }
    return container.ready.toDart;
  }

  static PushSubscriptionKeys? _keysOf(web.PushSubscription? s) {
    if (s == null) return null;
    final p256dh = s.getKey('p256dh');
    final auth = s.getKey('auth');
    if (p256dh == null || auth == null) return null;
    String encode(JSArrayBuffer b) =>
        base64Url.encode(b.toDart.asUint8List()).replaceAll('=', '');
    return PushSubscriptionKeys(
      endpoint: s.endpoint,
      p256dh: encode(p256dh),
      auth: encode(auth),
    );
  }

  @override
  Future<PushSubscriptionKeys?> current() async {
    if (!_hasPush) return null;
    final reg = await _registration();
    return _keysOf(await reg.pushManager.getSubscription().toDart);
  }

  @override
  Future<PushSubscriptionKeys?> subscribe(String serverPublicKey) async {
    if (!_hasPush) return null;
    final reg = await _registration();
    final existing = await reg.pushManager.getSubscription().toDart;
    if (existing != null) return _keysOf(existing);
    final key = base64Url.decode(base64Url.normalize(serverPublicKey));
    final sub = await reg.pushManager
        .subscribe(
          web.PushSubscriptionOptionsInit(
            userVisibleOnly: true,
            applicationServerKey: Uint8List.fromList(key).toJS,
          ),
        )
        .toDart;
    return _keysOf(sub);
  }

  @override
  Future<void> unsubscribe() async {
    if (!_hasPush) return;
    final reg = await _registration();
    final sub = await reg.pushManager.getSubscription().toDart;
    if (sub != null) await sub.unsubscribe().toDart;
  }

  @override
  Stream<String> get openedPaths => _opened.stream;
}
