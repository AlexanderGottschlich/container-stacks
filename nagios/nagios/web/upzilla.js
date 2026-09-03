/* Visual-only enhancements for the elastic2ls Nagios light skin. */
(function () {
  'use strict';

  function normalizedText(el) {
    return (el.textContent || '').replace(/\s+/g, ' ').trim().toUpperCase();
  }

  function badgeClass(state) {
    switch (state) {
      case 'OK': return 'elastic2ls-status-ok';
      case 'UP': return 'elastic2ls-status-up';
      case 'WARNING': return 'elastic2ls-status-warning';
      case 'CRITICAL': return 'elastic2ls-status-critical';
      case 'DOWN': return 'elastic2ls-status-down';
      case 'UNREACHABLE': return 'elastic2ls-status-unreachable';
      case 'UNKNOWN': return 'elastic2ls-status-unknown';
      case 'PENDING': return 'elastic2ls-status-pending';
      default: return '';
    }
  }

  function decorateStatusCells() {
    var allowed = ['OK', 'UP', 'WARNING', 'CRITICAL', 'DOWN', 'UNREACHABLE', 'UNKNOWN', 'PENDING'];
    var cells = document.querySelectorAll('td, th');

    cells.forEach(function (cell) {
      if (cell.querySelector('.elastic2ls-status-badge')) return;

      var state = normalizedText(cell);
      if (allowed.indexOf(state) === -1) return;

      var span = document.createElement('span');
      span.className = 'elastic2ls-status-badge ' + badgeClass(state);
      span.textContent = state;

      cell.textContent = '';
      cell.appendChild(span);
    });
  }

  function decorateServiceTable() {
    var tables = document.querySelectorAll('table');
    tables.forEach(function (table) {
      var headers = Array.prototype.map.call(table.querySelectorAll('th'), function (th) {
        return normalizedText(th);
      });
      if (!headers.length) return;

      var hostIndex = headers.indexOf('HOST');
      var outputIndex = headers.indexOf('STATUS INFORMATION');
      if (hostIndex < 0 && outputIndex < 0) return;

      table.classList.add('elastic2ls-monitor-table');
      Array.prototype.forEach.call(table.querySelectorAll('tr'), function (row) {
        var tds = row.querySelectorAll('td');
        if (hostIndex >= 0 && tds[hostIndex]) tds[hostIndex].classList.add('elastic2ls-host-cell');
        if (outputIndex >= 0 && tds[outputIndex]) tds[outputIndex].classList.add('elastic2ls-output-cell');
      });
    });
  }

  function addTopbar() {
    if (!document.body || document.body.classList.contains('navbar')) return;
    if (document.querySelector('.elastic2ls-topbar')) return;

    var title = document.title || 'Nagios Core';
    var heading = document.querySelector('.statusTitle, .dataTitle, .reportTitle, h1, h2');
    if (heading && heading.textContent.trim()) title = heading.textContent.trim();

    var bar = document.createElement('div');
    bar.className = 'elastic2ls-topbar';

    var left = document.createElement('div');
    left.className = 'elastic2ls-topbar__left';

    var mark = document.createElement('span');
    mark.className = 'elastic2ls-topbar__mark';
    mark.textContent = 'N';

    var titleEl = document.createElement('span');
    titleEl.className = 'elastic2ls-topbar__title';
    titleEl.textContent = title;

    var meta = document.createElement('span');
    meta.className = 'elastic2ls-topbar__meta';
    meta.textContent = 'elastic2ls monitoring';

    left.appendChild(mark);
    left.appendChild(titleEl);
    bar.appendChild(left);
    bar.appendChild(meta);
    document.body.insertBefore(bar, document.body.firstChild);
  }

  function init() {
    if (!document.body) return;
    document.body.classList.add('elastic2ls-modern-ui');
    addTopbar();
    decorateStatusCells();
    decorateServiceTable();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
