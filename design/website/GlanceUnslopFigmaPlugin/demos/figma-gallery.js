/* LIB and FEATURES are supplied from committed media/component ledgers.
 * Curates four Widget films and removes the Pro film section on all eight pages.
 */
if(figma.fileKey!=='kWvE51F9IfI3oSN6ZoxeKw')throw new Error('Wrong website file');
const page=await figma.getNodeByIdAsync('0:1');await figma.setCurrentPageAsync(page);
await Promise.all([['Inter','Regular'],['Inter','Medium'],['Geist Mono','Regular'],['Shippori Mincho','Regular'],['Noto Sans SC','Regular'],['Noto Sans SC','Medium'],['Noto Serif SC','Regular']].map(([family,style])=>figma.loadFontAsync({family,style})));
const created=[],mutated=[],removed=[],boards=[],vars={},spaces={},templates={},headings={};
const selectedKeys=['remove-objects','background','expand','outfit'];
for(const [k,id]of Object.entries({ink:'VariableID:13:32',secondary:'VariableID:13:33',line:'VariableID:13:31'}))vars[k]=await figma.variables.getVariableByIdAsync(id);
for(const [k,id]of Object.entries(LIB.spaces))spaces[k]=await figma.variables.getVariableByIdAsync(id);
for(const [key,value]of Object.entries(LIB.cards))templates[key]=await figma.getNodeByIdAsync(value.id);
const styles=await figma.getLocalTextStylesAsync();
const paint=k=>figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',vars[k]);
const made=n=>{created.push(n.id);return n;};
const changed=n=>{mutated.push(n.id);return n;};
function erase(n){removed.push(n.id,...('findAll'in n?n.findAll().map(c=>c.id):[]));n.remove();}
function stack(parent,name,direction='VERTICAL'){
 const n=made(figma.createAutoLayout(direction));parent.appendChild(n);n.name=name;n.fills=[];n.clipsContent=false;n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';return n;
}
async function text(parent,name,value,lang,size=16,role='secondary',display=false){
 const family=display?(lang==='zh'?'Noto Serif SC':'Shippori Mincho'):(lang==='zh'?'Noto Sans SC':size===12?'Geist Mono':'Inter'),line=size>=32?(size===48?52:40):size===12?20:24;
 const n=made(figma.createText());n.fontName={family,style:'Regular'};n.fontSize=size;n.lineHeight={unit:'PIXELS',value:line};n.characters=value;n.textAutoResize='HEIGHT';n.resize(parent.width||342,line);n.fills=[paint(role)];n.name=name;parent.appendChild(n);n.layoutSizingHorizontal='FILL';
 const style=styles.find(s=>s.name==='Glance/'+[family,size,'Regular',line].join('/'));if(style)await n.setTextStyleIdAsync(style.id);return n;
}
async function card(parent,f,lang,kind){
 const def=LIB.cards[lang+'/'+kind],c=made(templates[lang+'/'+kind].createInstance());parent.appendChild(c);
 c.name='Demo / '+f.key+' / '+lang;
 const meta=lang==='zh'?'AI Widget · '+f.credits+' 点 / 次':'AI Widget · '+f.credits+' credits / run';
 const summary=f.description[lang];
 c.setProperties({[def.keys.title]:f.title[lang],[def.keys.summary]:summary,[def.keys.meta]:meta,[def.keys.media]:LIB.media[f.key+'/'+lang].poster});
 created.push(...c.findAll().map(n=>n.id));return c;
}
async function sectionContents(section,lang,mobile){
 const width=mobile?390:1440,edge=mobile?24:96,cw=width-edge*2,items=selectedKeys.map(key=>FEATURES.find(f=>f.key===key));
 if(items.some(f=>!f))throw new Error('Missing selected Widget film');
 section.layoutMode='VERTICAL';section.resize(width,200);section.primaryAxisSizingMode='AUTO';section.counterAxisSizingMode='FIXED';section.itemSpacing=48;section.fills=[];section.clipsContent=false;
 section.paddingTop=64;section.paddingBottom=64;section.paddingLeft=edge;section.paddingRight=edge;
 for(const prop of ['paddingTop','paddingBottom'])section.setBoundVariable(prop,spaces[64]);
 for(const prop of ['paddingLeft','paddingRight'])section.setBoundVariable(prop,spaces[edge]);section.setBoundVariable('itemSpacing',spaces[48]);
 const header=stack(section,'Section introduction');header.resize(cw,200);header.layoutSizingHorizontal='FILL';header.primaryAxisSizingMode='AUTO';header.itemSpacing=16;header.setBoundVariable('itemSpacing',spaces[16]);
 await text(header,'Section label','AI Widgets',lang,12);
 await text(header,'Demo gallery headline',lang==='zh'?'每一种改变，都看得见':'See a few useful changes',lang,mobile?32:48,'ink',true);
 await text(header,'Demo gallery introduction',lang==='zh'?'移除物体、人物背景分离、智能扩图与 AI 换装。四段演示，直接看前后变化。':'Remove objects, separate backgrounds, extend a frame and change an outfit. Four films, with the changes in view.',lang);
 const list=stack(section,'Four selected Widget demonstrations');list.resize(cw,100);list.layoutSizingHorizontal='FILL';list.primaryAxisSizingMode='AUTO';list.itemSpacing=48;list.setBoundVariable('itemSpacing',spaces[48]);
 let offset=0;
 if(!mobile){await card(list,items[0],lang,'Wide');offset=1;}
 const columns=mobile?1:3,kind=mobile?'Mobile':'Compact';
 for(let i=offset;i<items.length;i+=columns){
  const row=stack(list,'Feature row / '+items[i].key,'HORIZONTAL');row.resize(cw,100);row.primaryAxisSizingMode='FIXED';row.counterAxisSizingMode='AUTO';row.itemSpacing=48;row.counterAxisAlignItems='MIN';row.layoutSizingHorizontal='FILL';row.setBoundVariable('itemSpacing',spaces[48]);
  for(const f of items.slice(i,i+columns))await card(row,f,lang,kind);
 }
 const link=await text(section,'Browse all Widgets',lang==='zh'?'查看全部 Widget →':'Explore all Widgets →',lang,14,'ink');
 await link.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'URL',url:lang==='zh'?'https://glancepreview.com/widgets/':'https://glancepreview.com/en/widgets/',openInNewTab:true}]}]);
 await text(section,'Processing and plan note',lang==='zh'?'云端 Widget 会上传你提交的媒体，运行前显示点数。所有失败任务自动全额退点。':'Cloud Widgets upload the media you submit and show the cost before running. Failed tasks refund credits in full.',lang,14);
 changed(section);
}
const ids=['15:2','15:969','15:1545','15:2512','15:3216','15:4183','15:4759','15:5726'];
for(const id of ids){
 const board=await figma.getNodeByIdAsync(id),lang=board.name.includes('中文')?'zh':'en',mobile=board.width<500;
 const oldPro=board.findOne(n=>n.name==='06b / Pro tool demonstrations');
 if(oldPro)erase(oldPro.parent);
 const widgets=board.findOne(n=>n.name==='06 / AI Widgets');if(!widgets)throw new Error('Missing existing Widget anchor');
 const widgetRow=widgets.parent;
 for(const c of [...widgets.children])erase(c);
 await sectionContents(widgets,lang,mobile);
 widgets.layoutSizingHorizontal='FILL';widgets.layoutSizingVertical='HUG';widgetRow.counterAxisSizingMode='AUTO';widgetRow.layoutSizingVertical='HUG';changed(widgetRow);
 board.primaryAxisSizingMode='AUTO';board.overflowDirection='VERTICAL';board.clipsContent=true;changed(board);
 const nav=board.findOne(n=>n.name==='01 / Navigation');
 const link=nav.findOne(n=>n.type==='TEXT'&&['Link / Pro tools','Link / Install','Link / 安装'].includes(n.name));
 if(link){link.characters=lang==='zh'?'安装':'Install';link.name=lang==='zh'?'Link / 安装':'Link / Install';await link.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'URL',url:lang==='zh'?'https://glancepreview.com/install/':'https://glancepreview.com/en/install/',openInNewTab:true}]}]);changed(link);}
 const count=board.findAllWithCriteria({types:['INSTANCE']}).filter(n=>n.name.startsWith('Demo / ')).length;
 if(count!==4)throw new Error('Expected four selected demonstrations: '+id+' has '+count);
 if(board.findOne(n=>n.name==='06b / Pro tool demonstrations'))throw new Error('Pro showcase must be absent');
 boards.push({id,name:board.name,width:board.width,height:board.height,widgetsId:widgets.id,proId:null,demoCount:count,widgetCount:4,proCount:0});
}
const sumiMax=Math.max(...boards.filter(b=>b.name.startsWith('Sumi')).map(b=>b.height));
const sumiTop=(await figma.getNodeByIdAsync('15:2')).y;
const washiY=sumiTop+sumiMax+480;
for(const n of page.children.filter(n=>n.name.startsWith('Washi · '))){n.y=washiY;changed(n);}
const selected=await figma.getNodeByIdAsync('15:1545');page.selection=[selected.findOne(n=>n.name==='06 / AI Widgets')];figma.viewport.scrollAndZoomIntoView(page.selection);
const pack=values=>{const map={};for(const id of new Set(values)){const at=id.lastIndexOf(':')+1,p=id.slice(0,at);(map[p]??=[]).push(id.slice(at));}return Object.fromEntries(Object.entries(map).map(([p,ids])=>[p,ids.join(',')]));};
return {createdNodeIdsByPrefix:pack(created),mutatedNodeIds:mutated,removedNodeIdsByPrefix:pack(removed),boards,selection:selectedKeys,counts:{homepages:8,widgetsPerPage:4,proDemosPerPage:0,placedFeatureCards:32,uniqueCaptionedFilms:8},washiY};
