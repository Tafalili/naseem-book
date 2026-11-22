// Web Push for order status updates (registered from the order page).
self.addEventListener('push', (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_) {}
  const title = data.title || 'كتاب نسيم';
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || '',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    lang: 'ar',
    dir: 'rtl',
    data: { url: data.url || './' },
  }));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url || './', self.registration.scope).href;
  event.waitUntil((async () => {
    const all = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of all) {
      if (c.url === url && 'focus' in c) return c.focus();
    }
    return clients.openWindow(url);
  })());
});
