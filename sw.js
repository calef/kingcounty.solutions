---
layout: null
---
'use strict';

const CACHE_PREFIX = 'kcs-pwa-v1';
const CACHE_NAME = `${CACHE_PREFIX}-{{ site.time | date: "%Y%m%d%H%M%S" }}`;
const PRECACHE_URLS = [
  '{{ "/" | relative_url }}',
  '{{ "/index.html" | relative_url }}',
  '{{ "/topics/" | relative_url }}',
  '{{ "/places/" | relative_url }}',
  '{{ "/organizations/" | relative_url }}',
  '{{ "/assets/main.css" | relative_url }}',
  '{{ "/assets/js/pwa.js" | relative_url }}',
  '{{ "/assets/manifest.webmanifest" | relative_url }}',
  '{{ "/assets/kcs_favicon.png" | relative_url }}'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .catch((error) => {
        console.error('Service worker pre-cache failed', error);
      })
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys
            .filter((key) => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
            .map((key) => caches.delete(key))
        )
      )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  if (request.method !== 'GET') {
    return;
  }

  const requestUrl = new URL(request.url);
  const isSameOrigin = requestUrl.origin === self.location.origin;
  const acceptsHtml = request.headers.get('accept')?.includes('text/html');

  if (request.mode === 'navigate' || (isSameOrigin && acceptsHtml)) {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
          return response;
        })
        .catch(() =>
          caches.match(request).then((cachedResponse) => {
            if (cachedResponse) {
              return cachedResponse;
            }
            return caches.match('{{ "/" | relative_url }}');
          })
        )
    );
    return;
  }

  if (isSameOrigin) {
    event.respondWith(
      caches.match(request).then((cachedResponse) => {
        if (cachedResponse) {
          return cachedResponse;
        }

        return fetch(request)
          .then((response) => {
            const copy = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, copy));
            return response;
          })
          .catch(() => caches.match('{{ "/assets/main.css" | relative_url }}'));
      })
    );
  }
});
