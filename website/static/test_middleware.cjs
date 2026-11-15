// Request-level checks only; no browser, UI automation or live deployment.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const middleware = import('data:text/javascript;base64,' +
  readFileSync(__dirname + '/functions/_middleware.js').toString('base64'));

async function visit(path='/', {country, cookie, agent='Mozilla/5.0', method='GET', host='glancepreview.com', verifiedBot=false, lang}={}) {
  const headers = new Headers({'User-Agent':agent});
  if (cookie) headers.set('Cookie', cookie);
  if (lang) headers.set('Accept-Language', lang);
  const request = new Request('https://' + host + path, {method,headers});
  Object.defineProperty(request, 'cf', {value:{country,botManagement:{verifiedBot}}});
  let passed = false;
  const response = await (await middleware).onRequest({request,next:async()=>{
    passed = true;
    return new Response('original page', {headers:{'Content-Type':'text/html','Vary':'Accept-Encoding'}});
  }});
  return {response, passed};
}

test('homepage selects supported languages from visitor IP country',async()=>{
  for (const country of ['CN','HK','MO','TW']) {
    const {response,passed} = await visit('/',{country});
    assert.equal(response.status,200); assert.equal(passed,true);
  }
  for (const [country,language] of [['JP','ja'],['DE','de'],['AT','de'],['CH','de'],['LI','de']]) {
    const {response,passed} = await visit('/',{country});
    assert.equal(response.status,302);assert.equal(passed,false);
    assert.equal(response.headers.get('Location'),'https://glancepreview.com/'+language+'/');
  }
});
test('unsupported, unavailable and malformed countries fall back to English',async()=>{
  for (const country of ['US','FR','KR','SG','XX','T1',undefined,null,'toString']) {
    const {response} = await visit('/',{country});
    assert.equal(response.headers.get('Location'),'https://glancepreview.com/en/');
  }
});
test('manual language preference takes precedence and invalid cookies are ignored',async()=>{
  for (const language of ['zh','en','ja','de']) {
    const {response} = await visit('/',{country:'JP',cookie:'other=x; glance.language='+language});
    assert.equal(response.status,language==='zh'?200:302);
    assert.equal(response.headers.get('Location'),language==='zh'?null:'https://glancepreview.com/'+language+'/');
  }
  for (const cookie of ['glance.language=fr','glance.language=https://evil.example','glance.language=%E0%A4%A','glance.language=']) {
    const {response} = await visit('/',{country:'JP',cookie});
    assert.equal(response.headers.get('Location'),'https://glancepreview.com/ja/');
  }
});
test('only the homepage entry is negotiated; language URLs, assets and payment routes retain their path',async()=>{
  for (const path of ['/en/','/ja/','/de/','/pricing/','/en/widgets/','/assets/site.js','/download/Glance-1.0.4.dmg','/pay/return/?order=example','/robots.txt','/sitemap.xml']) {
    const {response,passed} = await visit(path,{country:'JP',cookie:'glance.language=de'});
    assert.equal(passed,true,path);assert.equal(response.status,200,path);
  }
  const {response,passed} = await visit('/',{country:'JP',method:'POST'});
  assert.equal(passed,true);assert.equal(response.status,200);
});
test('personalized redirects preserve query strings and are never shared-cacheable',async()=>{
  const {response} = await visit('/?utm_source=x&ref=example',{country:'JP',method:'HEAD'});
  assert.equal(response.headers.get('Location'),'https://glancepreview.com/ja/?utm_source=x&ref=example');
  assert.equal(response.headers.get('Cache-Control'),'private, no-store');
  assert.equal(response.headers.get('Vary'),'Cookie, Accept-Language');
  const chinese = (await visit('/',{country:'CN'})).response;
  assert.equal(chinese.headers.get('Cache-Control'),'private, no-store');
  assert.equal(chinese.headers.get('Vary'),'Accept-Encoding, Cookie, Accept-Language');
});
test('canonical domain redirects and preview noindex still work',async()=>{
  const alias = (await visit('/?ref=x',{host:'www.glancepreview.com',country:'JP'})).response;
  assert.equal(alias.status,301);assert.equal(alias.headers.get('Location'),'https://glancepreview.com/?ref=x');
  for (const country of ['CN','JP']) {
    const preview = (await visit('/',{country,host:'preview.glance.pages.dev'})).response;
    assert.equal(preview.headers.get('X-Robots-Tag'),'noindex');
    if(country==='JP')assert.equal(preview.headers.get('Location'),'https://preview.glance.pages.dev/ja/');
  }
});
test('search crawlers can still discover the canonical Chinese entry',async()=>{
  for (const options of [{agent:'Googlebot'}, {agent:'bingbot'}, {verifiedBot:true}]) {
    const {response,passed} = await visit('/',{country:'US',...options});
    assert.equal(passed,true);assert.equal(response.status,200);
  }
});

test('browser language comes before the IP country; Chinese browsers stay on the Chinese entry',async()=>{
  for (const [lang,country,expected] of [['en-US,en;q=0.9','TW','en'],['ja-JP,ja;q=0.9','CN','ja'],['de-DE','US','de'],['en','JP','en']]) {
    const {response,passed} = await visit('/',{lang,country});
    assert.equal(response.status,302); assert.equal(passed,false);
    assert.equal(response.headers.get('Location'),'https://glancepreview.com/'+expected+'/');
    assert.match(response.headers.get('Vary'),/Accept-Language/);
  }
  for (const [lang,country] of [['zh-CN,zh;q=0.9','US'],['zh-TW','DE']]) {
    const {response,passed} = await visit('/',{lang,country});
    assert.equal(response.status,200); assert.equal(passed,true);
  }
  const fr = await visit('/',{lang:'fr-FR,fr;q=0.9',country:'JP'});
  assert.equal(fr.response.headers.get('Location'),'https://glancepreview.com/ja/');
  const saved = await visit('/',{lang:'en-US',country:'US',cookie:'glance.language=zh'});
  assert.equal(saved.response.status,200);
  const bot = await visit('/',{lang:'en-US',country:'US',agent:'Mozilla/5.0 (compatible; Googlebot/2.1)'});
  assert.equal(bot.response.status,200); assert.equal(bot.passed,true);
});
