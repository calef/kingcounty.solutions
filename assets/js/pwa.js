---
layout: null
---
'use strict';

(function () {
  const SERVICE_WORKER_PATH = '{{ "/sw.js" | relative_url }}';
  const STORAGE_KEY = 'kcsPwaPromptDismissed';
  const siteTitle = '{{ site.title | escape }}';

  const ua = window.navigator.userAgent.toLowerCase();
  const isIos = /iphone|ipad|ipod/.test(ua) && !/crios|fxios|firefox/.test(ua);
  const isAndroid = /android/.test(ua);

  let deferredPrompt;
  let bannerElement;

  function isStandalone() {
    return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone;
  }

  function hasDismissedPrompt() {
    try {
      return window.localStorage.getItem(STORAGE_KEY) === 'true';
    } catch (error) {
      return false;
    }
  }

  function setPromptDismissed() {
    try {
      window.localStorage.setItem(STORAGE_KEY, 'true');
    } catch (error) {
      // no-op if storage is unavailable
    }
  }

  function removeBanner() {
    if (bannerElement && bannerElement.parentNode) {
      bannerElement.parentNode.removeChild(bannerElement);
    }
    bannerElement = null;
  }

  function renderBanner(platform) {
    if (bannerElement || isStandalone() || hasDismissedPrompt()) {
      return;
    }

    if (!document.body) {
      window.requestAnimationFrame(() => renderBanner(platform));
      return;
    }

    bannerElement = document.createElement('div');
    bannerElement.className = 'pwa-install-banner';
    bannerElement.dataset.platform = platform;

    const title = `Install ${siteTitle}`;
    let message = 'Add this site to your home screen for faster access.';

    if (platform === 'ios') {
      message = 'Tap the share button and then "Add to Home Screen" to keep this site handy.';
    }

    bannerElement.innerHTML = `
      <div class="pwa-install-content">
        <p class="pwa-install-title">${title}</p>
        <p class="pwa-install-message">${message}</p>
        <div class="pwa-install-actions">
          <button type="button" class="pwa-install-primary">
            ${platform === 'android' ? 'Add now' : 'Show me how'}
          </button>
          <button type="button" class="pwa-install-dismiss" aria-label="Dismiss install prompt">&times;</button>
        </div>
        ${platform === 'ios' ? '<p class="pwa-install-steps">1. Tap the share icon. 2. Choose "Add to Home Screen".</p>' : ''}
      </div>
    `;

    const closeButton = bannerElement.querySelector('.pwa-install-dismiss');
    if (closeButton) {
      closeButton.addEventListener('click', () => {
        setPromptDismissed();
        removeBanner();
      });
    }

    const primaryButton = bannerElement.querySelector('.pwa-install-primary');
    if (primaryButton) {
      primaryButton.addEventListener('click', () => handlePrimaryAction(platform));
    }

    document.body.appendChild(bannerElement);
  }

  async function handlePrimaryAction(platform) {
    if (platform === 'android' && deferredPrompt) {
      deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;
      if (outcome === 'accepted') {
        setPromptDismissed();
      }
      deferredPrompt = null;
      removeBanner();
      return;
    }

    if (platform === 'ios') {
      // Keep the banner visible but mark as acknowledged to avoid showing repeatedly.
      setPromptDismissed();
      bannerElement?.classList.add('pwa-install-banner--hint');
    }
  }

  function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) {
      return;
    }

    window.addEventListener('load', () => {
      navigator.serviceWorker
        .register(SERVICE_WORKER_PATH)
        .catch((error) => {
          console.error('Failed to register service worker', error);
        });
    });
  }

  function setupInstallPrompts() {
    if (isStandalone()) {
      setPromptDismissed();
      return;
    }

    if (isAndroid) {
      window.addEventListener('beforeinstallprompt', (event) => {
        event.preventDefault();
        deferredPrompt = event;
        renderBanner('android');
      });
    }

    if (isIos) {
      window.addEventListener('load', () => {
        // Delay slightly to avoid interrupting initial page render.
        setTimeout(() => renderBanner('ios'), 1500);
      });
    }

    window.addEventListener('appinstalled', () => {
      setPromptDismissed();
      removeBanner();
    });
  }

  registerServiceWorker();
  document.addEventListener('DOMContentLoaded', setupInstallPrompts);
})();
