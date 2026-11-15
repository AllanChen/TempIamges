// Theme state checks using a minimal DOM, without browser/UI automation.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
function runtime({saved, systemLight=false, blocked=false, languageLinks=[]}={}) {
  const attrs = {'data-lang':'en'}, handlers={}, queries={}, buttonAttrs={};
  const button={setAttribute:(k,v)=>buttonAttrs[k]=v,getAttribute:k=>buttonAttrs[k],addEventListener:(k,v)=>handlers['button:'+k]=v};
  const meta={content:''};
  const context={document:{documentElement:{setAttribute:(k,v)=>attrs[k]=v,getAttribute:k=>attrs[k]},
    querySelector:s=>s==='.theme-toggle'?button:meta,querySelectorAll:s=>s==='.lang-option'?languageLinks:[],getElementById:()=>null,
    addEventListener:(k,v)=>handlers[k]=v,dispatchEvent:e=>handlers[e.type]?.(e)},
    localStorage:{getItem:()=>{if(blocked)throw Error('blocked');return saved;},setItem:(k,v)=>{if(blocked)throw Error('blocked');saved=v;}},
    window:{matchMedia:s=>queries[s]||(queries[s]={matches:s.includes('color-scheme')&&systemLight,addEventListener:(k,v)=>handlers[s]=v}),addEventListener:(k,v)=>handlers[k]=v},Event:class{constructor(type){this.type=type}}};
  for(const file of ['theme-init.js','presentation.js'])vm.runInNewContext(fs.readFileSync(__dirname+'/src/assets/'+file,'utf8'),context);
  return {attrs,handlers,buttonAttrs,meta,queries,document:context.document,get saved(){return saved;}};
}
test('initial theme follows the system and changes when no preference is saved',()=>{
  const r=runtime({systemLight:true});assert.equal(r.attrs['data-theme'],'light');
  assert.equal(r.meta.content,'#faf9f5');
  r.queries['(prefers-color-scheme: light)'].matches=false;
  r.handlers['(prefers-color-scheme: light)']();assert.equal(r.attrs['data-theme'],'dark');
});
test('header toggle saves the selection and ignores later system changes',()=>{
  const r=runtime({saved:'dark',systemLight:true});assert.equal(r.attrs['data-theme'],'dark');
  r.handlers['button:click']();assert.equal(r.saved,'light');assert.equal(r.attrs['data-theme'],'light');
  assert.equal(r.buttonAttrs['aria-label'],'Switch to dark');assert.equal(r.buttonAttrs['aria-pressed'],'true');
  r.queries['(prefers-color-scheme: light)'].matches=false;r.handlers['(prefers-color-scheme: light)']();
  assert.equal(r.attrs['data-theme'],'light');
});
test('blocked storage still permits switching and cross-tab reset returns to system',()=>{
  const r=runtime({blocked:true});r.handlers['button:click']();assert.equal(r.attrs['data-theme'],'light');
  r.handlers.storage({key:'glance.theme',newValue:null});assert.equal(r.attrs['data-theme'],'dark');
});
test('manual language links remember only a supported language choice',()=>{
  for (const [hreflang,expected] of [['zh-Hans','zh'],['en','en'],['ja','ja'],['de','de'],['fr',null]]) {
    let click;
    const link={getAttribute:()=>hreflang,addEventListener:(_,fn)=>{click=fn;}};
    const r=runtime({languageLinks:[link]});
    assert.equal(r.document.cookie,undefined); // Inferred language is not persisted.
    click();
    assert.equal(r.document.cookie,expected ? 'glance.language='+expected+'; Path=/; Max-Age=31536000; SameSite=Lax; Secure' : undefined);
  }
});
