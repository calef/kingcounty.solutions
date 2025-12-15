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
      const eventEnd = new Date(eventEndStr);
      
      if (!isNaN(eventEnd.getTime()) && eventEnd < now) {
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
