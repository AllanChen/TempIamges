// Unit tests for the runtime's analytics adapter; no browser or UI automation.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const { randomUUID } = require('node:crypto');
const source = readFileSync(__dirname + '/src/assets/site.js', 'utf8');
function runtime({ hostname='glancepreview.com', dnt, gpc, storage=new Map(), search='?email=secret@example.com' }={}) {
  const calls=[], listeners={}, replaced=[];
  const location={hostname,origin:'https://'+hostname,pathname:'/en/pricing/',href:'https://'+hostname+'/en/pricing/'+search+'#token'};
  const history={state:null,replaceState:(state,title,url)=>replaced.push(url)};
  const document={documentElement:{getAttribute:()=> 'en'},querySelectorAll:()=>[],getElementById:()=>null,
    addEventListener:(name,fn)=>{listeners[name]=fn;}};
  vm.runInNewContext(source,{document,location,URL,crypto:{randomUUID},
    navigator:{doNotTrack:dnt,globalPrivacyControl:gpc},window:{addEventListener(){},history},history,
    sessionStorage:{getItem:k=>storage.get(k),setItem:(k,v)=>storage.set(k,v)},
    fetch:(url,options)=>{calls.push({url,...options,payload:JSON.parse(options.body)});return Promise.resolve({ok:true});}});
  const click=(attributes={},href='https://glancepreview.com/en/install/',header=false)=>{
    const link={href,hasAttribute:k=>k in attributes,getAttribute:k=>attributes[k],closest:s=>header&&s==='header'?{}:null};
    listeners.click({target:{closest:()=>link}});
  };
  return {calls,click,replaced};
}
test('page and download clicks reach first-party collection without URL or account content',()=>{
  const r=runtime();r.click({'data-download-cta':'home'});
  assert.equal(r.calls.length,2);
  assert.equal(r.calls[0].payload.page,'pricing');
  assert.equal(r.calls[0].payload.kind,'page_view');
  assert.equal(r.calls[1].payload.target,'download');
  assert.equal(r.calls[1].payload.placement,'home');
  assert.equal(r.calls[1].keepalive,true);
  assert.equal(r.calls[1].credentials,'omit');
  assert.equal(r.calls[0].payload.sessionID,r.calls[1].payload.sessionID);
  assert.notEqual(r.calls[0].payload.id,r.calls[1].payload.id);
  assert.ok(!JSON.stringify(r.calls).includes('secret@example.com'));
});
test('same-tab navigation preserves the session and recognizes navigation clicks',()=>{
  const storage=new Map(), first=runtime({storage}), next=runtime({storage});
  next.click({},undefined,true);
  assert.equal(first.calls[0].payload.sessionID,next.calls[0].payload.sessionID);
  assert.equal(next.calls[1].payload.target,'install');
  assert.equal(next.calls[1].payload.placement,'header');
});
test('privacy signals and preview sites suppress all website analytics',()=>{
  for(const options of [{dnt:'1'},{gpc:true},{hostname:'preview.pages.dev'},{hostname:'localhost'}]) {
    const r=runtime(options);r.click({'data-download-cta':'install'});assert.equal(r.calls.length,0);
  }
});
test('external destinations and unrecognized pages are not sent as click content',()=>{
  const r=runtime();r.click({},'https://external.example/secret');
  r.click({},'https://glancepreview.com/private/secret');
  assert.equal(r.calls.length,1);
});
test('whitelisted UTM parameters tag every event in the tab session and are removed from the address bar',()=>{
  const storage=new Map();
  const first=runtime({storage,search:'?utm_source=X&utm_medium=social&utm_campaign=launch&utm_content=post-1&utm_term=secret&ref=private@example.com'});
  first.click({'data-download-cta':'home'});
  for (const call of first.calls) assert.deepEqual(
    {s:call.payload.utmSource,m:call.payload.utmMedium,c:call.payload.utmCampaign,n:call.payload.utmContent},
    {s:'x',m:'social',c:'launch',n:'post-1'});
  assert.ok(!JSON.stringify(first.calls).includes('secret'));
  assert.ok(!JSON.stringify(first.calls).includes('private@example.com'));
  assert.deepEqual(first.replaced,['/en/pricing/?ref=private%40example.com#token']);
  const next=runtime({storage,search:''});
  assert.equal(next.calls[0].payload.utmSource,'x');
  assert.equal(next.replaced.length,0);
  const retagged=runtime({storage,search:'?utm_source=v2ex'});
  assert.equal(retagged.calls[0].payload.utmSource,'v2ex');
  assert.equal(retagged.calls[0].payload.utmCampaign,undefined);
});
test('invalid UTM values are dropped and untagged visits carry no channel',()=>{
  const bad=runtime({search:'?utm_source=me%40example.com&utm_campaign=https://evil.example/'});
  assert.equal(bad.calls[0].payload.utmSource,undefined);
  assert.equal(bad.calls[0].payload.utmCampaign,undefined);
  assert.ok(!JSON.stringify(bad.calls).includes('example'));
  assert.equal(runtime().calls[0].payload.utmSource,undefined);
});
test('privacy signals still clean UTM links without sending events',()=>{
  const r=runtime({dnt:'1',search:'?utm_source=x'});
  assert.equal(r.calls.length,0);
  assert.deepEqual(r.replaced,['/en/pricing/#token']);
});
