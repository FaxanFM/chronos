const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

(async () => {
  const executablePath = [
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  ].find(fs.existsSync);
  const browser = await chromium.launch({ headless: true, executablePath });
  try {
    const page = await browser.newPage({ viewport: { width: 1080, height: 1920 }, deviceScaleFactor: 1 });
    const source = `file:///${path.resolve(__dirname, '../assets/chronos-proof-card.html').replace(/\\/g, '/')}`;
    await page.goto(source, { waitUntil: 'load' });
    const proofCard = path.resolve(__dirname, '../assets/chronos-proof-card.png');
    await page.screenshot({ path: proofCard });
    fs.copyFileSync(proofCard, path.resolve(__dirname, '../plugins/chronos/assets/chronos-proof-card.png'));

    await page.setViewportSize({ width: 1280, height: 640 });
    await page.goto(`${source}?social=1`, { waitUntil: 'load' });
    await page.screenshot({ path: path.resolve(__dirname, '../assets/chronos-social-preview.png') });
  } finally {
    await browser.close();
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
