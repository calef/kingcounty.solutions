(function() {
  function initMediaCarousel(carousel) {
    const track = carousel.querySelector('[data-carousel-track]');
    if (!track) return;
    const slides = Array.from(track.querySelectorAll('[data-carousel-slide]'));
    if (!slides.length) return;

    const prevButton = carousel.querySelector('[data-carousel-prev]');
    const nextButton = carousel.querySelector('[data-carousel-next]');
    const statusEl = carousel.querySelector('[data-carousel-status]');
    const dotButtons = Array.from(carousel.querySelectorAll('[data-carousel-dot]'));
    const slideCount = slides.length;
    let activeIndex = 0;

    function updateUi() {
      if (statusEl) {
        statusEl.textContent = 'Image ' + (activeIndex + 1) + ' of ' + slideCount;
      }
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
