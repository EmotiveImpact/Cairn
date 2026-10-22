const { chromium } = require(process.argv[2] + '/playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  for (const n of ['a-number', 'b-ask', 'c-disk']) {
    await p.goto('http://localhost:4173/v2/hero-ideas/' + n + '.html'); await p.waitForTimeout(800);
    await p.screenshot({ path: '/mnt/project-files/website-remix/idea-' + n + '.png' });
  }
  await b.close();
})();
