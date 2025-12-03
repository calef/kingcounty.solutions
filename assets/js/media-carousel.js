(function() {
  function initMediaCarousel(carousel) {
    const track = carousel.querySelector('[data-carousel-track]');
    if (!track) return;
    const slides = Array.from(track.querySelectorAll('[data-carousel-slide]'));
    if (!slides.length) return;

    const prevButton = carousel.querySelector('[data-carousel-prev]');
    const nextButton = carousel.querySelector('[data-carousel-next]');
    const statusEl = carousel.querySelector('[data-carousel-status]');
    const flagButton = carousel.querySelector('[data-carousel-flag]');
    const dotButtons = Array.from(carousel.querySelectorAll('[data-carousel-dot]'));
    const slideCount = slides.length;
    let activeIndex = 0;
    const flagData = slides.map(function(slide) {
      const dataEl = slide.querySelector('.flag-issue-data');
      if (!dataEl) {
        return null;
      }
      return {
        url: dataEl.getAttribute('data-flag-url'),
        label: dataEl.getAttribute('data-flag-label')
      };
    });

    function updateUi() {
      if (statusEl) {
        statusEl.textContent = 'Image ' + (activeIndex + 1) + ' of ' + slideCount;
      }
      updateFlagLink(activeIndex);
      if (prevButton) {
        prevButton.disabled = activeIndex === 0;
      }
      if (nextButton) {
        nextButton.disabled = activeIndex === slideCount - 1;
      }
      dotButtons.forEach(function(dot, idx) {
        dot.classList.toggle('is-active', idx === activeIndex);
        dot.setAttribute('aria-current', idx === activeIndex ? 'true' : 'false');
      });
    }

    function updateFlagLink(index) {
      if (!flagButton) {
        return;
      }
      const data = flagData[index];
      if (!data || !data.url) {
        flagButton.href = '#';
        flagButton.setAttribute('aria-label', 'Flag this image for removal');
        flagButton.classList.add('is-hidden');
        return;
      }
      flagButton.classList.remove('is-hidden');
      flagButton.href = data.url;
      const label = data.label || 'Flag this image for removal';
      flagButton.setAttribute('aria-label', label);
      const sr = flagButton.querySelector('.sr-only');
      if (sr) {
        sr.textContent = label;
      }
    }

    function scrollToIndex(index, instant) {
      const clamped = Math.max(0, Math.min(slideCount - 1, index));
      const left = clamped * track.clientWidth;
      if (typeof track.scrollTo === 'function') {
        track.scrollTo({ left: left, behavior: instant ? 'auto' : 'smooth' });
      } else {
        track.scrollLeft = left;
      }
      activeIndex = clamped;
      updateUi();
    }

    let scrolling = false;
    function onScroll() {
      if (scrolling) return;
      scrolling = true;
      window.requestAnimationFrame(function() {
        scrolling = false;
        const width = track.clientWidth || 1;
        const nextIndex = Math.round(track.scrollLeft / width);
        if (nextIndex !== activeIndex) {
          activeIndex = Math.max(0, Math.min(slideCount - 1, nextIndex));
          updateUi();
        }
      });
    }

    if (prevButton) {
      prevButton.addEventListener('click', function() {
        scrollToIndex(activeIndex - 1);
      });
    }
    if (nextButton) {
      nextButton.addEventListener('click', function() {
        scrollToIndex(activeIndex + 1);
      });
    }
    dotButtons.forEach(function(dot) {
      const target = parseInt(dot.getAttribute('data-carousel-target'), 10);
      if (!Number.isNaN(target)) {
        dot.addEventListener('click', function() {
          scrollToIndex(target);
        });
      }
    });

    track.addEventListener('scroll', onScroll);
    window.addEventListener('resize', function() {
      scrollToIndex(activeIndex, true);
    });

    updateUi();
    carousel.classList.add('is-ready');
  }

  function initAllCarousels() {
    document.querySelectorAll('[data-media-carousel]').forEach(initMediaCarousel);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAllCarousels);
  } else {
    initAllCarousels();
  }
})();
