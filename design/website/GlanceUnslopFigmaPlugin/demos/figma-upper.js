/* DATA contains committed upload nodes and hashes; four upper-homepage scenes.
 * Native window chrome, text, controls, media variants and website layout stay
 * editable. Only the demonstration's content viewport is GIF media.
 * Unslop: Damir Sokolovsky, CC BY 4.0.
 */
if(figma.fileKey!=='kWvE51F9IfI3oSN6ZoxeKw')throw new Error('Wrong website file');
const page=await figma.getNodeByIdAsync('0:1');await figma.setCurrentPageAsync(page);
if(page.children.some(n=>n.name==='Glance / Upper feature films · 2026-11-14'))throw new Error('Upper film library already exists; inspect ledger');
const created=[],mutated=[],removed=[],media={},placements=[],boards=[];
const made=n=>{created.push(n.id);return n;};
const allCreated=n=>{created.push(n.id,...('findAll'in n?n.findAll().map(x=>x.id):[]));return n;};
const changed=n=>{mutated.push(n.id);return n;};
function erase(n){removed.push(n.id,...('findAll'in n?n.findAll().map(x=>x.id):[]));n.remove();}
const originals={sumi:await figma.getNodeByIdAsync('13:130'),washi:await figma.getNodeByIdAsync('13:132')};
const fontMap=new Map();
for(const root of Object.values(originals))for(const t of root.findAllWithCriteria({types:['TEXT']}))for(const s of t.getStyledTextSegments(['fontName']))fontMap.set(JSON.stringify(s.fontName),s.fontName);
for(const f of [{family:'Inter',style:'Regular'},{family:'Noto Sans SC',style:'Regular'},{family:'Geist Mono',style:'Regular'}])fontMap.set(JSON.stringify(f),f);
await Promise.all([...fontMap.values()].map(f=>figma.loadFontAsync(f)));
const vars={};for(const[k,id]of Object.entries({surface:'VariableID:13:29',line:'VariableID:13:31',ink:'VariableID:13:32',secondary:'VariableID:13:33',accent:'VariableID:13:36',canvas:'VariableID:13:39',radius:'VariableID:13:44'}))vars[k]=await figma.variables.getVariableByIdAsync(id);
const styles=await figma.getLocalTextStylesAsync();
const paint=k=>figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',vars[k]);
const titles={hero:{zh:'照片浏览',en:'Photo collection'},view:{zh:'放大查看',en:'Zoom and pan'},edit:{zh:'右键图片工具',en:'Image tools'},compare:{zh:'滑杆对比',en:'Compare images'}};
const captions={hero:{zh:'打开、切换、查看，让每一张照片留在眼前',en:'Open, switch and inspect the whole collection.'},view:{zh:'播放演示：放大细节，移动视口',en:'Play: zoom in and pan across the image.'},edit:{zh:'播放演示：选择工具，确认输入与点数',en:'Play: choose a tool, then check the input and credits.'},compare:{zh:'播放演示：并排查看，再拖动滑杆',en:'Play: view side by side, then drag the divider.'}};
async function text(parent,name,value,lang,size=12,width=220,role='secondary'){
 const t=made(figma.createText());parent.appendChild(t);t.name=name;t.fontName={family:lang==='zh'?'Noto Sans SC':'Inter',style:'Regular'};t.fontSize=size;t.lineHeight={unit:'PIXELS',value:size>=20?32:20};t.characters=value;t.textAutoResize='HEIGHT';t.resize(width,20);t.fills=[paint(role)];
 const style=styles.find(s=>s.name==='Glance/'+[t.fontName.family,size,'Regular',size>=20?32:20].join('/'));if(style)await t.setTextStyleIdAsync(style.id);return t;
}
function radius(n){for(const key of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])n.setBoundVariable(key,vars.radius);}
function image(parent,name,hash,w,h){const n=made(figma.createRectangle());parent.appendChild(n);n.name=name;n.resize(w,h);n.fills=[{type:'IMAGE',imageHash:hash,scaleMode:'FIT'}];return n;}
function row(parent,name,w,h){const n=made(figma.createAutoLayout('HORIZONTAL'));parent.appendChild(n);n.name=name;n.resize(w,h);n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.counterAxisAlignItems='CENTER';n.fills=[];return n;}
async function playControl(parent,lang,playing,mobile){
 const b=row(parent,playing?'Pause demonstration':'Play demonstration',mobile?96:288,mobile?28:52);b.paddingLeft=mobile?8:16;b.paddingRight=mobile?8:16;b.itemSpacing=mobile?6:12;b.fills=[paint('surface')];b.strokes=[paint('line')];b.strokeWeight=1;b.strokesIncludedInLayout=false;radius(b);
 const svg=playing?'<path d="M8 5v18M20 5v18" stroke="currentColor" stroke-width="5"/>':'<path d="m7 4 19 10L7 24Z" fill="currentColor"/>';
 const icon=allCreated(figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 28 28">'+svg+'</svg>'));b.appendChild(icon);icon.name=playing?'Pause':'Play';if(mobile)icon.rescale(.5);
 for(const n of icon.findAll(n=>'fills'in n||'strokes'in n)){if('fills'in n&&Array.isArray(n.fills)&&n.fills.length)n.fills=[paint('ink')];if('strokes'in n&&Array.isArray(n.strokes)&&n.strokes.length)n.strokes=[paint('ink')];}
 await text(b,'Playback label',lang==='zh'?(playing?'暂停':'播放演示'):(playing?'Pause':'Play demo'),lang,mobile?11:22,mobile?60:200,'ink');
 return b;
}
const library=made(figma.createFrame());page.appendChild(library);library.name='Glance / Upper feature films · 2026-11-14';library.x=17200;library.y=160;library.resize(4200,16640);library.fills=[];library.clipsContent=false;
for(let index=0;index<DATA.assets.length;index++){
 const a=DATA.assets[index],mobile=a.kind==='mobile',variants=[];
 for(const state of ['Poster','Playing']){
  const playing=state==='Playing',c=made(figma.createComponent());c.name='Playback='+state;c.resize(mobile?342:1440,mobile?384:900);c.fills=[paint('canvas')];c.strokes=[paint('line')];c.strokeWeight=1;c.clipsContent=true;radius(c);c.setExplicitVariableModeForCollection('VariableCollectionId:13:3',a.theme==='sumi'?'13:1':'13:2');
  if(!mobile){
   const base=allCreated(originals[a.theme].createInstance());c.appendChild(base);base.name='Native Glance window chrome';
   const images=base.findAll(n=>'fills'in n&&Array.isArray(n.fills)&&n.fills.some(p=>p.type==='IMAGE'));
   for(let i=0;i<images.length;i++){if(i===0)images[i].visible=false;else images[i].fills=[{type:'IMAGE',imageHash:DATA.photos[(i-1)%DATA.photos.length].hash,scaleMode:'FILL'}];}
   const tx=base.findAllWithCriteria({types:['TEXT']});
   if(tx[0]){if(a.lang==='zh')tx[0].fontName={family:'Noto Sans SC',style:'Regular'};tx[0].characters=titles[a.key][a.lang];}if(tx[1]){if(a.lang==='zh')tx[1].fontName={family:'Noto Sans SC',style:'Regular'};tx[1].characters=a.lang==='zh'?'操作演示 · 8 秒':'8s · Product demo';}
   if(tx[2])tx[2].visible=false;if(tx[3])tx[3].visible=false;
   const film=image(c,'Animated content viewport',playing?a.gifHash:a.posterHash,1312,728);film.x=64;film.y=64;
   const play=await playControl(c,a.lang,playing,false);play.x=1080;play.y=824;
  }else{
   c.layoutMode='VERTICAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.itemSpacing=0;c.strokesIncludedInLayout=false;
   const header=row(c,'Native compact window header',342,32);header.paddingLeft=12;header.paddingRight=12;header.itemSpacing=12;header.fills=[paint('surface')];
   const dots=row(header,'Window controls',36,10);dots.itemSpacing=4;
   for(let j=0;j<3;j++){const dot=made(figma.createEllipse());dots.appendChild(dot);dot.resize(8,8);dot.fills=[paint('line')];}
   await text(header,'Window title','Glance · '+titles[a.key][a.lang],a.lang,11,252,'secondary');
   image(c,'Animated content viewport',playing?a.gifHash:a.posterHash,342,314);
   const footer=row(c,'Native playback controls',342,38);footer.paddingLeft=12;footer.paddingRight=12;footer.itemSpacing=8;footer.fills=[paint('surface')];
   await text(footer,'Duration',a.lang==='zh'?'0:08 · 操作演示':'0:08 · Product demo',a.lang,11,210,'secondary');
   await playControl(footer,a.lang,playing,true);
  }
  variants.push(c);
 }
 const set=made(figma.combineAsVariants(variants,library));set.name='Glance / Upper film / '+[a.key,a.lang,a.theme,a.kind].join(' / ');set.fills=[];set.strokes=[];
 const cw=mobile?342:1440,ch=mobile?384:900;variants.forEach((c,i)=>{c.x=12+i*(cw+24);c.y=12;});set.resizeWithoutConstraints(cw*2+48,ch+24);set.x=mobile?3080:0;set.y=Math.floor(index/2)*1040;
 for(let i=0;i<2;i++)await variants[i].setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:variants[1-i].id,navigation:'CHANGE_TO',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.14},resetVideoPosition:true}]}]);
 set.description='Eight-second captioned demonstration in the content viewport. Native window chrome and playback controls stay editable. Click to play/pause in Presentation View. Uses supplied photos; no live app recording or cloud task. Unslop: Damir Sokolovsky, CC BY 4.0.';
 media[[a.key,a.lang,a.theme,a.kind].join('/')]= {set:set.id,poster:variants[0].id,playing:variants[1].id,gifHash:a.gifHash,posterHash:a.posterHash};
}
function findSlot(section,key,mobile){
 const name=key==='hero'||(key==='compare'&&mobile)?(mobile?'Product / Mobile compare detail':'Product / Native latest Image Inspect'):key==='edit'?'Widget menu / Latest design language':mobile?'Portrait sample / Original':'Product / Native latest Figma frame';
 const expected=key==='compare'&&!mobile?'Product / Native latest Figma frame':name;
 return section.findOne(n=>n.name===expected&&n.type==='FRAME'&&(mobile?n.width<380:n.width>700));
}
for(const id of ['15:2','15:969','15:1545','15:2512','15:3216','15:4183','15:4759','15:5726']){
 const board=await figma.getNodeByIdAsync(id),lang=board.name.includes('中文')?'zh':'en',theme=board.name.startsWith('Washi')?'washi':'sumi',mobile=board.width<500;let count=0;
 for(const[key,sectionName]of [['hero','02 / Hero'],['view','04.1 / '],['edit','04.2 / '],['compare','04.3 / ']]){
  const section=board.findOne(n=>key==='hero'?n.name===sectionName:n.name.startsWith(sectionName));if(!section)throw new Error('Missing section '+key+' '+id);
  const slot=findSlot(section,key,mobile);if(!slot)throw new Error('Missing upper media slot '+key+' '+id);
  const oldHeight=slot.height,parent=slot.parent;for(const n of [...slot.children])erase(n);
  slot.layoutMode='NONE';slot.fills=[];slot.strokes=[];slot.clipsContent=false;slot.resize(mobile?342:slot.width,mobile?384:slot.height);changed(slot);
  const def=media[[key,lang,theme,mobile?'mobile':'desktop'].join('/')],component=await figma.getNodeByIdAsync(def.poster),instance=allCreated(component.createInstance());slot.appendChild(instance);instance.name='Upper demo / '+key+' / '+lang;
  if(!mobile)instance.rescale(slot.width/1440);instance.x=0;instance.y=0;
  if(mobile&&oldHeight!==384){const delta=384-oldHeight;parent.resize(parent.width,parent.height+delta);section.resize(section.width,section.height+delta);section.parent.resize(section.parent.width,section.parent.height+delta);changed(parent);changed(section);changed(section.parent);}
  const caption=section.findOne(n=>n.type==='TEXT'&&(n.name==='Product caption'||n.name==='Mobile product caption'));
  if(caption){for(const s of caption.getStyledTextSegments(['fontName']))await figma.loadFontAsync(s.fontName);caption.characters=captions[key][lang];changed(caption);}
  placements.push({boardId:id,scene:key,slotId:slot.id,instanceId:instance.id,componentId:def.poster,width:instance.width,height:instance.height});count++;
 }
 changed(board);boards.push({id,name:board.name,width:board.width,height:board.height,upperFilms:count,widgetCards:board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Demo / ')).length});
}
const sumiTop=(await figma.getNodeByIdAsync('15:2')).y;const washiY=sumiTop+Math.max(...boards.filter(b=>b.name.startsWith('Sumi')).map(b=>b.height))+480;
for(const n of page.children.filter(n=>n.name.startsWith('Washi · '))){n.y=washiY;changed(n);}
for(const id of DATA.transferNodeIds){const n=await figma.getNodeByIdAsync(id);if(n)erase(n);}
const selected=await figma.getNodeByIdAsync('15:1574');page.selection=[selected];figma.viewport.scrollAndZoomIntoView(page.selection);
// Prefix/range encoding returns every affected ID without oversized responses.
const pack=ids=>{const map={};for(const id of new Set(ids)){const i=id.lastIndexOf(':')+1,p=id.slice(0,i);(map[p]??=[]).push(id.slice(i));}for(const[p,values]of Object.entries(map)){const sorted=[...new Set(values)].sort((a,b)=>Number(a)-Number(b)),out=[];let start=sorted[0],last=start;for(const v of sorted.slice(1)){if(Number(v)===Number(last)+1)last=v;else{out.push(start===last?start:start+'-'+last);start=last=v;}}if(start!==undefined)out.push(start===last?start:start+'-'+last);map[p]=out.join(',');}return map;};
if(boards.some(b=>b.upperFilms!==4||b.widgetCards!==4))throw new Error('Expected four upper films and unchanged four Widget cards on every homepage');
return {createdNodeIdRangesByPrefix:pack(created),mutatedNodeIds:[...new Set(mutated)],removedNodeIdRangesByPrefix:pack(removed),media,placements,boards,libraryId:library.id,washiY,counts:{upperScenes:4,localizedThemeSizeFilms:32,playbackVariants:64,homepages:8,upperFilmPlacements:32,newSourcePortraits:8,cloudTasks:0}};
