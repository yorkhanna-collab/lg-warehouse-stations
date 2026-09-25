// Print ONE ShipStation label from the right PC's own browser (side copy, CDP on localhost:9223 via ssh -L).
// Aborts unless exactly one shipment is selected AND the Label destination is the right PC's ZD420.
const { chromium } = require('/Users/yorkhanna/projects/affiliate-coupon-site/node_modules/playwright');
const WANT = process.argv[2] || '323658721'; // shipment #; order 44352 (already a known test label)
(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
  const ctx = browser.contexts()[0];
  const page = ctx.pages().find(p => p.url().includes('shipstation')) || ctx.pages()[0];
  await page.bringToFront();
  if (!page.url().includes('/shipments')) await page.goto('https://ship15.shipstation.com/shipments', { waitUntil: 'domcontentloaded' });
  for (let i = 0; i < 20; i++) { // the right PC is on Wi-Fi; the grid takes ~15s
    const n = await page.evaluate(() => [...document.querySelectorAll('button')].filter(b => /^\d{8,10}$/.test(b.textContent.trim())).length);
    if (n > 0) break;
    await page.waitForTimeout(2000);
  }
  if (page.url().includes('signin')) { console.log('ABORT: not logged in'); process.exit(2); }
  const printTo = await page.evaluate(() => { const k = Object.keys(localStorage).find(k => /shipstation\.printSettings$/.test(k)); try { const v = JSON.parse(localStorage.getItem(k)); return v.label.name + ' @ ' + v.label.workstationName; } catch (e) { return 'unreadable'; } });
  console.log('browser Print To:', printTo);
  // clear any selection, then select exactly the wanted row (or the newest row if not on page)
  const sel = await page.evaluate((want) => {
    const boxes = [...document.querySelectorAll('[data-testid^="checkbox-clickable-checkbox-"]')];
    const header = boxes[0];
    if ((document.body.innerText.match(/(\d+) Selected/) || [])[1]) { header.click(); }
    let btn = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === want);
    let used = want;
    if (!btn) { btn = [...document.querySelectorAll('button')].find(b => /^\d{8,10}$/.test(b.textContent.trim())); used = btn ? btn.textContent.trim() + ' (newest; wanted not on page)' : null; }
    if (!btn) return { err: 'no shipment rows' };
    let row = btn, cb = null;
    for (let i = 0; i < 8 && row; i++) { row = row.parentElement; cb = row && row.querySelector('[data-testid^="checkbox-clickable-checkbox-"]'); if (cb) break; }
    if (!cb || cb === header) return { err: 'row checkbox not found safely' };
    cb.click();
    return { used, order: (row.innerText.match(/\b(4\d{4})\b/) || [])[1] || '?', selection: (document.body.innerText.match(/(\d+) Selected/) || ['none'])[0] };
  }, WANT);
  console.log('select:', JSON.stringify(sel));
  if (sel.err || sel.selection !== '1 Selected') { console.log('ABORT: selection not exactly one'); process.exit(3); }
  await page.locator('button:has-text("Print")').first().click();
  await page.waitForTimeout(1500);
  const opt = page.getByRole('button', { name: /^Label / }).first();
  const optText = (await opt.innerText().catch(() => '')).replace(/\s+/g, ' ').trim();
  console.log('label destination:', optText);
  if (!/ZD420-300dpi/.test(optText)) { console.log('ABORT: destination is not the right ZD420'); await page.keyboard.press('Escape'); process.exit(4); }
  await opt.click();
  await page.waitForTimeout(6000);
  console.log('PRINTED from right PC browser at', new Date().toTimeString().slice(0, 8));
  await browser.close();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
