/* Hand-drawn inline SVG icons that resemble the SF Symbols the Nubrix UI uses (no SF Symbols glyphs copied),
   plus the NotchShape clip-path helper. A few shapes follow Lucide (ISC license): gear, webcam.
   Usage: <i data-icon="house" data-size="15"></i>  (color comes from CSS color) */
(function () {
  var uid = 0;
  var STROKE = 'fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"';

  // Filled disc with a cut-out glyph (mask), like checkmark.circle.fill
  function disc(cut, dot) {
    var id = 'm' + (++uid);
    return '<mask id="' + id + '"><rect width="24" height="24" fill="#fff"/>' +
      '<path d="' + cut + '" stroke="#000" stroke-width="2.2" fill="none" stroke-linecap="round" stroke-linejoin="round"/>' +
      (dot ? '<circle cx="12" cy="16.9" r="1.3" fill="#000"/>' : '') +
      '</mask><circle cx="12" cy="12" r="10.2" fill="currentColor" mask="url(#' + id + ')"/>';
  }

  var ICONS = {
    house: function () {
      return '<path d="M12 3.1 2.9 11.2a.9.9 0 0 0 .6 1.6H5V20a1 1 0 0 0 1 1h3.6v-5.6h4.8V21H18a1 1 0 0 0 1-1v-7.2h1.5a.9.9 0 0 0 .6-1.6z" fill="currentColor"/>';
    },
    tray: function () {
      return '<path fill-rule="evenodd" fill="currentColor" d="M3 13.2 5.6 6.3C6 5.2 7 4.5 8.1 4.5h7.8c1.1 0 2.1.7 2.5 1.8L21 13.2V18c0 1.1-.9 2-2 2H5c-1.1 0-2-.9-2-2zM5.9 13.2v.9h3.1l1 2.1h4l1-2.1h3.1v-.9h-3.7l-1 2.1h-2.8l-1-2.1z"/>';
    },
    stack: function () {
      return '<path d="M12 3.2 21 8l-9 4.8L3 8z" fill="currentColor" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/>' +
        '<path d="M3.4 12 12 16.6 20.6 12M3.4 16 12 20.6 20.6 16" ' + STROKE + ' stroke-width="1.9"/>';
    },
    sparkle: function () {
      return '<path d="M12 2.4c.9 5.6 4 8.7 9.6 9.6-5.6.9-8.7 4-9.6 9.6-.9-5.6-4-8.7-9.6-9.6 5.6-.9 8.7-4 9.6-9.6z" fill="currentColor" stroke="currentColor" stroke-width="1" stroke-linejoin="round"/>';
    },
    terminal: function () { // terminal.fill
      var id = 'm' + (++uid);
      return '<mask id="' + id + '"><rect width="24" height="24" fill="#fff"/>' +
        '<path d="M7.2 9.4l3 2.6-3 2.6M12.6 15h4.4" stroke="#000" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></mask>' +
        '<rect x="2.4" y="3.6" width="19.2" height="16.8" rx="4" fill="currentColor" mask="url(#' + id + ')"/>';
    },
    terminalLine: function () { // small outline terminal used by the source chip fallback
      return '<rect x="3" y="4.5" width="18" height="15" rx="3.5" ' + STROKE + ' stroke-width="2"/>' +
        '<path d="M7.5 10l3 2.4-3 2.4M13 15h3.8" ' + STROKE + ' stroke-width="2"/>';
    },
    macwindow: function () {
      return '<rect x="3" y="4.5" width="18" height="15" rx="3.2" ' + STROKE + ' stroke-width="2"/>' +
        '<path d="M3 9.5h18" ' + STROKE + ' stroke-width="2"/>';
    },
    camera: function () { // web.camera (Lucide webcam)
      return '<circle cx="12" cy="10" r="8" ' + STROKE + ' stroke-width="1.9"/>' +
        '<circle cx="12" cy="10" r="3" ' + STROKE + ' stroke-width="1.9"/>' +
        '<path d="M7 22h10M12 18v4" ' + STROKE + ' stroke-width="1.9"/>';
    },
    gear: function () { // Lucide settings
      return '<path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" ' + STROKE + ' stroke-width="1.8"/>' +
        '<circle cx="12" cy="12" r="3" ' + STROKE + ' stroke-width="1.8"/>';
    },
    play: function () {
      return '<path d="M7.2 4.6v14.8c0 .8.9 1.3 1.6.9l11.6-7.4c.6-.4.6-1.3 0-1.7L8.8 3.7c-.7-.4-1.6.1-1.6.9z" fill="currentColor"/>';
    },
    pause: function () {
      return '<rect x="5.2" y="4" width="4.8" height="16" rx="1.6" fill="currentColor"/><rect x="14" y="4" width="4.8" height="16" rx="1.6" fill="currentColor"/>';
    },
    backward: function () {
      var t = 'fill="currentColor" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"';
      return '<path d="M11.4 6.6v10.8L3.6 12z" ' + t + '/><path d="M20.4 6.6v10.8L12.6 12z" ' + t + '/>';
    },
    forward: function () {
      var t = 'fill="currentColor" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"';
      return '<path d="M12.6 6.6v10.8L20.4 12z" ' + t + '/><path d="M3.6 6.6v10.8L11.4 12z" ' + t + '/>';
    },
    checkCircle: function () { return disc('M7.6 12.4l3.2 3.2 6-6.6'); },
    xCircle: function () { return disc('M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8'); },
    alertCircle: function () { return disc('M12 6.8v6', true); },
    moonZ: function () {
      return '<path d="M10.6 5.2a7.6 7.6 0 1 0 8.2 10.6A8.6 8.6 0 0 1 10.6 5.2z" fill="currentColor"/>' +
        '<path d="M14.6 3.4h3.4l-3.4 3.8h3.4M19.4 8.4h2.4l-2.4 2.6h2.4" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" stroke-linejoin="round"/>';
    },
    warn: function () {
      var id = 'm' + (++uid);
      return '<mask id="' + id + '"><rect width="24" height="24" fill="#fff"/><path d="M12 9.4v5" stroke="#000" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="17.7" r="1.3" fill="#000"/></mask>' +
        '<path d="M12 3 2.4 19.4c-.5.9.1 2 1.2 2h16.8c1.1 0 1.7-1.1 1.2-2z" fill="currentColor" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" mask="url(#' + id + ')"/>';
    },
    clock: function () {
      return '<circle cx="12" cy="12" r="9" ' + STROKE + ' stroke-width="2"/><path d="M12 7v5l3.2 2" ' + STROKE + ' stroke-width="2"/>';
    },
    info: function () {
      return '<circle cx="12" cy="12" r="9.2" ' + STROKE + ' stroke-width="1.9"/><path d="M12 11v5.2" ' + STROKE + ' stroke-width="2"/><circle cx="12" cy="7.7" r="1.2" fill="currentColor"/>';
    },
    expand: function () {
      return '<path d="M14 4h6v6M20 4l-7 7M10 20H4v-6M4 20l7-7" ' + STROKE + ' stroke-width="2.4"/>';
    },
    note: function () {
      return '<path d="M9 17.5V6.2l9-1.8v11.3" ' + STROKE + ' stroke-width="2"/><circle cx="6.8" cy="17.6" r="2.4" fill="currentColor"/><circle cx="15.8" cy="15.8" r="2.4" fill="currentColor"/>';
    },
    wifi: function () {
      return '<path d="M2.5 9.2a14 14 0 0 1 19 0M5.8 12.6a9.4 9.4 0 0 1 12.4 0M9 16a4.8 4.8 0 0 1 6 0" ' + STROKE + ' stroke-width="2"/><circle cx="12" cy="19" r="1.4" fill="currentColor"/>';
    },
    search: function () {
      return '<circle cx="10.5" cy="10.5" r="6.3" ' + STROKE + ' stroke-width="2.1"/><path d="M15.4 15.4 20.5 20.5" ' + STROKE + ' stroke-width="2.1"/>';
    },
    switches: function () {
      return '<path d="M4 8h16M4 16h16" ' + STROKE + ' stroke-width="2"/><circle cx="9" cy="8" r="2.6" fill="#000" stroke="currentColor" stroke-width="2"/><circle cx="15" cy="16" r="2.6" fill="#000" stroke="currentColor" stroke-width="2"/>';
    }
  };

  // Orange spinner of AgentAnimatedGlyphView (.spinner): stroke 0.15..0.85 of a circle, round caps.
  function spinner(size, rot) {
    var lw = Math.max(1.5, size / 7), inset = lw / 2 + size * 0.08, r = size / 2 - inset;
    var c = 2 * Math.PI * r;
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 ' + size + ' ' + size + '">' +
      '<g transform="rotate(' + (rot || 40) + ' ' + size / 2 + ' ' + size / 2 + ')">' +
      '<circle cx="' + size / 2 + '" cy="' + size / 2 + '" r="' + r + '" fill="none" stroke="currentColor" stroke-width="' + lw + '" stroke-linecap="round" ' +
      'stroke-dasharray="' + (c * 0.7) + ' ' + (c * 0.3) + '" transform="rotate(54 ' + size / 2 + ' ' + size / 2 + ')"/></g></svg>';
  }

  function svg(name, size) {
    var f = ICONS[name];
    if (!f) return '';
    return '<svg width="' + size + '" height="' + size + '" viewBox="0 0 24 24">' + f() + '</svg>';
  }

  function hydrate(root) {
    var nodes = (root || document).querySelectorAll('[data-icon]');
    Array.prototype.forEach.call(nodes, function (el) {
      var name = el.getAttribute('data-icon'), size = parseFloat(el.getAttribute('data-size') || '16');
      var html = name === 'spinner' ? spinner(size, parseFloat(el.getAttribute('data-rot') || '40')) : svg(name, size);
      el.innerHTML = html;
      el.style.display = 'inline-flex';
      el.style.width = size + 'px';
      el.style.height = size + 'px';
    });
  }

  // NotchShape.swift: quad curves into the straight sides, concave top corners.
  function notchPath(w, h, T, B) {
    return 'M0,0 Q' + T + ',0 ' + T + ',' + T + ' L' + T + ',' + (h - B) +
      ' Q' + T + ',' + h + ' ' + (T + B) + ',' + h + ' L' + (w - T - B) + ',' + h +
      ' Q' + (w - T) + ',' + h + ' ' + (w - T) + ',' + (h - B) + ' L' + (w - T) + ',' + T +
      ' Q' + (w - T) + ',0 ' + w + ',0 Z';
  }
  function shapeNotches() {
    Array.prototype.forEach.call(document.querySelectorAll('.notch'), function (n) {
      var body = n.querySelector('.notch-body');
      var closed = n.classList.contains('closed');
      var T = closed ? 6 : 19, B = closed ? 14 : 24;
      var w = n.offsetWidth, h = n.offsetHeight;
      body.style.clipPath = "path('" + notchPath(w, h, T, B) + "')";
    });
  }

  window.Nubrix = { icon: svg, spinner: spinner, hydrate: hydrate, shapeNotches: shapeNotches };

  function run() { hydrate(); shapeNotches(); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', run); else run();
  window.addEventListener('load', shapeNotches);
})();
