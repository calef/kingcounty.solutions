/**
 * Grays out events that have already ended
 */
(function() {
  'use strict';

  function grayOutPastEvents() {
    const eventItems = document.querySelectorAll('.event-item[data-event-end]');
    const now = new Date();

    eventItems.forEach(function(eventItem) {
      const eventEndStr = eventItem.getAttribute('data-event-end');
      if (!eventEndStr) return;

      const eventEnd = new Date(eventEndStr);
      
      if (eventEnd < now) {
        eventItem.classList.add('event-past');
      }
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', grayOutPastEvents);
  } else {
    grayOutPastEvents();
  }
})();
