/* DATA.assets is supplied by the uploader. Native media and card components.
 * Unslop method: Damir Sokolovsky, CC BY 4.0. Website file only.
 */
if (figma.fileKey !== 'kWvE51F9IfI3oSN6ZoxeKw') throw new Error('Wrong website file');
const page = await figma.getNodeByIdAsync('0:1'); await figma.setCurrentPageAsync(page);
await Promise.all([['Inter','Regular'],['Inter','Medium'],['Geist Mono','Regular'],['Shippori Mincho','Regular'],['Noto Sans SC','Regular'],['Noto Sans SC','Medium'],['Noto Serif SC','Regular']].map(([family,style])=>figma.loadFontAsync({family,style})));
if (page.children.some(n=>n.name==='Glance / Feature demo library')) throw new Error('Demo library already exists; read the committed ledger before retrying');
const created=[],mutated=[],removed=[], media={},cards={}, styles={};
const vars={};for(const [k,id] of Object.entries({bg:'VariableID:13:28',surface:'VariableID:13:29',ink:'VariableID:13:32',secondary:'VariableID:13:33',line:'VariableID:13:31'}))vars[k]=await figma.variables.getVariableByIdAsync(id);
const primitive=await figma.variables.getVariableCollectionByIdAsync('VariableCollectionId:13:2');
const existingVars=await figma.variables.getLocalVariablesAsync('FLOAT'),spaces={};
for(const value of [8,12,16,24,32,48,64,96]){
 let v=existingVars.find(v=>v.name==='space/'+value);
 if(!v){v=figma.variables.createVariable('space/'+value,primitive,'FLOAT');v.scopes=['GAP'];v.setVariableCodeSyntax('WEB','var(--glance-space-'+value+')');v.setValueForMode(primitive.defaultModeId,value);}
 spaces[value]=v;
}
function paint(k){return figma.variables.setBoundVariableForPaint({type:'SOLID',color:{r:0,g:0,b:0}},'color',vars[k]);}
function made(n){created.push(n.id);return n;}
function erase(n){removed.push(n.id,...('findAll'in n?n.findAll().map(c=>c.id):[]));n.remove();}
const existingStyles=await figma.getLocalTextStylesAsync();
async function typography(family,size,lineHeight){
 const key=[family,size,'Regular',lineHeight].join('/');
 let s=existingStyles.find(s=>s.name==='Glance/'+key);
 if(!s){s=figma.createTextStyle();s.name='Glance/'+key;s.fontName={family,style:'Regular'};s.fontSize=size;s.lineHeight={unit:'PIXELS',value:lineHeight};existingStyles.push(s);}
 styles[key]=s.id;return s.id;
}
async function text(parent,name,value,width,family,size,lineHeight,role){
 const t=made(figma.createText());t.fontName={family,style:'Regular'};t.fontSize=size;t.lineHeight={unit:'PIXELS',value:lineHeight};t.characters=value;t.textAutoResize='HEIGHT';t.resize(width,lineHeight);t.fills=[paint(role)];parent.appendChild(t);t.name=name;t.layoutSizingHorizontal='FILL';await t.setTextStyleIdAsync(await typography(family,size,lineHeight));return t;
}
const library=made(figma.createFrame());library.name='Glance / Feature demo library';page.appendChild(library);library.x=13200;library.y=160;library.resize(3360,12800);library.fills=[];library.clipsContent=false;
for(let index=0;index<DATA.assets.length;index++){
 const asset=DATA.assets[index],variants=[];
 for(const state of ['Poster','Playing']){
  const c=made(figma.createComponent());c.name='Playback='+state;c.resize(720,480);c.fills=[];c.clipsContent=true;c.cornerRadius=12;
  const image=made(figma.createRectangle());c.appendChild(image);image.name='Film';image.resize(720,480);image.fills=[{type:'IMAGE',imageHash:state==='Poster'?asset.posterHash:asset.gifHash,scaleMode:'FIT'}];image.constraints={horizontal:'STRETCH',vertical:'STRETCH'};
  const svg=state==='Poster'?'<circle cx="36" cy="36" r="34" fill="#eae7e0"/><path d="M29 23 51 36 29 49Z" fill="#151514"/>':'<circle cx="36" cy="36" r="34" fill="#151514" fill-opacity=".85"/><path d="M28 23v26M43 23v26" stroke="#eae7e0" stroke-width="7"/>';
  const button=made(figma.createNodeFromSvg('<svg xmlns="http://www.w3.org/2000/svg" width="72" height="72" viewBox="0 0 72 72">'+svg+'</svg>'));c.appendChild(button);button.name=state==='Poster'?'Play demo':'Pause demo';button.x=324;button.y=204;button.constraints={horizontal:'CENTER',vertical:'CENTER'};created.push(...button.findAll().map(n=>n.id));
  if(state==='Playing'){button.resize(44,44);button.x=660;button.y=72;button.constraints={horizontal:'MAX',vertical:'MIN'};}
  variants.push(c);
 }
 const set=made(figma.combineAsVariants(variants,library));set.name='Glance / Film / '+asset.key+' / '+asset.lang;set.fills=[];set.strokes=[];set.resizeWithoutConstraints(1512,520);set.x=(index%2)*1680;set.y=Math.floor(index/2)*640;
 variants.forEach((c,i)=>{c.x=12+i*756;c.y=12;});
 for(let i=0;i<2;i++)await variants[i].setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:variants[1-i].id,navigation:'CHANGE_TO',transition:{type:'DISSOLVE',easing:{type:'EASE_OUT'},duration:.14},resetVideoPosition:true}]}]);
 set.description='Click to play/pause a captioned looping GIF in Presentation View. The native canvas uses the matching still poster. Original GIF retained; MP4 is packaged locally. Unslop: Damir Sokolovsky, CC BY 4.0.';
 media[asset.key+'/'+asset.lang]={poster:variants[0].id,playing:variants[1].id,set:set.id,gifHash:asset.gifHash,posterHash:asset.posterHash};
}
const cardArea=made(figma.createAutoLayout('VERTICAL'));page.appendChild(cardArea);cardArea.name='Glance / Feature card components';cardArea.x=5800;cardArea.y=1200;cardArea.resize(1440,1000);cardArea.primaryAxisSizingMode='AUTO';cardArea.counterAxisSizingMode='FIXED';cardArea.itemSpacing=64;cardArea.fills=[];cardArea.clipsContent=false;
for(const lang of ['zh','en'])for(const [kind,width] of [['Wide',1248],['Desktop',600],['Compact',384],['Mobile',342]]){
 const wide=kind==='Wide',mediaWidth=wide?736:width;
 const c=made(figma.createComponent());c.name='Glance / Feature card / '+lang+' / '+kind;cardArea.appendChild(c);c.resize(width,500);c.layoutMode=wide?'HORIZONTAL':'VERTICAL';c.primaryAxisSizingMode=wide?'FIXED':'AUTO';c.counterAxisSizingMode=wide?'AUTO':'FIXED';c.itemSpacing=wide?64:16;c.counterAxisAlignItems=wide?'CENTER':'MIN';c.fills=[];c.clipsContent=false;c.setBoundVariable('itemSpacing',spaces[wide?64:16]);
 const starter=await figma.getNodeByIdAsync(media['edit-area/'+lang].poster),film=made(starter.createInstance());c.appendChild(film);film.name='Demo media';film.rescale(mediaWidth/720);created.push(...film.findAll().map(n=>n.id));
 const swap=c.addComponentProperty('Media','INSTANCE_SWAP',starter.id);film.componentPropertyReferences={mainComponent:swap};
 let copy=c;
 if(wide){copy=made(figma.createAutoLayout('VERTICAL'));c.appendChild(copy);copy.name='Feature explanation';copy.resize(448,240);copy.layoutSizingHorizontal='FILL';copy.primaryAxisSizingMode='AUTO';copy.counterAxisSizingMode='FIXED';copy.itemSpacing=16;copy.fills=[];copy.setBoundVariable('itemSpacing',spaces[16]);}
 const meta=await text(copy,'Feature metadata',lang==='zh'?'AI Widget · 按次计费':'AI Widget · credits per run',wide?448:width,lang==='zh'?'Noto Sans SC':'Geist Mono',12,20,'secondary');
 const titleSize=wide?36:(kind==='Mobile'||kind==='Compact'?24:28),heading=await text(copy,'Feature title',lang==='zh'?'局部编辑':'Edit Area',wide?448:width,lang==='zh'?'Noto Serif SC':'Shippori Mincho',titleSize,wide?40:32,'ink');
 const summary=await text(copy,'Feature summary',lang==='zh'?'从输入到结果，看清每一步。':'See each step from input to result.',wide?448:width,lang==='zh'?'Noto Sans SC':'Inter',16,24,'secondary');
 const keys={media:swap};for(const [role,node] of [['meta',meta],['title',heading],['summary',summary]]){const key=c.addComponentProperty(role[0].toUpperCase()+role.slice(1),'TEXT',node.characters);node.componentPropertyReferences={characters:key};keys[role]=key;}
 c.description='Reusable captioned feature showcase. Override Title, Summary, Meta and swap Media. Portrait examples are content; all website text and hierarchy stay editable.';
 cards[lang+'/'+kind]={id:c.id,keys};
}
// The uploads are transfer nodes; the actual images are now used in components.
for(const id of [...DATA.assets.flatMap(a=>[a.gifNodeId,a.posterNodeId]),'26:1490']){const n=await figma.getNodeByIdAsync(id);if(n)erase(n);}
const pack=values=>{const map={};for(const id of new Set(values)){const at=id.lastIndexOf(':')+1,p=id.slice(0,at);(map[p]??=[]).push(id.slice(at));}return Object.fromEntries(Object.entries(map).map(([p,ids])=>[p,ids.join(',')]));};
return {createdNodeIdsByPrefix:pack(created),mutatedNodeIds:mutated,removedNodeIdsByPrefix:pack(removed),media,cards,spaces:Object.fromEntries(Object.entries(spaces).map(([k,v])=>[k,v.id])),styles,libraryId:library.id,cardAreaId:cardArea.id,counts:{films:40,playbackVariants:80,cardTemplates:8}};
