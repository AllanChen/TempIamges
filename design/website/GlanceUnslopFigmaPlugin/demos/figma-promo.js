/* Widget-first promotional homepage. Existing media and foundations are reused.
 * Four Widget stories, with comparison woven into the second story.
 * Unslop: Damir Sokolovsky, CC BY 4.0.
 */
if(figma.fileKey!=='kWvE51F9IfI3oSN6ZoxeKw')throw new Error('Wrong website file');
const page=await figma.getNodeByIdAsync('0:1');await figma.setCurrentPageAsync(page);
if(page.children.some(n=>n.name==='Glance / Widget promotion assets'))throw new Error('Promotion revision already exists; inspect the committed ledger');
const created=[],mutated=[],removed=[],copies={},decks={},boards=[],stories=[];
const made=n=>{created.push(n.id);return n;};
const tracked=n=>{created.push(n.id,...('findAll'in n?n.findAll().map(x=>x.id):[]));return n;};
const changed=n=>{mutated.push(n.id);return n;};
function erase(n){removed.push(n.id,...('findAll'in n?n.findAll().map(x=>x.id):[]));n.remove();}
const ids=['15:2','15:969','15:1545','15:2512','15:3216','15:4183','15:4759','15:5726'];
const roots=await Promise.all(ids.map(id=>figma.getNodeByIdAsync(id)));
const sources={sumi:await figma.getNodeByIdAsync('13:130'),washi:await figma.getNodeByIdAsync('13:132')};
const fonts=new Map();for(const root of [...roots,...Object.values(sources)])for(const n of root.findAllWithCriteria({types:['TEXT']}))for(const s of n.getStyledTextSegments(['fontName']))fonts.set(s.fontName.family+'/'+s.fontName.style,{family:s.fontName.family,style:s.fontName.style});
await Promise.all([...fonts.values()].map(f=>figma.loadFontAsync(f)));
const vars={};for(const[k,id]of Object.entries({surface:'VariableID:13:29',line:'VariableID:13:31',ink:'VariableID:13:32',secondary:'VariableID:13:33',canvas:'VariableID:13:39',radius:'VariableID:13:44'}))vars[k]=await figma.variables.getVariableByIdAsync(id);
const spaces={};for(const[k,id]of Object.entries(DATA.spaces))spaces[k]=await figma.variables.getVariableByIdAsync(id);
const styles=await figma.getLocalTextStylesAsync();const madeStyles=[];
const paint=k=>figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',vars[k]);
function radius(n){for(const p of ['topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])n.setBoundVariable(p,vars.radius);}
function stack(parent,name,direction,w,h=100){const n=made(figma.createAutoLayout(direction));parent.appendChild(n);n.name=name;n.resize(w,h);n.fills=[];n.clipsContent=false;n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';return n;}
async function text(parent,name,value,lang,size=16,width=448,role='secondary',display=false){
 const family=display?(lang==='zh'?'Noto Serif SC':'Shippori Mincho'):(lang==='zh'?'Noto Sans SC':size===12?'Geist Mono':'Inter'),line=size>=28?40:size===12?20:24;
 await figma.loadFontAsync({family,style:'Regular'});
 const t=made(figma.createText());parent.appendChild(t);t.name=name;t.fontName={family,style:'Regular'};t.fontSize=size;t.lineHeight={unit:'PIXELS',value:line};t.characters=value;t.textAutoResize='HEIGHT';t.resize(width,line);t.fills=[paint(role)];
 const key='Glance/'+[family,size,'Regular',line].join('/');let style=styles.find(s=>s.name===key);
 if(!style){style=figma.createTextStyle();style.name=key;style.fontName={family,style:'Regular'};style.fontSize=size;style.lineHeight={unit:'PIXELS',value:line};styles.push(style);madeStyles.push(style.id);}
 await t.setTextStyleIdAsync(style.id);t.textAutoResize='HEIGHT';t.layoutSizingVertical='HUG';return t;
}
function photo(parent,name,hash,w,h){const n=made(figma.createRectangle());parent.appendChild(n);n.name=name;n.resize(w,h);n.fills=[{type:'IMAGE',imageHash:hash,scaleMode:'FIT'}];return n;}
const FEATURES=[
 {key:'background',credits:20,name:{zh:'人物背景分离',en:'Background removal'},title:{zh:'把人物留下\n把背景分离',en:'Keep the person.\nSeparate the background.'},body:{zh:'分离人物与背景，得到透明 PNG。继续用于排版、合成，或放进你的下一个设计。',en:'Separate the person from the background as a transparent PNG, ready for your next layout or composition.'}},
 {key:'remove-objects',credits:30,name:{zh:'移除物体',en:'Remove objects'},title:{zh:'留下你想要的\n移走多余的物体',en:'Keep what matters.\nRemove the rest.'},body:{zh:'用英文描述要移除的物体。生成结果后，拖动滑杆核对原图与处理结果。',en:'Describe the unwanted object in English. Then drag the comparison divider to inspect the result against the original.'}},
 {key:'expand',credits:30,name:{zh:'智能扩图',en:'Expand image'},title:{zh:'向画面之外\n再多走一步',en:'Give your photo\nmore room.'},body:{zh:'向画面边缘之外延展，为人物照片增加构图空间。原图和扩展结果放在一起，变化看得清楚。',en:'Extend beyond the edges of a portrait to create more room in the composition. See the original beside the expanded result.'}},
 {key:'outfit',credits:30,name:{zh:'AI 换装',en:'Outfit swap'},title:{zh:'同一个人\n另一种穿搭',en:'Same person.\nA different outfit.'},body:{zh:'提供人物图和服装参考，尝试不同穿搭。保留原图，随时回看换装前后的效果。',en:'Add a person image and an outfit reference to try a different look. Keep the original close while you review the clothing change.'}}
];
const area=made(figma.createFrame());page.appendChild(area);area.name='Glance / Widget promotion assets';area.x=22000;area.y=160;area.resize(3100,1700);area.fills=[];area.clipsContent=false;
for(const[theme,index]of [['sumi',0],['washi',1]]){
 for(const mobile of [false,true]){
  const c=made(figma.createComponent());area.appendChild(c);c.name='Glance / Photo inputs / '+theme+' / '+(mobile?'Mobile':'Desktop');c.resize(mobile?342:1440,mobile?384:900);c.x=mobile?index*400:index*1520;c.y=mobile?1000:0;c.fills=[paint('canvas')];c.strokes=[paint('line')];c.strokeWeight=1;c.clipsContent=true;radius(c);c.setExplicitVariableModeForCollection('VariableCollectionId:13:3',theme==='sumi'?'13:1':'13:2');
  if(!mobile){
   const base=tracked(sources[theme].createInstance());c.appendChild(base);base.name='Native Glance window';
   const images=base.findAll(n=>'fills'in n&&Array.isArray(n.fills)&&n.fills.some(p=>p.type==='IMAGE'));
   for(let i=0;i<images.length;i++){if(i===0||i>8)images[i].visible=false;else images[i].fills=[{type:'IMAGE',imageHash:DATA.photos[i-1].hash,scaleMode:'FILL'}];}
   const tx=base.findAllWithCriteria({types:['TEXT']});if(tx[0])tx[0].characters='Portrait collection';if(tx[1])tx[1].characters='8 original photos';if(tx[2])tx[2].visible=false;if(tx[3])tx[3].characters='1 / 8';
   const strip=stack(c,'Original portrait inputs','HORIZONTAL',1312,656);strip.x=64;strip.y=80;strip.primaryAxisSizingMode='FIXED';strip.counterAxisSizingMode='FIXED';strip.counterAxisAlignItems='CENTER';strip.itemSpacing=44;
   for(const idx of [2,3,7])photo(strip,'Original photo / '+(idx+1),DATA.photos[idx].hash,408,656);
  }else{
   c.layoutMode='VERTICAL';c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.strokesIncludedInLayout=false;
   const header=stack(c,'Window header','HORIZONTAL',342,32);header.primaryAxisSizingMode='FIXED';header.counterAxisSizingMode='FIXED';header.counterAxisAlignItems='CENTER';header.paddingLeft=12;header.fills=[paint('surface')];await text(header,'Window title','Glance', 'en',12,300,'secondary');
   const strip=stack(c,'Original portrait inputs','HORIZONTAL',342,284);strip.primaryAxisSizingMode='FIXED';strip.counterAxisSizingMode='FIXED';strip.counterAxisAlignItems='CENTER';strip.paddingLeft=12;strip.paddingRight=12;strip.itemSpacing=12;
   for(const idx of [2,3])photo(strip,'Original photo / '+(idx+1),DATA.photos[idx].hash,153,264);
   const thumbs=stack(c,'Portrait filmstrip','HORIZONTAL',342,52);thumbs.primaryAxisSizingMode='FIXED';thumbs.counterAxisSizingMode='FIXED';thumbs.counterAxisAlignItems='CENTER';thumbs.primaryAxisAlignItems='CENTER';thumbs.itemSpacing=8;
   for(let i=0;i<8;i++)photo(thumbs,'Thumbnail / '+(i+1),DATA.photos[i].hash,32,40);
   const foot=stack(c,'Photo collection label','HORIZONTAL',342,16);foot.primaryAxisSizingMode='FIXED';foot.counterAxisSizingMode='FIXED';foot.paddingLeft=12;const t=await text(foot,'Collection count','8 original photos','en',11,300,'secondary');t.lineHeight={unit:'PIXELS',value:16};
  }
  decks[theme+'/'+(mobile?'Mobile':'Desktop')]=c.id;
 }
}
for(const lang of ['zh','en'])for(const mobile of [false,true]){
 const width=mobile?342:448,c=made(figma.createComponent());area.appendChild(c);c.name='Glance / Widget story copy / '+lang+' / '+(mobile?'Mobile':'Desktop');c.layoutMode='VERTICAL';c.resize(width,200);c.primaryAxisSizingMode='AUTO';c.counterAxisSizingMode='FIXED';c.itemSpacing=16;c.fills=[];c.clipsContent=false;c.x=900+(lang==='en'?1000:0)+(mobile?500:0);c.y=1000;c.setBoundVariable('itemSpacing',spaces[16]);
 const f=FEATURES[0],meta=await text(c,'Widget metadata',lang==='zh'?'01 / 人物背景分离 · 20 点 / 次':'01 / Background removal · 20 credits / run',lang,12,width),title=await text(c,'Widget headline',f.title[lang],lang,mobile?32:36,width,'ink',true),body=await text(c,'Widget explanation',f.body[lang],lang,16,width);
 const keys={};for(const[key,node]of [['Meta',meta],['Title',title],['Body',body]]){const prop=c.addComponentProperty(key,'TEXT',node.characters);node.componentPropertyReferences={characters:prop};keys[key]=prop;node.layoutSizingHorizontal='FILL';}
 c.description='Outcome-led Widget promotion copy. Shared typography and theme variables; Meta, Title and Body remain editable. Unslop: Damir Sokolovsky, CC BY 4.0.';
 copies[lang+'/'+(mobile?'Mobile':'Desktop')]={id:c.id,keys};
}
async function updateText(node,value){for(const s of node.getStyledTextSegments(['fontName']))await figma.loadFontAsync(s.fontName);node.characters=value;changed(node);}
async function scroll(node,destinationId){await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId,navigation:'SCROLL_TO',transition:null}]}]);changed(node);}
async function band(section,f,index,lang,theme,mobile){
 for(const c of [...section.children])erase(c);
 const width=mobile?390:1440,edge=mobile?24:96,cw=width-edge*2;
 section.name=index===3?'06 / AI Widgets':'04.'+(index+1)+' / '+f.name[lang];section.parent.name='Row / '+section.name;
 section.layoutMode='VERTICAL';section.resize(width,100);section.primaryAxisSizingMode='AUTO';section.counterAxisSizingMode='FIXED';section.paddingLeft=edge;section.paddingRight=edge;section.paddingTop=0;section.paddingBottom=64;section.itemSpacing=48;section.fills=[];section.clipsContent=false;
 for(const p of ['paddingLeft','paddingRight'])section.setBoundVariable(p,spaces[edge]);section.setBoundVariable('paddingBottom',spaces[64]);section.setBoundVariable('itemSpacing',spaces[48]);
 const line=made(figma.createRectangle());section.appendChild(line);line.name='Feature divider';line.resize(cw,1);line.fills=[paint('line')];line.layoutSizingHorizontal='FILL';
 const row=stack(section,'Widget story / '+f.key,mobile?'VERTICAL':'HORIZONTAL',cw);row.primaryAxisSizingMode=mobile?'AUTO':'FIXED';row.counterAxisSizingMode=mobile?'FIXED':'AUTO';row.itemSpacing=mobile?32:64;row.counterAxisAlignItems=mobile?'MIN':'CENTER';row.layoutSizingHorizontal='FILL';row.setBoundVariable('itemSpacing',spaces[mobile?32:64]);
 const def=copies[lang+'/'+(mobile?'Mobile':'Desktop')],copy=tracked((await figma.getNodeByIdAsync(def.id)).createInstance());copy.name='Promotion copy / '+f.key;
 const meta=String(index+1).padStart(2,'0')+' / '+f.name[lang]+' · '+f.credits+(lang==='zh'?' 点 / 次':' credits / run');copy.setProperties({[def.keys.Meta]:meta,[def.keys.Title]:f.title[lang],[def.keys.Body]:f.body[lang]});
 const mediaDef=f.key==='remove-objects'?DATA.compare[['compare',lang,theme,mobile?'mobile':'desktop'].join('/')]:DATA.media[f.key+'/'+lang],source=await figma.getNodeByIdAsync(mediaDef.poster),film=tracked(source.createInstance());film.name='Promo media / '+f.key;film.rescale((mobile?342:736)/source.width);
 if(mobile||index%2===0){row.appendChild(copy);row.appendChild(film);}else{row.appendChild(film);row.appendChild(copy);}
 if(index===3){
  const more=stack(section,'More image Widgets','VERTICAL',cw);more.layoutSizingHorizontal='FILL';more.itemSpacing=16;more.setBoundVariable('itemSpacing',spaces[16]);
  await text(more,'More Widget capabilities',lang==='zh'?'还支持局部编辑、高清放大、图片与视频去水印、免费图床、图片转提示词，以及图生图。':'Also explore Edit Area, Upscale, image and video watermark removal, image hosting, Image to Prompt, and Redraw & Reframe.',lang,16,cw,'secondary');
  const link=await text(more,'Browse all Widgets',lang==='zh'?'查看全部 Widget →':'Explore all Widgets →',lang,14,cw,'ink');await link.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'URL',url:lang==='zh'?'https://glancepreview.com/widgets/':'https://glancepreview.com/en/widgets/',openInNewTab:true}]}]);
  await text(more,'Cloud processing disclosure',lang==='zh'?'运行前显示点数。云端处理会上传你提交的媒体，失败任务自动全额退点。':'Credits are shown before running. Cloud Widgets upload the media you submit; failed tasks refund credits in full.',lang,14,cw,'secondary');
 }
 section.layoutSizingHorizontal='FILL';section.layoutSizingVertical='HUG';section.parent.counterAxisSizingMode='AUTO';section.parent.layoutSizingVertical='HUG';changed(section);changed(section.parent);
 return {key:f.key,sectionId:section.id,mediaInstanceId:film.id,copyInstanceId:copy.id,mediaComponentId:source.id,mediaWidth:film.width,mediaHeight:film.height,sectionHeight:section.height,usesSlider:f.key==='remove-objects'};
}
for(const board of roots){
 const lang=board.name.includes('中文')?'zh':'en',mobile=board.width<500,theme=board.name.startsWith('Washi')?'washi':'sumi';
 const hero=board.findOne(n=>n.name==='02 / Hero'),intro=board.findOne(n=>n.name==='03 / Workflow introduction'),local=board.findOne(n=>n.name==='05 / More local tools');
 const sections=[board.findOne(n=>n.name.startsWith('04.1 / ')),board.findOne(n=>n.name.startsWith('04.2 / ')),board.findOne(n=>n.name.startsWith('04.3 / ')),board.findOne(n=>n.name==='06 / AI Widgets')];if(sections.some(n=>!n))throw new Error('Missing Widget story section');
 const slot=hero.findOne(n=>n.name===(mobile?'Product / Mobile compare detail':'Product / Native latest Image Inspect')&&n.type==='FRAME'&&(mobile?n.width<380:n.width>700));
 for(const c of [...slot.children])erase(c);slot.layoutMode='NONE';slot.fills=[];slot.strokes=[];const deck=tracked((await figma.getNodeByIdAsync(decks[theme+'/'+(mobile?'Mobile':'Desktop')])).createInstance());slot.appendChild(deck);deck.name='Original photos / Widget inputs';if(!mobile)deck.rescale(slot.width/1440);deck.x=0;deck.y=0;changed(slot);
 const find=(root,name)=>root.findOne(n=>n.type==='TEXT'&&n.name===name);
 await updateText(find(hero,'Section label'),lang==='zh'?'Glance · Mac 图片 Widget':'Glance · AI image Widgets for Mac');
 await updateText(find(hero,'Hero headline'),lang==='zh'?'用 AI 改图\n看见每种变化':'AI edits.\nVisible results.');
 await updateText(find(hero,'Hero description'),lang==='zh'?(mobile?'去背景、移物体、扩画幅、换穿搭。\n用 Widget 修改，再与原图对比。':'去背景、移除物体、扩画幅、换穿搭。\n用图片 Widget 完成修改，再与原图对比。'):'Remove backgrounds. Erase objects.\nExpand a frame. Try a new outfit.');
 await updateText(find(hero,'Product caption'),lang==='zh'?'从你的一张照片开始':'Start with a photo of your own.');
 const action=hero.findOne(n=>n.type==='TEXT'&&n.name.startsWith('Link / '));await updateText(action,lang==='zh'?'看 Widget 功能演示 →':'See Widgets in action →');action.name='Link / Widget demonstrations';await scroll(action,intro.id);
 await updateText(find(intro,'Section label'),lang==='zh'?'精选图片 Widget':'Selected image Widgets');
 await updateText(find(intro,'Workflow headline'),lang==='zh'?'选一个工具\n看一种改变':'Choose a tool.\nSee what changes.');
 await updateText(find(intro,'Workflow introduction'),lang==='zh'?'选好工具，看清处理后的变化。\n需要确认细节时，直接对照原图。':'Choose a Widget, then check the result\nagainst your original.');
 const info=[];for(let i=0;i<4;i++)info.push(await band(sections[i],FEATURES[i],i,lang,theme,mobile));
 // The fourth Widget story follows the other three; local conveniences follow it.
 board.insertChild(board.children.indexOf(local.parent),sections[3].parent);changed(board);board.primaryAxisSizingMode='AUTO';
 const nav=board.findOne(n=>n.name==='01 / Navigation');for(const t of nav.findAllWithCriteria({types:['TEXT']})){if(['Link / AI Widgets','Link / AI Widget'].includes(t.name))await scroll(t,intro.id);if(['Link / Features','Link / 功能'].includes(t.name))await scroll(t,local.id);}
 const mediaCount=board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Promo media / ')).length;
 const duplicateCards=board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Demo / ')||n.name.startsWith('Upper demo / ')).length;
 if(mediaCount!==4||duplicateCards!==0)throw new Error('Expected four distinct Widget promotions and no duplicate media gallery');
 if(board.findOne(n=>n.name==='06b / Pro tool demonstrations'))throw new Error('Pro demos must remain absent');
 boards.push({id:board.id,name:board.name,height:board.height,width:board.width,heroId:hero.id,introId:intro.id,widgetFilms:mediaCount,duplicateCards,order:board.children.map(n=>({id:n.id,name:n.name,height:n.height}))});stories.push({boardId:board.id,lang,theme,mobile,features:info});
}
const sumiTop=roots[0].y,washiY=sumiTop+Math.max(...boards.filter(b=>b.name.startsWith('Sumi')).map(b=>b.height))+480;for(const n of page.children.filter(n=>n.name.startsWith('Washi · '))){n.y=washiY;changed(n);}
page.selection=[await figma.getNodeByIdAsync('15:1545')];figma.viewport.scrollAndZoomIntoView(page.selection);
const pack=ids=>{const m={};for(const id of new Set(ids)){const i=id.lastIndexOf(':')+1,p=id.slice(0,i);(m[p]??=[]).push(id.slice(i));}for(const[p,v]of Object.entries(m)){const a=[...new Set(v)].sort((x,y)=>Number(x)-Number(y)),out=[];let s=a[0],l=s;for(const x of a.slice(1)){if(Number(x)===Number(l)+1)l=x;else{out.push(s===l?s:s+'-'+l);s=l=x;}}if(s!==undefined)out.push(s===l?s:s+'-'+l);m[p]=out.join(',');}return m;};
return {createdNodeIdRangesByPrefix:pack(created),mutatedNodeIds:[...new Set(mutated)],removedNodeIdRangesByPrefix:pack(removed),createdTextStyleIds:madeStyles,libraryId:area.id,copies,decks,boards,stories,washiY,counts:{homepages:8,widgetStoriesPerHomepage:4,totalStoryPlacements:32,duplicateGalleryCards:0,proDemonstrations:0,newPhotos:8},featureOrder:FEATURES.map(f=>f.key),comparisonWithin:'remove-objects'};
