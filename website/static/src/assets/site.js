// Glance website runtime: localized media, live Widget catalog and live pricing.
(function () {
  var API = 'https://api.glancepreview.com/api/v2';
  var root = document.documentElement;

  // The URL and generated HTML determine language; language links navigate.
  function switchMedia(lang) {
    document.querySelectorAll('img[data-src-en]').forEach(function (img) {
      var src = img.getAttribute('data-src-' + lang);
      if (src && img.getAttribute('src') !== src) img.setAttribute('src', src);
    });
    document.querySelectorAll('video[data-video-en]').forEach(function (video) {
      var src = video.getAttribute('data-video-' + lang);
      if (!src || video.getAttribute('src') === src) return;
      var time = video.currentTime || 0;
      video.poster = video.getAttribute('data-poster-' + lang);
      video.src = src;
      video.load();
      if (time) video.addEventListener('loadedmetadata', function resume() {
        video.removeEventListener('loadedmetadata', resume);
        if (Number.isFinite(video.duration)) video.currentTime = Math.min(time, Math.max(0, video.duration - 0.1));
      });
      video.play().catch(function () {});
    });
  }
  var language = root.getAttribute('data-lang') || 'zh';
  switchMedia(language);

  document.addEventListener('click', function (event) {
    var link = event.target.closest && event.target.closest('a[data-download-cta]');
    if (!link) return;
    var details = {
      page_path: location.pathname,
      page_language: language,
      cta_location: link.getAttribute('data-download-cta'),
      app_version: link.getAttribute('data-app-version')
    };
    if (typeof window.gtag === 'function') window.gtag('event', 'download_click', details);
    else if (Array.isArray(window.dataLayer)) window.dataLayer.push(Object.assign({ event: 'download_click' }, details));
  });

  // Bilingual anchors: #report resolves to #report-zh or #report-en.
  function followHash() {
    var id = decodeURIComponent(location.hash.slice(1));
    if (!id || document.getElementById(id)) return;
    var target = document.getElementById(id + '-' + root.getAttribute('data-lang'));
    if (target) target.scrollIntoView();
  }
  window.addEventListener('hashchange', followHash);
  window.addEventListener('load', followHash);

  function el(tag, cls, text) {
    var node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text != null) node.textContent = text;
    return node;
  }
  function both(tag, cls, zh, en) {
    var node = el(tag, cls, language === 'zh' ? zh : en);
    node.setAttribute('lang', language);
    return node;
  }

  // Live Widget catalog: names, summaries and per-run credit prices come from
  // the same service the app uses, so the site never drifts from Admin.
  function renderWidgets(target, widgets) {
    // Extra languages keep the server-rendered, translated cards.
    if (language !== 'zh' && language !== 'en' && target.children.length) return;
    target.textContent = '';
    var limit = Number(target.getAttribute('data-limit') || 0);
    widgets.filter(function (w) { return w.name && w.name !== 'My Widget'; })
      .slice(0, limit || undefined).forEach(function (w) {
        var en = (w.localizations && w.localizations.en) || {};
        var card = el('article', 'widget');
        var icon = el('div', 'widget-icon');
        if (w.iconURL && /^https:\/\//.test(w.iconURL)) {
          var img = el('img'); img.src = w.iconURL; img.alt = ''; img.loading = 'lazy'; icon.appendChild(img);
        } else icon.textContent = (en.name || w.name).slice(0, 1);
        card.appendChild(icon);
        var body = el('div', 'widget-body');
        var top = el('div', 'widget-top');
        var name = el('h3');
        name.appendChild(both('span', '', w.name, en.name || w.name));
        top.appendChild(name);
        var cost = Number(w.creditCost == null ? 1 : w.creditCost);
        var duration = w.billing && w.billing.mode === 'duration' && Number(w.billing.unitSeconds);
        var price = el('span', 'price' + (cost === 0 ? ' free' : ''));
        price.appendChild(cost === 0 ? both('span', '', '免费', 'Free') : duration ?
          both('span', '', cost + ' 点 / ' + duration + ' 秒', cost + ' credits / ' + duration + ' sec') :
          both('span', '', cost + ' 点 / 次', cost + ' credits / run'));
        top.appendChild(price);
        body.appendChild(top);
        body.appendChild(both('p', '', w.summary || '', en.summary || w.summary || ''));
        var meta = el('div', 'meta');
        var uploads = w.privacy && w.privacy.uploadsMedia;
        meta.appendChild(both('span', '', uploads ? '运行时上传所选媒体到云端处理' : '在 Glance 服务端处理',
          uploads ? 'Uploads the selected media for cloud processing' : 'Processed by Glance servers'));
        body.appendChild(meta);
        card.appendChild(body);
        target.appendChild(card);
      });
    if (!target.children.length) target.appendChild(both('p', 'notice', '暂无可用的 Widget。', 'No Widgets are available right now.'));
  }
  var widgetTargets = document.querySelectorAll('[data-widgets]');
  if (widgetTargets.length) {
    fetch(API + '/widgets?limit=50', { headers: { Accept: 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (body) {
        var widgets = (body.result && body.result.widgets) || [];
        widgetTargets.forEach(function (t) { renderWidgets(t, widgets); });
      })
      .catch(function () {
        widgetTargets.forEach(function (t) {
          if (!t.children.length) {
            t.appendChild(both('p', 'notice', 'Widget 列表暂时无法加载，请稍后刷新。', 'The Widget list could not be loaded. Please refresh in a moment.'));
          }
        });
      });
  }

  // Live pricing. Admin is the single source of truth; the embedded JSON is the
  // last published fallback so the page is complete without the API.
  var fallbackNode = document.getElementById('pricing-fallback');
  if (fallbackNode) {
    var pricing = JSON.parse(fallbackNode.textContent);
    var currency = language === 'zh' ? 'CNY' : 'USD';
    var money = function (cents, cur) {
      if (cents == null) return null;
      var value = cents / (cur === 'JPY' ? 1 : 100);
      var text = value % 1 === 0 ? String(value) : value.toFixed(2);
      return ({CNY:'CN¥',USD:'US$',JPY:'JP¥',EUR:'€',HKD:'HK$'}[cur] || cur + ' ') + text;
    };
    var launchActive = function () {
      return pricing.launchUntil && new Date(pricing.launchUntil) > new Date();
    };
    var tierPrice = function (tier, cur) {
      var launch = launchActive() && tier['launch' + cur] && tier['launch' + cur].amount != null ? tier['launch' + cur].amount : null;
      var regular = tier[cur] && tier[cur].amount;
      return { amount: launch != null ? launch : regular, regular: regular, discounted: launch != null && launch !== regular };
    };
    var fill = function () {
      var cur = currency;
      document.querySelectorAll('[data-zero]').forEach(function (n) { n.textContent = money(0,cur); });
      var purchasesOpen = pricing.enabled && pricing.paymentsAvailable;
      var tiers = purchasesOpen ? (pricing.proTiers || []).filter(function (t) { return t.enabled; }) : [];
      var anyDiscount = false;
      document.querySelectorAll('[data-tiers]').forEach(function (n) {
        n.textContent = '';
        tiers.forEach(function (t) {
          var p = tierPrice(t, cur);
          var row = el('div', 'tier' + (t.recommended ? ' recommended' : ''));
          var head = el('div', 'tier-head');
          head.appendChild(both('b', '', t.name === 'Personal' ? '个人版' : t.id === 'team' ? '多人版' : t.name, t.name));
          head.appendChild(both('span', 'tier-macs', t.id==='team'?'5 人 · 每人 1 台 Mac':t.deviceLimit + ' 台 Mac', t.id==='team'?'5 people · 1 Mac each':t.deviceLimit + (t.deviceLimit === 1 ? ' Mac' : ' Macs')));
          row.appendChild(head);
          var priceNode = el('div', 'tier-price');
          if (p.amount == null) priceNode.appendChild(both('span', '', '待公布', 'TBA'));
          else {
            priceNode.appendChild(document.createTextNode(money(p.amount, cur)));
            if (p.discounted) { priceNode.appendChild(el('del', '', money(p.regular, cur))); anyDiscount = true; }
          }
          row.appendChild(priceNode);
          if (t.recommended) row.appendChild(both('span', 'tier-badge', '最受欢迎', 'Most popular'));
          n.appendChild(row);
        });
        if (!tiers.length) n.appendChild(both('p', 'notice',
          purchasesOpen ? '价格尚未公布。' : '内测期间应用内购买尚未开放。',
          purchasesOpen ? 'Prices are not published yet.' : 'In-app purchases are not open during this beta.'));
      });
      document.querySelectorAll('[data-pro-launch]').forEach(function (n) {
        n.hidden = !anyDiscount;
        if (!n.hidden) {
          var d = new Date(pricing.launchUntil);
          var zhLabel = n.querySelector('[lang="zh"]');
          var enLabel = n.querySelector('[lang="en"]');
          if (zhLabel) zhLabel.textContent = '首发价，截至 ' + (d.getMonth() + 1) + ' 月 ' + d.getDate() + ' 日';
          if (enLabel) enLabel.textContent = 'Launch price until ' + d.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
        }
      });
      document.querySelectorAll('[data-packs]').forEach(function (n) {
        n.textContent = '';
        var packs = purchasesOpen ? (pricing.packs || []).filter(function (p) { return p.enabled && p[cur] && p[cur].amount != null; }) : [];
        packs.forEach(function (p) {
          var pack = el('div', 'pack' + (p.recommended ? ' recommended' : ''));
          pack.appendChild(el('b', '', Number(p[cur].points).toLocaleString('en-US')));
          pack.appendChild(both('span', '', '点 · ' + money(p[cur].amount, cur), 'credits · ' + money(p[cur].amount, cur)));
          n.appendChild(pack);
        });
        if (!packs.length) n.appendChild(both('p', 'notice',
          purchasesOpen ? '点数包价格尚未公布。' : '内测期间应用内购买尚未开放。',
          purchasesOpen ? 'Credit pack prices are not published yet.' : 'In-app purchases are not open during this beta.'));
      });
      document.querySelectorAll('[data-config]').forEach(function (n) {
        var v = pricing[n.getAttribute('data-config')];
        if (v != null) n.textContent = v;
      });
      document.querySelectorAll('.currency-switch button').forEach(function (b) {
        b.setAttribute('aria-pressed', String(b.getAttribute('data-currency') === cur));
      });
    };
    document.querySelectorAll('.currency-switch button').forEach(function (b) {
      b.addEventListener('click', function () { currency = b.getAttribute('data-currency'); fill(); });
    });
    fill();
    fetch(API + '/pricing', { headers: { Accept: 'application/json' } })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (body) {
        if (!body.result) return;
        pricing = body.result;
        if (body.result.defaultCurrency) currency = body.result.defaultCurrency;
        fill();
      })
      .catch(function () {
        // Keep the published fallback. Default currency follows the browser.
        currency = /^zh(-CN|-Hans)?/i.test(navigator.language || '') ? 'CNY' : 'USD';
        fill();
      });
  }
})();
