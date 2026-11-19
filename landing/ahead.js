// Shared by every Ahead page: language, top bar, reveals, and (where the page has them) the example answer, "Frag Ahead" and the waitlist.
(function () {
  'use strict';
  function $(s, root) { return (root || document).querySelector(s); }
  function $$(s, root) { return (root || document).querySelectorAll(s); }
  function meta(name) { var m = $('meta[name="' + name + '"]'); return m ? m.content : null; }

  // a page without the ahead-api tag has nothing that talks to the server
  var api = meta('ahead-api');
  var API = (api === null ? 'demo' : api).replace(/\/$/, '');
  // Static hosts (GitHub Pages) have no /waitlist/join — fall back to preview mode
  if (!API && /\.github\.io$/i.test(location.hostname)) API = 'demo';
  var store = {
    get: function (k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set: function (k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  };
  if (API === 'demo') {
    var realFetch = window.fetch.bind(window);
    window.fetch = function (url, opts) {
      var u = String(url);
      function reply(o) { return Promise.resolve(new Response(JSON.stringify(o), { status: 200, headers: { 'Content-Type': 'application/json' } })); }
      // no place, no headcount: a queue exists only on a real server
      if (u.indexOf('demo/waitlist/') === 0) return reply({ preview: true });
      if (u.indexOf('demo/') === 0) return Promise.reject(new Error('preview'));
      return realFetch(url, opts);
    };
  }

  var APP = meta('ahead-app') || '../';
  $$('[data-app]').forEach(function (a) { a.href = APP; });

  var qLang = new URLSearchParams(location.search).get('lang');
  var lang = qLang === 'en' || qLang === 'de' ? qLang : store.get('ahead-lang') || ((navigator.language || 'de').toLowerCase().indexOf('de') === 0 ? 'de' : 'en');
  function L(de, en) { return lang === 'en' ? en : de; }
  function esc(s) { return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
  var reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  var talksDe = {
    steuer: { q: 'Bekomme ich Steuer zurück?', a: 'Wer nicht das ganze Jahr gearbeitet hat oder pendelt, bekommt oft <b>mehrere hundert Euro</b> zurück. Ahead rechnet es für jedes offene Jahr aus.', next: 'Rückhol-Check machen: drei Antworten, ohne Anmeldung.' },
    frist: { q: 'Ich hab 2022 nie abgegeben. Zu spät?', a: 'Nein. Freiwillig geht es <b>vier Jahre</b> zurück, 2022 noch bis zum <b>31. Dezember 2026</b>. Danach ist das Geld weg.', next: 'Jetzt 2022 prüfen, bevor die Frist endet.' },
    gehalt: { q: 'Was steht da auf meiner ersten Abrechnung?', a: 'Brutto minus Steuern und Sozialabgaben. Bei Steuerklasse I bleiben von 3.000 € Brutto oft etwa <b>1.950 €</b> Netto.', list: ['Steuerklasse prüfen', 'Kirchensteuer und KV-Zusatz checken'], next: 'Abrechnung neben Gehaltsrechner legen und die Differenz verstehen.' },
    dispo: { q: 'Ich bin jeden Monat im Dispo. Was tun?', a: 'Der Dispo kostet oft <b>10 Prozent Zinsen im Jahr oder mehr</b>. Zuerst die Lücke kennen: Wie viel fehlt dir im Schnitt vor dem Gehalt?', next: 'Heute die größte Fixkosten-Position prüfen und einen Puffer von einem halben Monatsgehalt planen.' },
    abos: { q: 'Alles wird teurer. Wo verliere ich Geld?', a: 'Drei laufen weiter, obwohl du sie kaum nutzt: Fitness <b>29,90 €</b>, Streaming <b>17,99 €</b>, Cloud <b>2,99 €</b>. Zusammen 50,88 € im Monat.', next: 'Heute eines kündigen. Am meisten bringt das Fitnessstudio.' },
    wg: { q: 'Wie teilen wir die WG-Kasse fair?', a: 'Miete nach Zimmergröße, Rest 50/50, oder alles nach Einkommen. Wichtig ist eine Regel, nicht die perfekte Formel.', next: 'Eine Regel festlegen und den ersten Monat gemeinsam nachrechnen.' },
    bav: { q: 'Lohnt sich die Betriebsrente?', a: 'Wenn der Arbeitgeber zuzahlt, oft ja. Ohne Zuschuss erst Notgroschen und einen ETF-Sparplan prüfen.', list: ['Zuschuss und Kosten vom AG holen', 'Netto-Effekt auf dem Gehaltszettel checken'], next: 'Bei HR nach Zuschuss und Kosten fragen.' }
  };
  var talksEn = {
    steuer: { q: 'Do I get tax back?', a: 'If you didn’t work the whole year or you commute, often <b>several hundred euros</b>. Ahead works it out for every open year.', next: 'Do the refund check: three answers, no sign-up.' },
    frist: { q: 'I never filed for 2022. Too late?', a: 'No. Voluntary returns go back <b>four years</b>, 2022 until <b>31 December 2026</b>. After that the money is gone.', next: 'Check 2022 now, before the deadline ends.' },
    gehalt: { q: 'What’s on my first payslip?', a: 'Gross minus tax and social contributions. In tax class I, €3,000 gross often leaves about <b>€1,950</b> net.', list: ['Check your tax class', 'Look at church tax and health insurance surcharge'], next: 'Put the payslip next to a salary calculator and understand the gap.' },
    dispo: { q: 'I’m overdrawn every month. What now?', a: 'An overdraft often costs <b>10 percent interest a year or more</b>. First know the gap: how much are you short on average before payday?', next: 'Check your biggest fixed cost today and plan a buffer of half a month’s pay.' },
    abos: { q: 'Everything costs more. Where do I lose money?', a: 'Three keep running though you barely use them: gym <b>€29.90</b>, streaming <b>€17.99</b>, cloud <b>€2.99</b>. That’s €50.88 a month.', next: 'Cancel one today. The gym usually helps most.' },
    wg: { q: 'How do we split flatshare money fairly?', a: 'Rent by room size, the rest 50/50, or everything by income. One rule beats a perfect formula.', next: 'Pick one rule and reconcile the first month together.' },
    bav: { q: 'Is the company pension worth it?', a: 'If your employer tops up, often yes. Without a top-up, fill the emergency fund and check an ETF plan first.', list: ['Ask HR for the top-up and costs', 'Check the net effect on your payslip'], next: 'Ask HR about the top-up and costs.' }
  };
  var talks = lang === 'en' ? talksEn : talksDe;

  function block(q, a, list, next, note) {
    var html = '<div class="you fade">' + esc(q) + '</div><div class="buddy fade"><span class="coin"><svg><use href="#b"/></svg></span><div>';
    html += '<div class="say-line">' + a + '</div>';
    if (list && list.length) html += '<ul>' + list.map(function (x) { return '<li>' + x + '</li>'; }).join('') + '</ul>';
    if (next) html += '<div class="step"><em>' + L('Nächster Schritt', 'Next step') + '</em><span>' + next + '</span></div>';
    if (note) html += '<p class="note">' + note + '</p>';
    return html + '</div></div>';
  }
  var talkEl = $('[data-talk]');
  var current = 'abos';
  function showTalk(key) {
    if (!talkEl) return;
    current = key;
    var t = talks[key];
    talkEl.innerHTML = block(t.q, t.a, t.list, t.next);
  }

  function applyLang() {
    document.documentElement.lang = lang;
    $$('[data-en]').forEach(function (el) {
      if (!el.dataset.de) el.dataset.de = el.innerHTML;
      el.innerHTML = lang === 'en' ? el.dataset.en : el.dataset.de;
    });
    $$('[data-en-placeholder]').forEach(function (el) {
      if (!el.dataset.dePlaceholder) el.dataset.dePlaceholder = el.getAttribute('placeholder') || '';
      el.setAttribute('placeholder', lang === 'en' ? el.dataset.enPlaceholder : el.dataset.dePlaceholder);
    });
    $$('[data-en-aria-label]').forEach(function (el) {
      if (!el.dataset.deAria) el.dataset.deAria = el.getAttribute('aria-label') || '';
      el.setAttribute('aria-label', lang === 'en' ? el.dataset.enAriaLabel : el.dataset.deAria);
    });
    $$('[data-en-src]').forEach(function (el) {
      if (!el.dataset.deSrc) el.dataset.deSrc = el.getAttribute('src');
      el.setAttribute('src', lang === 'en' ? el.dataset.enSrc : el.dataset.deSrc);
    });
    $$('[data-en-alt]').forEach(function (el) {
      if (!el.dataset.deAlt) el.dataset.deAlt = el.getAttribute('alt') || '';
      el.setAttribute('alt', lang === 'en' ? el.dataset.enAlt : el.dataset.deAlt);
    });
    $$('[data-lang]').forEach(function (b) { b.textContent = lang === 'en' ? 'DE' : 'EN'; });
    $$('[data-mail]').forEach(function (a) {
      var mail = 'luis.frenkler@t-online.de';
      var body = a.dataset.email || '';
      a.href = 'mailto:' + mail + '?subject=' + encodeURIComponent(L('Ahead Warteliste', 'Ahead waitlist')) + (body ? '&body=' + encodeURIComponent(body) : '');
    });
  }
  applyLang();
  showTalk(current);

  var spot = $('.spot');
  var ask = $('form.ask'), out = $('.answer');
  $$('[data-lang]').forEach(function (b) {
    b.addEventListener('click', function () {
      lang = lang === 'en' ? 'de' : 'en';
      store.set('ahead-lang', lang);
      talks = lang === 'en' ? talksEn : talksDe;
      applyLang();
      showTalk(current);
      var code = store.get('ahead-code');
      if (spot && code && spot.classList.contains('on')) {
        fetch(API + '/waitlist/status?code=' + encodeURIComponent(code)).then(function (r) { if (!r.ok) throw 0; return r.json(); }).then(onStatus).catch(function () {});
      }
      if (out) out.innerHTML = '';
    });
  });

  var ref = new URLSearchParams(location.search).get('ref');
  if (ref) store.set('ahead-ref', ref);

  // ------------------------------------------------------------ waitlist (home)
  if (API === 'demo') $$('[data-demo]').forEach(function (el) { el.hidden = false; });
  function myLink(code) { return location.origin + location.pathname + '?ref=' + code; }
  function onStatus(d) { if (d && d.preview) { store.set('ahead-code', ''); return; } if (d) showSpot(d); }
  function showSpot(d) {
    if (!spot || !d || d.preview || !d.code) return;
    store.set('ahead-code', d.code);
    $$('form.join').forEach(function (f) { f.style.display = 'none'; });
    $$('[data-join-head]').forEach(function (el) { el.hidden = true; });
    spot.classList.add('on');
    var n = Number(d.position);
    var real = Number.isFinite(n) && n >= 1;
    var pos = $('[data-pos]', spot);
    pos.hidden = !real;
    $('[data-place]', spot).hidden = !real;
    if (real) pos.textContent = '#' + n.toLocaleString(L('de-DE', 'en-GB'));
    var friends = Number(d.friends);
    var bars = $('[data-bars]', spot);
    var marks = $$('i', bars);
    var showBars = Number.isFinite(friends) && friends > 0;
    bars.hidden = !showBars;
    if (showBars) for (var i = 0; i < marks.length; i++) marks[i].classList.toggle('on', i < friends);
    var link = myLink(d.code);
    $('[data-link]', spot).textContent = link.replace(/^https?:\/\//, '');
    var text = L('Ahead ist dein persönlicher Finanz-Agent und findet verlorenes Geld. Warteliste: ', 'Ahead is your personal finance agent and finds lost money. Waitlist: ') + link;
    $('[data-wa]', spot).href = 'https://wa.me/?text=' + encodeURIComponent(text);
    $('[data-copy]', spot).onclick = function (ev) {
      var btn = ev.currentTarget;
      var done = function () { btn.textContent = L('Kopiert', 'Copied'); setTimeout(function () { btn.textContent = L('Link kopieren', 'Copy link'); }, 1600); };
      if (navigator.clipboard) navigator.clipboard.writeText(link).then(done, function () {}); else done();
    };
  }
  function showMailStep(form, email) {
    var box = form.parentElement;
    form.classList.remove('is-error');
    form.style.display = 'none';
    var err = form.nextElementSibling;
    if (err) { err.textContent = ''; err.hidden = true; }
    $$('[data-demo]', box).forEach(function (el) { el.hidden = true; });
    var step = $('.mailstep', box);
    if (!step) return;
    var link = $('[data-mail]', step);
    if (link) link.dataset.email = email;
    step.classList.add('on');
    applyLang();
    var r = step.getBoundingClientRect();
    if (r.top < 80 || r.bottom > window.innerHeight - 16) step.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: 'nearest' });
  }
  $$('form.join').forEach(function (form) {
    form.addEventListener('input', function () {
      form.classList.remove('is-error');
      form.email.removeAttribute('aria-invalid');
      var err = form.nextElementSibling;
      if (err && err.textContent) err.textContent = '';
    });
    form.addEventListener('submit', function (e) {
      e.preventDefault();
      var err = form.nextElementSibling, btn = $('button', form), email = form.email.value.trim();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) { form.classList.add('is-error'); form.email.setAttribute('aria-invalid', 'true'); err.hidden = false; err.textContent = L('Bitte gib eine gültige E-Mail-Adresse ein.', 'Please enter a valid email address.'); form.email.focus(); return; }
      form.classList.remove('is-error'); err.textContent = ''; btn.disabled = true; var label = btn.textContent; btn.textContent = L('Einen Moment …', 'One moment …');
      fetch(API + '/waitlist/join', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email: email, ref: store.get('ahead-ref'), lang: lang }) })
        .then(function (r) {
          return r.text().then(function (t) {
            var j = null;
            try { j = t ? JSON.parse(t) : {}; } catch (e) { throw new Error('unreachable'); }
            if (!r.ok) throw new Error((lang === 'en' ? '' : (j && j.error)) || 'unreachable');
            return j;
          });
        })
        .then(function (d) {
          if (d && d.preview) { showMailStep(form, email); return; }
          showSpot(d); var r = spot.getBoundingClientRect(); scrollTo({ top: Math.max(0, r.top + scrollY - 120), behavior: reduceMotion ? 'auto' : 'smooth' });
        })
        .catch(function (x) {
          form.classList.add('is-error');
          err.hidden = false;
          var msg = x && x.message;
          var raw = msg && msg !== 'Failed to fetch' && msg !== 'preview' && msg !== 'unreachable' && msg.indexOf('Unexpected token') === -1 && msg.indexOf('<') === -1;
          err.textContent = raw ? msg : L('Gerade nicht erreichbar. Versuch es gleich noch einmal.', 'Not reachable right now. Please try again in a moment.');
        })
        .finally(function () { btn.disabled = false; btn.textContent = label; });
    });
  });
  var mine = store.get('ahead-code');
  if (spot && mine) fetch(API + '/waitlist/status?code=' + encodeURIComponent(mine)).then(function (r) { if (!r.ok) throw 0; return r.json(); }).then(onStatus).catch(function () {});

  // ------------------------------------------------------------ "Frag Ahead" (home)
  function fromTalk(re, talk) { return [re, talk.a, talk.next, talk.list]; }
  var basicsDe = [
    [/notgroschen|rücklage|reserve|polster/i, '<b>Drei Monatsausgaben</b> auf einem Tagesgeldkonto. Bei 1.500 € Ausgaben im Monat sind das 4.500 €. Erst den Notgroschen füllen, dann investieren.', 'Dauerauftrag direkt nach dem Gehalt.'],
    fromTalk(/betriebsrente|bav|entgeltumwandlung/i, talksDe.bav),
    fromTalk(/steuer|erstattung|zurück/i, talksDe.steuer),
    fromTalk(/frist|zu spät|nicht abgegeben|2022/i, talksDe.frist),
    fromTalk(/dispo|überzogen|im minus|schulden/i, talksDe.dispo),
    fromTalk(/\babos?\b|fitnessstudio|streaming|teurer/i, talksDe.abos),
    fromTalk(/\bwg\b|mitbewohner|wg-kasse/i, talksDe.wg),
    [/etf|sparplan|aktie|fonds|invest/i, 'Ein <b>ETF</b> bildet einen Index nach, also viele Unternehmen auf einmal. Mit einem Sparplan kaufst du jeden Monat automatisch für einen festen Betrag.', 'Erst den Notgroschen, dann einen Betrag, den du jeden Monat sicher schaffst.'],
    fromTalk(/gehalt|abrechnung|steuerklasse|\bnetto\b|\bbrutto\b/i, talksDe.gehalt),
    [/sparen|sparplan|wie viel|wieviel/i, 'Ein guter Start sind <b>10 bis 20 Prozent</b> deines Nettos, direkt am Zahltag per Dauerauftrag.', 'In der App rechne ich aus deinen echten Ausgaben aus, was realistisch ist.']
  ];
  var basicsEn = [
    [/emergency|reserve|cushion|rainy/i, '<b>Three months of spending</b> in an instant-access savings account. At €1,500 of spending a month that’s €4,500. Fill the emergency fund first, then invest.', 'A standing order right after payday.'],
    fromTalk(/company pension|workplace pension|salary conversion/i, talksEn.bav),
    fromTalk(/\btax\b|refund/i, talksEn.steuer),
    fromTalk(/deadline|too late|never filed|2022/i, talksEn.frist),
    fromTalk(/overdraft|overdrawn|\bdebt/i, talksEn.dispo),
    fromTalk(/\bsubscriptions?\b|\bgym\b|\bstreaming\b|expensive|costs more/i, talksEn.abos),
    fromTalk(/flatshare|roommate/i, talksEn.wg),
    [/etf|savings plan|stock|fund|invest/i, 'An <b>ETF</b> tracks an index, so many companies at once. With a savings plan you automatically buy a fixed amount every month.', 'Emergency fund first, then an amount you can safely manage every month.'],
    fromTalk(/salary|payslip|tax class|\bnet\b|\bgross\b/i, talksEn.gehalt),
    [/\bsave\b|how much/i, 'A good start is <b>10 to 20 percent</b> of your net pay, by standing order on payday.', 'In the app I work out from your real spending what’s realistic.']
  ];
  if (ask && out) {
    var device = store.get('ahead-device');
    if (!device) { device = (window.crypto && crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2) + Date.now()).replace(/-/g, ''); store.set('ahead-device', device); }
    var render = function (text) {
      var next = '', body = [], list = [];
      text.split('\n').forEach(function (l) {
        l = l.trim();
        if (!l || /^\[(weiter|merken)/i.test(l)) return;
        var m = /^(\*\*)?(Nächster Schritt|Next step):(\*\*)?\s*(.*)$/.exec(l);
        if (m) { next = m[4]; return; }
        var md = function (s) { return esc(s).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>'); };
        if (/^([-•*]|\d+[.)])\s+/.test(l)) { list.push(md(l.replace(/^([-•*]|\d+[.)])\s+/, ''))); return; }
        body.push(md(l));
      });
      return { a: body.join(' '), list: list, next: esc(next).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>') };
    };
    var show = function (q, a, next, list, note, scroll) {
      out.innerHTML = '<div class="talk">' + block(q, a, list, next, note) + '</div>';
      if (!scroll) return;
      requestAnimationFrame(function () {
        var r = out.getBoundingClientRect();
        var view = window.innerHeight;
        if (r.top >= 88 && r.bottom <= view - 12) return;
        out.scrollIntoView({ behavior: reduceMotion ? 'auto' : 'smooth', block: r.height > view - 140 ? 'start' : 'center' });
      });
    };
    var offline = function (q) {
      var primary = lang === 'en' ? basicsEn : basicsDe;
      var other = lang === 'en' ? basicsDe : basicsEn;
      var note = L('Aus Aheads Grundwissen. In der App rechnet er mit deinen Zahlen.', 'From Ahead’s basic knowledge. In the app it works with your numbers.');
      function hit(row) { return show(q, row[1], esc(row[2]), (row[3] || []).map(esc), note); }
      for (var i = 0; i < primary.length; i++) if (primary[i][0].test(q)) return hit(primary[i]);
      for (var j = 0; j < other.length; j++) if (other[j][0].test(q)) return hit(primary[j]);
      show(q, L('Die KI ist gerade nicht da oder für heute aufgebraucht.', 'The AI is unavailable or used up for today.'), L('Mach den Geld-Check: In der App rechnet Ahead mit deinen Zahlen.', 'Do the money check: in the app Ahead works with your numbers.'));
    };
    ask.addEventListener('submit', function (e) {
      e.preventDefault();
      var q = ask.q.value.trim() || ask.q.placeholder;
      var btn = $('button', ask); btn.disabled = true;
      ask.setAttribute('aria-busy', 'true');
      show(q, '<span class="typing">' + L('schreibt …', 'typing …') + '</span>', '', null, '', true);
      function finish() { btn.disabled = false; ask.removeAttribute('aria-busy'); }
      if (API === 'demo') {
        setTimeout(function () { offline(q); finish(); }, reduceMotion ? 0 : 420);
        return;
      }
      var acc = '';
      fetch(API + '/ai/guest', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ device: device, lang: lang, history: [{ role: 'user', text: q }] }) })
        .then(function (res) {
          if (!res.ok || !res.body) throw 0;
          var reader = res.body.getReader(), dec = new TextDecoder(), buf = '', failed = false;
          return (function pump() {
            return reader.read().then(function (p) {
              if (p.done) { if (failed || !acc) offline(q); else { var r = render(acc); show(q, r.a, r.next, r.list); } return; }
              buf += dec.decode(p.value, { stream: true });
              var parts = buf.split('\n'); buf = parts.pop();
              parts.forEach(function (line) {
                if (line.indexOf('data: ') !== 0) return;
                try {
                  var ev = JSON.parse(line.slice(6));
                  if (ev.t) { acc += ev.t; var r = render(acc); show(q, r.a, '', r.list); }
                  if (ev.error) failed = true;
                } catch (err) {}
              });
              return pump();
            });
          })();
        })
        .catch(function () { offline(q); })
        .finally(finish);
    });
  }

  // ------------------------------------------------------------ top bar, reveals, phone
  // clear at the very top, a paper bar once the page moves (the status bar colour follows)
  var top = $('[data-top]');
  var theme = $('meta[name="theme-color"]');
  var heroColor = theme ? theme.content : '', onPaper = false;
  function onScroll() {
    var now = window.scrollY > 24;
    if (now === onPaper) return;
    onPaper = now;
    top.classList.toggle('on-paper', now);
    if (theme) theme.content = now ? '#FAF7F4' : heroColor;
  }
  if (top) {
    onScroll();
    window.addEventListener('scroll', onScroll, { passive: true });
  }
  // the phone menu closes on a tap outside, on Escape and after a choice
  var menu = $('details.menu');
  if (menu) {
    document.addEventListener('click', function (e) { if (menu.open && (!menu.contains(e.target) || e.target.closest('.menu-panel a'))) menu.open = false; });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape' && menu.open) { menu.open = false; $('summary', menu).focus(); } });
  }

  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.classList.add('seen'); io.unobserve(e.target); }
      });
    }, { threshold: 0.16, rootMargin: '0px 0px -8% 0px' });
    $$('.rise').forEach(function (el) { io.observe(el); });
  } else {
    $$('.rise').forEach(function (el) { el.classList.add('seen'); });
  }

  var phone = $('[data-phone]');
  var stage = $('[data-stage]');
  if (phone && stage && !reduceMotion && window.matchMedia('(hover:hover) and (pointer:fine)').matches) {
    var tx = 0, ty = 0, cx = 0, cy = 0, raf = 0, live = false;
    setTimeout(function () { live = true; }, 800); // the entrance keyframes own the transform until then
    var tick = function () {
      tx += (cx - tx) * 0.08;
      ty += (cy - ty) * 0.08;
      phone.style.transform = 'rotateY(' + tx.toFixed(2) + 'deg) rotateX(' + ty.toFixed(2) + 'deg)';
      // stop once settled instead of running a frame loop forever
      raf = Math.abs(cx - tx) + Math.abs(cy - ty) > 0.01 ? requestAnimationFrame(tick) : 0;
    };
    var kick = function () { if (live && !raf) raf = requestAnimationFrame(tick); };
    stage.addEventListener('pointermove', function (e) {
      var r = stage.getBoundingClientRect();
      cx = ((e.clientX - r.left) / r.width - 0.5) * 10;
      cy = ((e.clientY - r.top) / r.height - 0.5) * -8;
      kick();
    });
    stage.addEventListener('pointerleave', function () { cx = 0; cy = 0; kick(); });
  }
})();
