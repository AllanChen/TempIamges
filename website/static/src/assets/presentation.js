/* Theme and viewport-aware playback for the Shizuka website. */
(function () {
  'use strict';
  var root = document.documentElement;
  var lang = root.getAttribute('data-lang') || 'en';
  // Save only an explicit menu choice, so later visits to / use it before IP
  // geolocation. This cookie contains a language code, not the visitor's IP.
  document.querySelectorAll('.lang-option').forEach(function (link) {
    link.addEventListener('click', function () {
      var choice = (link.getAttribute('hreflang') || '').split('-')[0];
      if (['zh', 'en', 'ja', 'de'].indexOf(choice) === -1) return;
      try {
        document.cookie = 'glance.language=' + choice + '; Path=/; Max-Age=31536000; SameSite=Lax; Secure';
      } catch (_) { /* The selected language URL still works if cookies are blocked. */ }
    });
  });
  var light = window.matchMedia('(prefers-color-scheme: light)');
  var small = window.matchMedia('(max-width: 760px)');
  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)');
  var themeButton = document.querySelector('.theme-toggle');
  var saved;
  try { saved = localStorage.getItem('glance.theme'); } catch (_) {}
  var themeLabels = {
    zh: ['切换浅色', '切换深色'], en: ['Switch to light', 'Switch to dark'],
    ja: ['ライトに切り替え', 'ダークに切り替え'], de: ['Helles Design', 'Dunkles Design']
  }[lang];
  function setTheme(theme) {
    root.setAttribute('data-theme', theme);
    document.querySelector('meta[name="theme-color"]').content = theme === 'light' ? '#faf9f5' : '#151514';
    if (themeButton) {
      themeButton.setAttribute('aria-pressed', String(theme === 'light'));
      themeButton.setAttribute('aria-label', themeLabels[theme === 'light' ? 1 : 0]);
      themeButton.title = themeButton.getAttribute('aria-label');
    }
    document.dispatchEvent(new Event('glance:theme'));
  }
  if (themeButton) themeButton.addEventListener('click', function () {
    saved = root.getAttribute('data-theme') === 'light' ? 'dark' : 'light';
    try { localStorage.setItem('glance.theme', saved); } catch (_) {}
    setTheme(saved);
  });
  function listen(query, callback) {
    if (query.addEventListener) query.addEventListener('change', callback);
    else query.addListener(callback);
  }
  listen(light, function () { if (saved !== 'light' && saved !== 'dark') setTheme(light.matches ? 'light' : 'dark'); });
  window.addEventListener('storage', function (e) {
    if (e.key === 'glance.theme' || e.key === null) {
      saved = e.newValue;
      setTheme(saved === 'dark' || saved === 'light' ? saved : light.matches ? 'light' : 'dark');
    }
  });
  setTheme(root.getAttribute('data-theme') || 'dark');
  document.querySelectorAll('.mobile-nav').forEach(function (menu) {
    menu.addEventListener('click', function (e) { if (e.target.closest('a')) menu.open = false; });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') menu.open = false; });
    document.addEventListener('click', function (e) { if (!menu.contains(e.target)) menu.open = false; });
  });
  var promos = [];
  document.querySelectorAll('[data-promo]').forEach(function (figure) {
    var video = figure.querySelector('video');
    var button = figure.querySelector('button');
    var state = {figure: figure, video: video, visible: false, manual: null, requested: false};
    promos.push(state);
    // Native controls and a complete video source remain available without JS.
    video.controls = false;
    video.muted = true;
    button.hidden = false;
    function update() {
      var playing = !video.paused;
      figure.classList.toggle('is-playing', playing);
      button.setAttribute('aria-pressed', String(playing));
      var title = button.getAttribute(playing ? 'data-pause' : 'data-play');
      button.setAttribute('aria-label', title);
      button.querySelector('.control-label').textContent = title;
    }
    video.addEventListener('play', update);
    video.addEventListener('pause', update);
    video.addEventListener('error', function () { video.controls = true; button.hidden = true; });
    button.addEventListener('click', function () {
      state.manual = video.paused;
      if (state.manual) { state.visible = true; play(state); } else video.pause();
    });
    state.sync = function () {
      if (!figure.hasAttribute('data-dark-desktop')) return;
      var base = figure.getAttribute('data-' + root.getAttribute('data-theme') + '-' + (small.matches ? 'mobile' : 'desktop'));
      if (video.getAttribute('src') === base + '.mp4') return;
      var position = video.currentTime;
      video.pause();
      video.poster = base + '-poster.jpg';
      video.src = base + '.mp4';
      if (position) video.addEventListener('loadedmetadata', function restore() {
        video.currentTime = Math.min(position, video.duration || position);
      }, {once: true});
      state.requested = false;
      if (state.visible) play(state);
    };
    state.sync();
  });
  function play(state) {
    if (document.hidden || !state.visible || state.manual === false || (reduced.matches && state.manual !== true)) {
      state.video.pause(); return;
    }
    var attempt = state.video.play();
    if (attempt && attempt.catch) attempt.catch(function () { /* Play button stays available. */ });
  }
  if ('IntersectionObserver' in window) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        var state = promos.find(function (s) { return s.figure === entry.target; });
        state.visible = entry.isIntersecting;
        play(state);
      });
    }, {threshold: 0.25});
    promos.forEach(function (s) { observer.observe(s.figure); });
  }
  document.addEventListener('visibilitychange', function () { promos.forEach(play); });
  document.addEventListener('glance:theme', function () { promos.forEach(function (s) { s.sync(); }); });
  listen(small, function () { promos.forEach(function (s) { s.sync(); }); });
  listen(reduced, function () { promos.forEach(play); });

  // The homepage starts with the public catalog snapshot, then refreshes prices.
  var homePricing = document.getElementById('home-pricing');
  if (homePricing) {
    var currency = {zh:'CNY', en:'USD', ja:'JPY', de:'EUR'}[lang];
    var locale = {zh:'zh-CN', en:'en-US', ja:'ja-JP', de:'de-DE'}[lang];
    function money(amount) { return new Intl.NumberFormat(locale, {style:'currency',currency:currency,maximumFractionDigits:currency==='JPY'?0:2}).format(amount/(currency==='JPY'?1:100)); }
    function fill(pricing) {
      var available = pricing.enabled && pricing.paymentsAvailable;
      var personal = (pricing.proTiers || []).find(function (t) { return t.id === 'personal' && t.enabled; });
      var pack = (pricing.packs || []).find(function (t) { return t.id === 'small' && t.enabled; });
      [null,personal,pack].forEach(function (item,i) {
        var node = document.querySelector('[data-home-price="'+i+'"]');
        var amount = i === 0 ? 0 : available && item && item[currency] ? item[currency].amount : null;
        if (amount !== null) node.textContent = money(amount);
        else node.textContent = {zh:'暂未开放',en:'Not available',ja:'現在利用できません',de:'Derzeit nicht verfügbar'}[lang];
      });
    }
    fill(JSON.parse(homePricing.textContent));
    fetch('https://api.glancepreview.com/api/v2/pricing', {headers:{Accept:'application/json'}})
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (body) { if (body.result) fill(body.result); }).catch(function () {});
  }
})();
