// Service worker da PWA (docs/features/lembretes.md). A build copia este
// ficheiro por cima do flutter_service_worker.js do Flutter (que hoje só se
// desregista): é o único service worker da app. Não guarda nada em cache;
// só mostra os lembretes e abre a app no sítio certo ao tocar.
'use strict';

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch (_) {
    data = { body: event.data ? event.data.text() : '' };
  }
  event.waitUntil(
    self.registration.showNotification(data.title || 'fio', {
      body: data.body || '',
      icon: 'icons/Icon-192.png',
      badge: 'icons/Icon-192.png',
      tag: data.tag,
      data: { url: typeof data.url === 'string' ? data.url : '/' },
    }),
  );
});

// A app usa URLs com # (go_router na Web): /vesti?... -> /#/vesti?...
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const path = (event.notification.data && event.notification.data.url) || '/';
  const target = new URL('#' + path, self.registration.scope).href;
  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of windows) {
        if ('focus' in client) {
          await client.focus();
          // A app aberta muda de ecrã sem recarregar.
          client.postMessage({ type: 'fio-open', path });
          return;
        }
      }
      await self.clients.openWindow(target);
    })(),
  );
});
