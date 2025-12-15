(function() {
  /**
   * Redirects /events/ links to /events/YYYY-MM-DD/ based on current date
   * This ensures events are always relevant even if the site hasn't been rebuilt
   */
  
  // Pattern to match /events/ URLs (with or without trailing slash)
  const EVENTS_ROOT_PATTERN = /^(https?:\/\/[^/]+)?\/events\/?$/;

  function formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }

  function getCurrentDatePath() {
    const today = new Date();
    const dateStr = formatDate(today);
    return `/events/${dateStr}/`;
  }

  function handleEventsLinkClick(event) {
    const target = event.target.closest('a');
    if (!target) return;

    const href = target.getAttribute('href');
    if (!href) return;
    
    // Only redirect if link points exactly to /events/ (with or without trailing slash)
    if (EVENTS_ROOT_PATTERN.test(href)) {
      event.preventDefault();
      const currentDatePath = getCurrentDatePath();
      window.location.replace(currentDatePath);
    }
  }

  // Attach click handler to document to catch all events links
  document.addEventListener('click', handleEventsLinkClick);
})();
