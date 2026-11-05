// Glance website runtime: localized media, live Widget catalog and live pricing.
(function () {
  var API = 'https://api.glancepreview.com/api/v2';
  var root = document.documentElement;

  // The URL and generated HTML determine language; language links navigate.
  // Japanese and German pages reuse English media where no localized file exists.
  function switchMedia(lang) {
    document.querySelectorAll('img[data-src-en]').forEach(function (img) {
      var src = img.getAttribute('data-src-' + lang) || img.getAttribute('data-src-en');
      if (src && img.getAttribute('src') !== src) img.setAttribute('src', src);
    });
    document.querySelectorAll('video[data-video-en]').forEach(function (video) {
      var media = video.getAttribute('data-video-' + lang) ? lang : 'en';
      var src = video.getAttribute('data-video-' + media);
      if (!src || video.getAttribute('src') === src) return;
      var time = video.currentTime || 0;
      video.poster = video.getAttribute('data-poster-' + media);
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

  // First-party, tab-scoped analytics. Never send full URLs, query strings,
  // link text, referrers, account IDs or media. Respect browser privacy signals.
  var analyticsSession = null;
  if (location.hostname === 'glancepreview.com' && navigator.doNotTrack !== '1' &&
      navigator.globalPrivacyControl !== true && typeof crypto.randomUUID === 'function') {
    try {
      analyticsSession = sessionStorage.getItem('glance.analytics.session');
      if (!/^[A-Za-z0-9_-]{16,128}$/.test(analyticsSession || '')) {
        analyticsSession = crypto.randomUUID();
        sessionStorage.setItem('glance.analytics.session', analyticsSession);
      }
    } catch (_) { analyticsSession = crypto.randomUUID(); }
  }
  // Only utm_source / medium / campaign / content, as normalized slugs. A tagged
  // visit replaces the tab's stored channel; other query parameters are ignored.
  var campaignKeys = ['source', 'medium', 'campaign', 'content'], campaign = null;
  (function () {
    var url; try { url = new URL(location.href); } catch (_) { return; }
    var found = {}, tagged = [];
    url.searchParams.forEach(function (_, name) { if (/^utm_/i.test(name)) tagged.push(name); });
    campaignKeys.forEach(function (key) {
      var value = (url.searchParams.get('utm_' + key) || '').trim().toLowerCase();
      if (/^[a-z0-9._-]{1,64}$/.test(value)) found[key] = value;
    });
    if (analyticsSession) {
      try {
        if (found.source) sessionStorage.setItem('glance.analytics.campaign', JSON.stringify(found));
        campaign = JSON.parse(sessionStorage.getItem('glance.analytics.campaign') || 'null');
      } catch (_) { campaign = found.source ? found : null; }
      if (!campaign || !/^[a-z0-9._-]{1,64}$/.test(campaign.source || '')) campaign = null;
    }
    // Keep shared or bookmarked links clean so they do not re-attribute later visits.
    if (tagged.length && window.history && history.replaceState) {
      tagged.forEach(function (name) { url.searchParams.delete(name); });
      try { history.replaceState(history.state, '', url.pathname + url.search + url.hash); } catch (_) {}
    }
  })();
  function pageKey(path) {
    var key = path.replace(/^\/(en|ja|de)(?=\/|$)/, '').replace(/^\/+|\/+$/g, '') || 'home';
    return ['home','pricing','widgets','ai-models','install','terms','privacy','refunds','acceptable-use'].includes(key) ? key : 'other';
  }
  function trackWebsite(kind, target, placement) {
    if (!analyticsSession) return;
    var payload = {id:crypto.randomUUID(), sessionID:analyticsSession, kind:kind,
      page:pageKey(location.pathname), language:language};
    if (target) { payload.target = target; payload.placement = placement; }
    if (campaign) campaignKeys.forEach(function (key) {
      var value = campaign[key];
      if (typeof value === 'string' && /^[a-z0-9._-]{1,64}$/.test(value))
        payload['utm' + key.charAt(0).toUpperCase() + key.slice(1)] = value;
    });
    // keepalive allows a CTA navigation to proceed while its small event is sent.
    fetch(API + '/analytics/website', {method:'POST', credentials:'omit', keepalive:true,
      headers:{'Content-Type':'text/plain;charset=UTF-8'}, body:JSON.stringify(payload)}).catch(function () {});
  }
  trackWebsite('page_view');
  // Language menu: close on an outside click or Escape.
  function closeLanguageMenus(except) {
    document.querySelectorAll('details.lang-menu[open]').forEach(function (menu) {
      if (menu !== except) menu.removeAttribute('open');
    });
  }
  document.addEventListener('keydown', function (event) { if (event.key === 'Escape') closeLanguageMenus(null); });
  document.addEventListener('click', function (event) {
    closeLanguageMenus(event.target.closest && event.target.closest('details.lang-menu'));
    var link = event.target.closest && event.target.closest('a,button[data-currency]');
    if (!link) return;
    var target, placement = link.closest('header') ? 'header' : link.closest('footer') ? 'footer' : 'content';
    if (link.hasAttribute('data-download-cta')) {
      target = 'download';
      var namedPlacement = link.getAttribute('data-download-cta');
      if (['home','install'].includes(namedPlacement)) placement = namedPlacement;
    } else if (link.hasAttribute('data-currency')) target = 'currency';
    else {
      var url; try { url = new URL(link.href, location.href); } catch (_) { return; }
      if (url.origin !== location.origin) return;
      if (link.classList && link.classList.contains('lang-option')) target = 'language';
      else if (url.hash === '#download') target = 'download_section';
      else if (url.hash === '#loop') target = 'features';
      else if (['pricing','install','widgets','ai-models','home'].includes(pageKey(url.pathname))) target = pageKey(url.pathname);
    }
    if (target) trackWebsite('cta_click', target, placement);
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
  // Japanese and German fall back to English (including Widget names and summaries).
  function both(tag, cls, zh, en, ja, de) {
    var text = language === 'zh' ? zh : language === 'ja' && ja != null ? ja : language === 'de' && de != null ? de : en;
    var node = el(tag, cls, text);
    node.setAttribute('lang', language === 'zh' || text !== en ? language : 'en');
    return node;
  }

  // Live Widget catalog: names, summaries and per-run credit prices come from
  // the same service the app uses, so the site never drifts from Admin.
  function renderWidgets(target, widgets) {
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
        price.appendChild(cost === 0 ? both('span', '', '免费', 'Free', '無料', 'Kostenlos') : duration ?
          both('span', '', cost + ' 点 / ' + duration + ' 秒', cost + ' credits / ' + duration + ' sec',
            cost + ' クレジット / ' + duration + ' 秒', cost + ' Credits / ' + duration + ' s') :
          both('span', '', cost + ' 点 / 次', cost + ' credits / run', cost + ' クレジット / 回', cost + ' Credits / Ausführung'));
        top.appendChild(price);
        body.appendChild(top);
        body.appendChild(both('p', '', w.summary || '', en.summary || w.summary || ''));
        var meta = el('div', 'meta');
        var uploads = w.privacy && w.privacy.uploadsMedia;
        meta.appendChild(both('span', '', uploads ? '运行时上传所选媒体到云端处理' : '在 Glance 服务端处理',
          uploads ? 'Uploads the selected media for cloud processing' : 'Processed by Glance servers',
          uploads ? '実行時に選択したメディアをクラウドにアップロードして処理' : 'Glance のサーバーで処理',
          uploads ? 'Lädt die ausgewählten Medien zur Verarbeitung in die Cloud hoch' : 'Wird auf Glance-Servern verarbeitet'));
        body.appendChild(meta);
        card.appendChild(body);
        target.appendChild(card);
      });
    if (!target.children.length) target.appendChild(both('p', 'notice', '暂无可用的 Widget。', 'No Widgets are available right now.',
      '現在利用できる Widget はありません。', 'Derzeit sind keine Widgets verfügbar.'));
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
            t.appendChild(both('p', 'notice', 'Widget 列表暂时无法加载，请稍后刷新。', 'The Widget list could not be loaded. Please refresh in a moment.',
              'Widget の一覧を読み込めませんでした。しばらくしてから再読み込みしてください。', 'Die Widget-Liste konnte nicht geladen werden. Bitte lade die Seite gleich neu.'));
          }
        });
      });
  }

  // Live pricing. Admin is the single source of truth; the embedded JSON is the
  // last published fallback so the page is complete without the API.
  var fallbackNode = document.getElementById('pricing-fallback');
  if (fallbackNode) {
    var pricing = JSON.parse(fallbackNode.textContent);
    var currency = language === 'en' ? 'USD' : 'CNY';
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
