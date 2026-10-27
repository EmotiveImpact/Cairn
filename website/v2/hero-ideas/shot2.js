const { chromium } = require(process.argv[2] + '/playwright');
(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const p = await b.newPage({ viewport: { width: 1440, height: 900 } });
  p.on('console', m => console.log(m.text())); p.on('pageerror', e => console.log('ERR', e.message));
  await p.goto('http://localhost:4173/v2/hero-ideas/' + process.argv[3] + '.html'); await p.waitForTimeout(3000);
  await p.screenshot({ path: '/mnt/project-files/website-remix/idea-' + process.argv[3] + '.png' });
  await b.close();
})();
