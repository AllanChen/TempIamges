/* Add Japanese/German versions of the current Widget promotion, including media
 * captions, regional prices and four-language navigation. Existing EN/ZH copy is
 * preserved. Unslop: Damir Sokolovsky, CC BY 4.0.
 */
if(figma.fileKey!=='kWvE51F9IfI3oSN6ZoxeKw')throw new Error('Wrong website file');
const page=await figma.getNodeByIdAsync('0:1');await figma.setCurrentPageAsync(page);
if(page.children.some(n=>n.name==='Glance / Japanese & German localization'))throw new Error('Localization already committed; inspect its ledger');
const created=[],mutated=[],removed=[],styleIds=[],media={},copies={},newBoards=[],switchers={},validation=[];
const made=n=>{created.push(n.id);return n;};
const tracked=n=>{created.push(n.id,...('findAll'in n?n.findAll().map(c=>c.id):[]));return n;};
const changed=n=>{mutated.push(n.id);return n;};
function erase(n){removed.push(n.id,...('findAll'in n?n.findAll().map(c=>c.id):[]));n.remove();}
const norm=s=>s.replace(/\s+/g,' ').trim();
const existing=page.children.filter(n=>n.type==='FRAME'&&/^(Sumi|Washi) · Home \/ (English|中文) \/ /.test(n.name));
const allFonts=new Map();for(const b of existing)for(const t of b.findAllWithCriteria({types:['TEXT']}))for(const s of t.getStyledTextSegments(['fontName']))allFonts.set(s.fontName.family+'/'+s.fontName.style,{family:s.fontName.family,style:s.fontName.style});
for(const family of ['Noto Sans JP','Noto Sans SC','Inter'])for(const style of ['Regular','Medium'])allFonts.set(family+'/'+style,{family,style});
await Promise.all([...allFonts.values()].map(f=>figma.loadFontAsync(f)));
const vars={};for(const[k,id]of Object.entries({surface:'VariableID:13:29',raised:'VariableID:13:30',line:'VariableID:13:31',ink:'VariableID:13:32',secondary:'VariableID:13:33',radius:'VariableID:13:43'}))vars[k]=await figma.variables.getVariableByIdAsync(id);
const paint=k=>figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',vars[k]);
const styles=await figma.getLocalTextStylesAsync();
function round(n){for(const k of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])n.setBoundVariable(k,vars.radius);}
function sourceText(value,lang){const entry=DATA.copy[norm(value)];return entry?entry[lang]:null;}
async function setText(t,value,lang){
 for(const s of t.getStyledTextSegments(['fontName']))await figma.loadFontAsync(s.fontName);
 const sourceFont=t.fontName;
 const family=lang==='ja'&&/[\u3040-\u30ff\u3400-\u9fff]/.test(value)&&sourceFont.family!=='Shippori Mincho'?'Noto Sans JP':sourceFont.family;
 const style=sourceFont.style==='Medium'?'Medium':'Regular';await figma.loadFontAsync({family,style});
 if(family!==sourceFont.family){
  const size=t.fontSize,line=t.lineHeight,key='Glance/i18n/ja/'+[family,size,style,JSON.stringify(line)].join('/');let ts=styles.find(s=>s.name===key);
  if(!ts){ts=figma.createTextStyle();ts.name=key;ts.fontName={family,style};ts.fontSize=size;ts.lineHeight=line;styles.push(ts);styleIds.push(ts.id);}
  await t.setTextStyleIdAsync(ts.id);
 }
 const prop=t.componentPropertyReferences?.characters;let owner=t.parent;
 while(owner&&!['INSTANCE','COMPONENT'].includes(owner.type)&&owner!==page)owner=owner.parent;
 if(prop&&owner?.type==='INSTANCE')owner.setProperties({[prop]:value});else if(prop&&owner?.type==='COMPONENT')owner.editComponentProperty(prop,{defaultValue:value});else t.characters=value;
 t.textAutoResize='HEIGHT';if(t.parent&&'layoutMode'in t.parent&&t.parent.layoutMode!=='NONE')t.layoutSizingVertical='HUG';
 changed(t);
}
const area=made(figma.createFrame());page.appendChild(area);area.name='Glance / Japanese & German localization';area.x=25600;area.y=160;area.resize(4200,10200);area.fills=[];area.clipsContent=false;
let mediaY=0;
for(const a of DATA.assets){
 const source=a.key==='compare'?DATA.sources.compare[['compare','en',a.theme,a.kind].join('/')]:DATA.sources.media[a.key+'/en'];
 const variants=[];
 for(const state of ['Poster','Playing']){
  const original=await figma.getNodeByIdAsync(state==='Poster'?source.poster:source.playing),c=tracked(original.clone());area.appendChild(c);mutated.push(original.parent.id);c.name='Playback='+state;
  const film=c.findOne(n=>n.name==='Animated content viewport'||n.name==='Film');if(!film)throw new Error('Missing media viewport');film.fills=[{type:'IMAGE',imageHash:state==='Poster'?a.posterHash:a.gifHash,scaleMode:'FIT'}];
  for(const t of c.findAllWithCriteria({types:['TEXT']})){
   let value=sourceText(t.characters,a.lang);if(t.name==='Playback label'&&a.lang==='de'&&a.kind==='mobile'&&state==='Poster')value='Abspielen';
   if(value!==null)await setText(t,value,a.lang);
  }
  variants.push(c);
 }
 const set=made(figma.combineAsVariants(variants,area));set.name='Glance / Localized film / '+[a.key,a.lang,a.theme,a.kind].join(' / ');set.fills=[];set.strokes=[];
 const w=variants[0].width,h=variants[0].height;variants.forEach((c,i)=>{c.x=12+i*(w+24);c.y=12;});set.resizeWithoutConstraints(w*2+48,h+24);set.x=0;set.y=mediaY;mediaY+=h+88;
 for(let i=0;i<2;i++)await variants[i].setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:variants[1-i].id,navigation:'CHANGE_TO',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.14},resetVideoPosition:true}]}]);
 set.description='Japanese/German captioned version of the existing real-result Widget film. Click to play/pause. Native window chrome remains editable. Unslop: Damir Sokolovsky, CC BY 4.0.';
 media[[a.key,a.lang,a.theme,a.kind].join('/')]= {set:set.id,poster:variants[0].id,playing:variants[1].id,gifHash:a.gifHash,posterHash:a.posterHash};
}
for(const lang of ['ja','de'])for(const mobile of [false,true]){
 const original=await figma.getNodeByIdAsync(DATA.sources.copies['en/'+(mobile?'Mobile':'Desktop')].id),c=tracked(original.clone());area.appendChild(c);mutated.push(original.parent.id);c.name='Glance / Widget story copy / '+lang+' / '+(mobile?'Mobile':'Desktop');c.x=3200;c.y=5000+Object.keys(copies).length*440;
 for(const t of c.children.filter(n=>n.type==='TEXT')){const value=sourceText(t.characters,lang);if(value===null)throw new Error('Missing copy translation');await setText(t,value,lang);}
 const definitions=c.componentPropertyDefinitions,keys={};for(const name of ['Meta','Title','Body'])keys[name]=Object.keys(definitions).find(k=>k.startsWith(name+'#'));
 copies[lang+'/'+(mobile?'Mobile':'Desktop')]={id:c.id,keys};
}
const sourceBoards=[{id:'15:2',theme:'sumi',mobile:false},{id:'15:969',theme:'sumi',mobile:true},{id:'15:3216',theme:'washi',mobile:false},{id:'15:4183',theme:'washi',mobile:true}];
const originalMax=Math.max(...existing.map(b=>b.y+b.height));
function underNamedInstance(t,prefix,stop){for(let n=t.parent;n&&n!==stop;n=n.parent)if(n.type==='INSTANCE'&&n.name.startsWith(prefix))return true;return false;}
function insideInstance(n,stop){for(let p=n.parent;p&&p!==stop;p=p.parent)if(p.type==='INSTANCE')return true;return false;}
function depth(n,stop){let d=0;for(let p=n.parent;p&&p!==stop;p=p.parent)d++;return d;}
function reflow(board,minimums){
 const frames=board.findAll(n=>n.type==='FRAME'&&n.layoutMode!=='NONE'&&!insideInstance(n,board)).sort((a,b)=>depth(b,board)-depth(a,board));
 for(const n of frames){n.minHeight=Math.max(n.minHeight??0,minimums.get(n.id)??n.height);if(n.layoutMode==='VERTICAL')n.primaryAxisSizingMode='AUTO';else n.counterAxisSizingMode='AUTO';n.layoutSizingVertical='HUG';changed(n);}
 board.primaryAxisSizingMode='AUTO';changed(board);
}
for(const lang of ['ja','de'])for(const s of sourceBoards){
 const source=await figma.getNodeByIdAsync(s.id),board=tracked(source.clone());page.appendChild(board);board.name=(s.theme==='sumi'?'Sumi':'Washi')+' · Home / '+(lang==='ja'?'日本語':'Deutsch')+' / '+(s.mobile?'Mobile 390':'Desktop 1440');
 const originals=[source,...source.findAll()],clones=[board,...board.findAll()];if(originals.length!==clones.length)throw new Error('Clone structure differs');
 const map=new Map(originals.map((n,i)=>[n.id,clones[i].id])),minimums=new Map(clones.filter(n=>n.type==='FRAME').map(n=>[n.id,n.height]));
 for(const n of clones.filter(n=>'reactions'in n&&n.reactions.length)){
  let differs=false;const reactions=JSON.parse(JSON.stringify(n.reactions)).map(r=>{const actions=(r.actions??(r.action?[r.action]:[])).map(a=>{if(a.type==='NODE'&&map.has(a.destinationId)){a.destinationId=map.get(a.destinationId);differs=true;}if(a.type==='URL'&&/^https:\/\/glancepreview\.com\/en\/$/.test(a.url)){a.url='https://glancepreview.com/'+lang+'/';differs=true;}return a;});return{trigger:r.trigger,actions};});
  if(differs){await n.setReactionsAsync(reactions);changed(n);}
 }
 for(const old of board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Promotion copy / '))){
  const def=copies[lang+'/'+(s.mobile?'Mobile':'Desktop')],fresh=tracked((await figma.getNodeByIdAsync(def.id)).createInstance()),values={};
  for(const t of old.findAllWithCriteria({types:['TEXT']})){const role=t.name==='Widget metadata'?'Meta':t.name==='Widget headline'?'Title':'Body';values[def.keys[role]]=sourceText(t.characters,lang);if(values[def.keys[role]]===null)throw new Error('Missing story override');}
  fresh.setProperties(values);fresh.name=old.name;old.parent.insertChild(old.parent.children.indexOf(old),fresh);erase(old);
 }
 for(const old of board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Promo media / '))){
  const key=old.name.slice('Promo media / '.length),lookup=key==='remove-objects'?['compare',lang,s.theme,s.mobile?'mobile':'desktop'].join('/'):[key,lang,'shared','widget'].join('/'),def=media[lookup];
  if(!def)throw new Error('Missing localized film '+lookup);
  const c=await figma.getNodeByIdAsync(def.poster),fresh=tracked(c.createInstance());fresh.name=old.name;fresh.rescale((s.mobile?342:736)/c.width);old.parent.insertChild(old.parent.children.indexOf(old),fresh);erase(old);
 }
 const untranslated=[];let translated=0;
 for(const t of board.findAllWithCriteria({types:['TEXT']})){
  if(underNamedInstance(t,'Promotion copy / ',board)||underNamedInstance(t,'Promo media / ',board))continue;
  const value=sourceText(t.characters,lang);if(value===null){untranslated.push({id:t.id,value:t.characters});continue;}await setText(t,value,lang);translated++;
 }
 if(untranslated.length)throw new Error('Missing translations: '+JSON.stringify(untranslated));
 reflow(board,minimums);
 newBoards.push({id:board.id,lang,theme:s.theme,mobile:s.mobile,sourceId:source.id,translatedTexts:translated});
}
// Place the additional locale rows beneath the existing EN/ZH compositions.
let nextY=originalMax+480;
for(const theme of ['sumi','washi']){
 for(const b of newBoards.filter(b=>b.theme===theme)){const n=await figma.getNodeByIdAsync(b.id);n.x=b.lang==='ja'?(b.mobile?1696:160):(b.mobile?3776:2240);n.y=nextY;changed(n);}
 nextY+=Math.max(...newBoards.filter(b=>b.theme===theme).map(b=>figma.getNodeById(b.id).height))+480;
}
const allBoards=existing.map(b=>({id:b.id,lang:b.name.includes('中文')?'zh':'en',theme:b.name.startsWith('Washi')?'washi':'sumi',mobile:b.width<500})).concat(newBoards);
async function label(parent,value,family='Inter',style='Regular',width=124){
 const t=made(figma.createText());parent.appendChild(t);t.name='Locale label';t.fontName={family,style};t.fontSize=14;t.lineHeight={unit:'PIXELS',value:20};t.characters=value;t.resize(width,20);t.textAutoResize='HEIGHT';t.layoutSizingVertical='HUG';t.fills=[paint('ink')];return t;
}
for(const theme of ['sumi','washi'])for(const mobile of [false,true]){
 const variants=[],index=Object.keys(switchers).length,byLang={};
 for(const lang of ['zh','en','ja','de'])for(const state of ['Closed','Open']){
  const c=made(figma.createComponent());area.appendChild(c);c.name='Locale='+lang+', State='+state;c.layoutMode='HORIZONTAL';c.resize(44,32);c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.primaryAxisAlignItems='CENTER';c.counterAxisAlignItems='CENTER';c.fills=[];c.clipsContent=false;c.setExplicitVariableModeForCollection('VariableCollectionId:13:3',theme==='sumi'?'13:1':'13:2');
  await label(c,({zh:'中文',en:'EN',ja:'JA',de:'DE'})[lang]+' ▾',lang==='zh'?'Noto Sans SC':'Inter','Medium',44);
  if(state==='Open'){
   const panel=made(figma.createAutoLayout('VERTICAL'));c.appendChild(panel);panel.name='Language menu';panel.resize(164,176);panel.primaryAxisSizingMode='FIXED';panel.counterAxisSizingMode='FIXED';panel.layoutPositioning='ABSOLUTE';panel.x=-120;panel.y=36;panel.paddingTop=8;panel.paddingBottom=8;panel.paddingLeft=8;panel.paddingRight=8;panel.fills=[paint('surface')];panel.strokes=[paint('line')];panel.strokeWeight=1;panel.strokesIncludedInLayout=false;panel.clipsContent=false;round(panel);
   for(const item of ['zh','en','ja','de']){
    const row=made(figma.createAutoLayout('HORIZONTAL'));panel.appendChild(row);row.name='Language / '+item;row.resize(148,40);row.primaryAxisSizingMode='FIXED';row.counterAxisSizingMode='FIXED';row.counterAxisAlignItems='CENTER';row.paddingLeft=12;row.paddingRight=12;row.fills=item===lang?[paint('raised')]:[];round(row);
    await label(row,({zh:'中文',en:'English',ja:'日本語',de:'Deutsch'})[item],item==='zh'?'Noto Sans SC':item==='ja'?'Noto Sans JP':'Inter',item===lang?'Medium':'Regular',124);
    const destination=allBoards.find(b=>b.lang===item&&b.theme===theme&&b.mobile===mobile);if(!destination)throw new Error('Missing language destination');
    await row.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:destination.id,navigation:'NAVIGATE',transition:null,resetScrollPosition:true}]}]);
   }
  }
  variants.push(c);(byLang[lang]??={})[state.toLowerCase()]=c.id;
 }
 const set=made(figma.combineAsVariants(variants,area));set.name='Glance / Language selector / '+theme+' / '+(mobile?'Mobile':'Desktop');set.fills=[];set.strokes=[];set.clipsContent=false;set.x=3200;set.y=index*1160;
 variants.forEach((c,i)=>{c.x=140+(i%2)*240;c.y=12+Math.floor(i/2)*260;});set.resizeWithoutConstraints(580,1040);
 for(const pair of Object.values(byLang))for(const[from,to]of [[pair.closed,pair.open],[pair.open,pair.closed]])await (await figma.getNodeByIdAsync(from)).setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:to,navigation:'CHANGE_TO',transition:null}]}]);
 set.description='Four-language navigation preserving theme and viewport. English, Chinese, Japanese and German destinations are local homepage boards.';
 switchers[theme+'/'+(mobile?'mobile':'desktop')]={set:set.id,byLang};
}
for(const b of allBoards){
 const board=await figma.getNodeByIdAsync(b.id),nav=board.findOne(n=>n.name==='01 / Navigation'),old=nav.findOne(n=>n.type==='TEXT'&&['Link / 中文','Link / EN'].includes(n.name));if(!old)throw new Error('Missing legacy locale link '+b.id);
 const parent=old.parent;erase(old);parent.resize(44,40);parent.layoutMode='VERTICAL';parent.paddingTop=4;parent.paddingBottom=4;parent.paddingLeft=0;parent.paddingRight=0;parent.primaryAxisSizingMode='FIXED';parent.counterAxisSizingMode='FIXED';parent.clipsContent=false;changed(parent);
 const def=switchers[b.theme+'/'+(b.mobile?'mobile':'desktop')].byLang[b.lang],control=tracked((await figma.getNodeByIdAsync(def.closed)).createInstance());parent.appendChild(control);control.name='Language selector / '+b.lang;
 if(newBoards.some(n=>n.id===b.id)){
  const films=board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Promo media / '));
  const overlap=[];for(const c of board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Promotion copy / '))){const ts=c.findAllWithCriteria({types:['TEXT']}).sort((x,y)=>x.y-y.y);for(let i=1;i<ts.length;i++)if(ts[i].y<ts[i-1].y+ts[i-1].height+15.9)overlap.push(c.id);}
  validation.push({id:b.id,lang:b.lang,theme:b.theme,mobile:b.mobile,width:board.width,height:board.height,heroId:board.findOne(n=>n.name==='02 / Hero').id,widgetFilms:films.length,missingFonts:board.findAllWithCriteria({types:['TEXT']}).filter(t=>t.hasMissingFont).length,copyOverlaps:overlap,localeSwitcher:control.id});
 }
}
for(const id of DATA.transferNodeIds){const n=await figma.getNodeByIdAsync(id);if(n)erase(n);}
if(validation.some(v=>v.widgetFilms!==4||v.missingFonts||v.copyOverlaps.length))throw new Error('Localized homepage validation failed '+JSON.stringify(validation));
const first=await figma.getNodeByIdAsync(newBoards.find(b=>b.lang==='ja'&&b.theme==='sumi'&&!b.mobile).id);page.selection=[first];figma.viewport.scrollAndZoomIntoView(page.selection);
const pack=ids=>{const m={};for(const id of new Set(ids)){const i=id.lastIndexOf(':')+1,p=id.slice(0,i);(m[p]??=[]).push(id.slice(i));}for(const[p,v]of Object.entries(m)){const a=[...new Set(v)].sort((x,y)=>Number(x)-Number(y)),out=[];let s=a[0],l=s;for(const x of a.slice(1)){if(Number(x)===Number(l)+1)l=x;else{out.push(s===l?s:s+'-'+l);s=l=x;}}if(s!==undefined)out.push(s===l?s:s+'-'+l);m[p]=out.join(',');}return m;};
return {createdNodeIdRangesByPrefix:pack(created),mutatedNodeIdRangesByPrefix:pack(mutated),removedNodeIdRangesByPrefix:pack(removed),createdTextStyleIds:styleIds,libraryId:area.id,media,copies,switchers,boards:validation,counts:{newHomepages:8,totalHomepages:16,languages:4,localizedFilmAssets:14,playbackVariants:28,localeSelectorVariants:32,localeSelectorPlacements:16,widgetFilmsPerHomepage:4},regionalPrices:{JPY:{personal:1480,team:2980,credits600:480},EUR:{personal:9.99,team:19.99,credits600:2.99}}};
