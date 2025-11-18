(function() {
  const MIN_QUERY = 2;
  const MAX_RESULTS = 20;
  const search = document.querySelector('.site-search');
  if (!search) return;

  const input = search.querySelector('#site-search-input');
  const clearBtn = search.querySelector('#site-search-clear');
  const status = search.querySelector('#site-search-status');
  const list = search.querySelector('#site-search-list');
  const results = search.querySelector('.site-search-results');
  if (!input || !list || !results) return;

  const indexUrl = search.getAttribute('data-search-index') || '/assets/search-index.json';
  let index = [];
  let categoryCounts = {};
  let indexPromise;
  let activeIndex = -1;

  function updateStatus(message) {
    if (status) status.textContent = message || '';
  }

  function setExpanded(expanded) {
    results.hidden = !expanded;
    input.setAttribute('aria-expanded', expanded ? 'true' : 'false');
  }

  function setResultsPosition() {
    if (results.hidden) return;
    const nav = document.querySelector('.site-header .site-nav');
    const rect = nav ? nav.getBoundingClientRect() : input.getBoundingClientRect();
    const width = Math.min(window.innerWidth * 0.75, window.innerWidth - 24);
    const left = (window.innerWidth - width) / 2;
    const top = rect.bottom + window.scrollY + 12;
    results.style.setProperty('--site-search-left', `${left}px`);
    results.style.setProperty('--site-search-top', `${top}px`);
    results.style.setProperty('--site-search-width', `${width}px`);
  }

  function buildIndex(data) {
    categoryCounts = {};
    index = (data || []).map(item => {
      const key = item.category || 'Other';
      categoryCounts[key] = (categoryCounts[key] || 0) + 1;
      const searchText = [item.title, item.description, item.category]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();
      return Object.assign({}, item, { searchText });
    });
  }

  function loadIndex() {
    if (indexPromise) return indexPromise;
    indexPromise = fetch(indexUrl, { credentials: 'same-origin' })
      .then(response => {
        if (!response.ok) throw new Error('Search index unavailable');
        return response.json();
      })
      .then(data => {
        buildIndex(data);
        return index;
      })
      .catch(error => {
        console.error(error);
        updateStatus('Search is unavailable right now.');
        return [];
      });
    return indexPromise;
  }

  function clearHighlight() {
    activeIndex = -1;
    input.removeAttribute('aria-activedescendant');
    Array.from(list.children).forEach(li => li.classList.remove('is-active'));
  }

  function highlightActive() {
    Array.from(list.children).forEach((li, idx) => {
      if (idx === activeIndex) {
        li.classList.add('is-active');
        const link = li.querySelector('a');
        if (link) input.setAttribute('aria-activedescendant', link.id);
      } else {
        li.classList.remove('is-active');
      }
    });
    if (activeIndex < 0) input.removeAttribute('aria-activedescendant');
  }

  function renderResults(items) {
    setExpanded(true);
    setResultsPosition();
    if (!items.length) {
      list.innerHTML = '';
      updateStatus('No matches found.');
      clearHighlight();
      return;
    }

    const limited = items.slice(0, MAX_RESULTS);
    list.innerHTML = limited.map((item, idx) => {
      const meta = item.category ? `<span class="site-search-pill">${item.category}</span>` : '';
      const optionId = `site-search-option-${idx}`;
      return `
        <li data-index="${idx}">
          <div class="site-search-row">
            <a id="${optionId}" href="${item.url}">${item.title}</a>
            ${meta}
          </div>
        </li>
      `;
    }).join('');

    updateStatus('');
    clearHighlight();
  }

  function rankMatches(matches) {
    const grouped = {};
    matches.forEach(item => {
      const key = item.category || 'Other';
      (grouped[key] = grouped[key] || []).push(item);
    });
    Object.keys(grouped).forEach(key => {
      grouped[key].sort((a, b) => a.title.localeCompare(b.title));
    });

    const categoryOrder = Object.keys(grouped).sort((a, b) => {
      const countA = categoryCounts[a] || 0;
      const countB = categoryCounts[b] || 0;
      if (countA !== countB) return countA - countB;
      return a.localeCompare(b);
    });

    const ranked = [];
    while (ranked.length < MAX_RESULTS) {
      let added = false;
      for (const category of categoryOrder) {
        const bucket = grouped[category];
        if (bucket && bucket.length) {
          ranked.push(bucket.shift());
          added = true;
          if (ranked.length >= MAX_RESULTS) break;
        }
      }
      if (!added) break;
    }

    return ranked;
  }

  function handleSearch() {
    const query = input.value.trim();
    clearBtn.hidden = query.length === 0;

    if (query.length < MIN_QUERY) {
      list.innerHTML = '';
      updateStatus('');
      clearHighlight();
      setExpanded(false);
      return;
    }

    loadIndex().then(() => {
      const tokens = input.value.toLowerCase().split(/\s+/).filter(Boolean);
      const matches = index.filter(item => tokens.every(token => item.searchText.includes(token)));
      if (!matches.length) {
        renderResults([]);
        return;
      }
      renderResults(rankMatches(matches));
    });
  }

  function clearResults() {
    input.value = '';
    clearBtn.hidden = true;
    list.innerHTML = '';
    updateStatus('');
    clearHighlight();
    setExpanded(false);
  }

  function moveActive(delta) {
    const total = list.children.length;
    if (!total) return;
    activeIndex = (activeIndex + delta + total) % total;
    highlightActive();
  }

  function visitActive() {
    if (activeIndex < 0) return;
    const li = list.children[activeIndex];
    const link = li ? li.querySelector('a') : null;
    if (link) {
      link.click();
    }
  }

  clearBtn.addEventListener('click', () => {
    clearResults();
    input.focus();
  });
  input.addEventListener('input', handleSearch);
  input.addEventListener('focus', () => {
    if (input.value.trim().length >= MIN_QUERY) handleSearch();
  });

  input.addEventListener('keydown', (event) => {
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault();
      if (results.hidden) handleSearch();
      moveActive(event.key === 'ArrowDown' ? 1 : -1);
    }
    if (event.key === 'Enter') {
      const hasResults = list.children.length > 0 && !results.hidden;
      if (hasResults) {
        event.preventDefault();
        if (activeIndex < 0) activeIndex = 0;
        highlightActive();
        visitActive();
      }
    }
    if (event.key === 'Escape') {
      clearResults();
    }
  });

  document.addEventListener('keydown', (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === 'k') {
      event.preventDefault();
      input.focus();
    }
  });

  document.addEventListener('pointerdown', (event) => {
    if (results.hidden) return;
    if (!search.contains(event.target)) {
      clearHighlight();
      setExpanded(false);
    }
  });

  window.addEventListener('resize', setResultsPosition);
  window.addEventListener('scroll', setResultsPosition, { passive: true });

  loadIndex();
})();
