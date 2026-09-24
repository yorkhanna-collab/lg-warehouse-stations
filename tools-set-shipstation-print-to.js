// Drive the packer's cloned Chrome on the right PC over CDP (tunnelled to localhost:9223).
// 1) set ShipStation "Print To" for Labels to DESKTOP-UKL2D68 / ZDesigner ZD420-300dpi ZPL
// 2) verify the Printing Setup row shows it
// 3) print the label for shipment 315099032 through this browser (-> Connect on this PC -> ZD420)
const { chromium } = require('/Users/yorkhanna/projects/affiliate-coupon-site/node_modules/playwright');
const VALUE = {"label":{"id":"p-zdesignerzd420300dpizpl","name":"ZDesigner ZD420-300dpi ZPL","shared":true,"disabled":false,"zplPrintSpeed":4,"zplChunkSize":10,"zplInvert":false,"zplPrintSpeedRemoval":false,"workstationId":"0b8313fe-9dec-4170-9f7a-aeb88464962d","workstationName":"DESKTOP-UKL2D68","isSsc":true,"isGcp":false}};
(async () => {
  const browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
  const ctx = browser.contexts()[0];
  let page = ctx.pages().find(p => p.url().includes('shipstation')) || ctx.pages()[0];
  await page.bringToFront();
  await page.goto('https://ship15.shipstation.com/settings/printing', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(6000);
  console.log('url:', page.url());
  if (page.url().includes('signin')) { console.log('NOT LOGGED IN in this browser'); await browser.close(); process.exit(2); }
  const before = await page.evaluate(() => Object.keys(localStorage).filter(k => /shipstation\.printSettings/.test(k)).map(k => k + ' = ' + localStorage.getItem(k)));
  console.log('before:', before);
  const keys = await page.evaluate((v) => {
    let ks = Object.keys(localStorage).filter(k => /shipstation\.printSettings$/.test(k));
    if (ks.length === 0) { const any = Object.keys(localStorage).find(k => /^v3-[^.]+\.shipstation\./.test(k)); const prefix = any ? any.split('.shipstation.')[0] : 'v3-f2882640'; ks = [prefix + '.shipstation.printSettings']; }
    for (const k of ks) { const cur = JSON.parse(localStorage.getItem(k) || '{}'); cur.label = v.label; localStorage.setItem(k, JSON.stringify(cur)); }
    return ks;
  }, VALUE);
  console.log('set keys:', keys);
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(6000);
  const labelRow = await page.evaluate(() => { const t = document.body.innerText; const i = t.indexOf('Document Type'); return t.slice(i, i + 220).replace(/\n/g, ' | '); });
  console.log('printing setup row:', labelRow);
  // print the label via this browser
  await page.goto('https://ship15.shipstation.com/shipments', { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(8000);
  const sel = await page.evaluate(() => {
    const btn = [...document.querySelectorAll('button')].find(b => b.textContent.trim() === '315099032');
    if (!btn) return 'row not found';
    let row = btn;
    for (let i = 0; i < 8 && row; i++) { row = row.parentElement; const cb = row && row.querySelector('[data-testid^="checkbox-clickable-checkbox-"]'); if (cb) { cb.click(); return 'row checkbox clicked'; } }
    return 'no checkbox';
  });
  console.log('select:', sel);
  await page.waitForTimeout(1500);
  const count = await page.evaluate(() => (document.body.innerText.match(/(\d+) Selected/) || ['none'])[0]);
  console.log('selection:', count);
  if (count !== '1 Selected') { console.log('ABORT: not exactly one selected'); await browser.close(); process.exit(3); }
  await page.getByRole('button', { name: 'Print', exact: true }).first().click();
  await page.waitForTimeout(1500);
  const opt = page.getByRole('button', { name: /^Label / });
  const optText = await opt.first().innerText().catch(() => '?');
  console.log('label option:', optText.replace(/\n/g, ' '));
  await opt.first().click();
  await page.waitForTimeout(6000);
  console.log('print clicked');
  await browser.close();
})().catch(e => { console.error('ERR', e.message); process.exit(1); });
