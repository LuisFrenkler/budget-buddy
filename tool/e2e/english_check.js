// Clicks through the English web demo (served at localhost:8765/budget-buddy/)
// and lists every visible text that still looks German. Run: node english_check.js
// Walks the English demo and lists every visible text that looks German.
const { chromium } = require('playwright');
const GERMAN = /\b(und|oder|der|die|das|dein|deine|deinen|nicht|noch|mit|für|bei|vom|zum|bis|ein|eine|ist|sind|Monat|Ausgaben|Einnahmen|Konto|Konten|Sparziel|Sparziele|Buchung|Buchungen|Übernehmen|Verwerfen|Abbrechen|Speichern|Löschen|Zurück|Weiter|heute|gestern|Woche|gesamt|frei|knapp|Ziel|Ziele|Vertrag|Verträge|Kündigen|Steuer|Gehalt|Miete|Lebensmittel|Wohnen|Unterhaltung|Sonstiges|Kategorie|Kategorien|Einstellungen|Hinweis|Nächster Schritt)\b/;
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 390, height: 844 }, locale: 'en-US' });
  await p.goto('http://localhost:8765/budget-buddy/');
  await p.waitForTimeout(6000);
  await p.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await p.waitForTimeout(800);
  const texts = async () => p.$$eval('flt-semantics *', els => [...new Set(els.map(e => (e.getAttribute('aria-label') || (e.children.length === 0 ? e.textContent : '') || '').trim()).filter(Boolean))]);
  const click = async (re, nth = 0) => {
    const pos = await p.evaluate(([src, nth]) => {
      const r = new RegExp(src);
      const els = [...document.querySelectorAll('flt-semantics *')].filter(e => r.test(e.getAttribute('aria-label') || '') || (e.children.length === 0 && r.test(e.textContent || '')));
      const el = els[nth]; if (!el) return null;
      const b = el.getBoundingClientRect(); return [b.x + b.width / 2, b.y + b.height / 2];
    }, [re, nth]);
    if (pos) { await p.mouse.click(pos[0], pos[1]); await p.waitForTimeout(1800); }
    return !!pos;
  };
  const found = new Map();
  const scan = async (where) => {
    console.log('SCAN', where, JSON.stringify((await texts()).slice(0, 12)).slice(0, 400));
    for (let s = 0; s < 3; s++) {
      for (const t of await texts()) {
        for (const line of t.split('\n')) if (GERMAN.test(line) && !found.has(line)) found.set(line, where);
      }
      await p.mouse.wheel(0, 700); await p.waitForTimeout(600);
    }
  };
  await click('^Start$');
  const vals = ['Luis Test', 'luis@example.com', 'sicheresPasswort1'];
  for (let i = 0; i < 3; i++) { const inp = await p.$$('input'); await inp[i].click(); await p.waitForTimeout(200); await p.keyboard.type(vals[i], { delay: 20 }); }
  await p.mouse.click(44, 494); await p.waitForTimeout(400);
  await click('^Create account$'); await p.waitForTimeout(4000);
  await click('^Try with sample data'); await p.waitForTimeout(9000);
  const tabs = await p.evaluate(() => [...document.querySelectorAll('flt-semantics *')].map(e => { const b = e.getBoundingClientRect(); return [((e.getAttribute('aria-label') || '') + '|' + (e.children.length === 0 ? e.textContent : '')).slice(0, 30), Math.round(b.x + b.width / 2), Math.round(b.y + b.height / 2), Math.round(b.height)]; }).filter(t => t[2] > 780 && t[0] !== '|' && !t[0].includes('Quick')));
  console.log('TABS', JSON.stringify(tabs));
  for (const [name, x, y] of tabs) {
    await p.mouse.click(x, y); await p.waitForTimeout(2000);
    await scan('Tab ' + name.split('\n')[0]);
  }
  // the profile and its pages
  await click('^Overview$'); await p.mouse.click(360, 40); await p.waitForTimeout(1500);
  await scan('Profile');
  const rows = (await texts()).filter(t => /^[A-Z][a-z]/.test(t) && t.length < 60).slice(0, 25);
  for (const r of rows) {
    const label = r.split('\n')[0].replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    if (!(await click('^' + label))) continue;
    await scan('Profile › ' + r.split('\n')[0]);
    await p.goBack().catch(() => {}); await p.keyboard.press('Escape'); await p.waitForTimeout(800);
    await click('^Back$'); await p.waitForTimeout(800);
  }
  console.log('scanned', found.size, (await texts()).length);
  for (const [k, v] of found) console.log(v + ' | ' + k.slice(0, 160));
  await b.close();
})();
