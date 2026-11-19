/* Convert the exact Figma product artwork to static HTML templates. This is
 * build tooling, not a React/Tailwind runtime. Assets retain their source bytes.
 * Unslop: Damir Sokolovsky, CC BY 4.0. */
const fs=require('node:fs'),path=require('node:path');
const ts=require('../../server/GlanceService/node_modules/typescript');
const contexts=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const dir=path.join(__dirname,'src/artwork');fs.mkdirSync(dir,{recursive:true});
const plan=new Map(),unknown=new Set();
const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('"','&quot;').replaceAll('<','&lt;').replaceAll('>','&gt;');
function css(classes){const out={};
 for(const token of classes.split(/\s+/)){
  const exact={absolute:{position:'absolute'},relative:{position:'relative'},contents:{display:'contents'},block:{display:'block'},flex:{display:'flex'},'flex-col':{'flex-direction':'column'},'shrink-0':{'flex-shrink':'0'},'items-start':{'align-items':'flex-start'},'items-center':{'align-items':'center'},'justify-center':{'justify-content':'center'},'content-stretch':{'align-content':'stretch'},'overflow-clip':{overflow:'hidden'},'size-full':{width:'100%',height:'100%'},'w-full':{width:'100%'},'h-full':{height:'100%'},'max-w-none':{'max-width':'none'},'inset-0':{inset:'0'},'left-0':{left:'0'},'top-0':{top:'0'},'right-full':{right:'100%'},'bottom-full':{bottom:'100%'},'pointer-events-none':{'pointer-events':'none'},'object-contain':{'object-fit':'contain'},'object-cover':{'object-fit':'cover'},'border-solid':{'border-style':'solid'},border:{'border-width':'1px'},'font-normal':{'font-weight':'400'},'font-medium':{'font-weight':'500'},'not-italic':{'font-style':'normal'},'whitespace-nowrap':{'white-space':'nowrap'},'text-left':{'text-align':'left'},'text-center':{'text-align':'center'},'mask-alpha':{'mask-mode':'alpha'},'mask-intersect':{'mask-composite':'intersect'},'mask-no-clip':{'mask-clip':'no-clip'},'mask-no-repeat':{'mask-repeat':'no-repeat'},'mb-0':{'margin-bottom':'0'},'h-px':{height:'1px'},'leading-none':{'line-height':'1'},'leading-normal':{'line-height':'1.5'}};
  if(exact[token]){Object.assign(out,exact[token]);continue;}
  if(token==='[word-break:break-word]'){out['overflow-wrap']='break-word';continue;}
  if(token.startsWith('opacity-')){out.opacity=String(Number(token.slice(8))/100);continue;}
  let m=token.match(/^([^[]+)-\[(.*)\]$/);if(!m){if(token&&!['cursor-pointer'].includes(token))unknown.add(token);continue;}
  const k=m[1],v=m[2].replaceAll('_',' '),map={w:'width',h:'height',left:'left',right:'right',top:'top',bottom:'bottom',inset:'inset',gap:'gap',bg:'background',rounded:'border-radius',leading:'line-height',pl:'padding-left',pr:'padding-right',pt:'padding-top',pb:'padding-bottom','mask-size':'mask-size','mask-position':'mask-position'};
  if(map[k])out[map[k]]=v;
  else if(k==='px'){out['padding-left']=out['padding-right']=v;}
  else if(k==='py'){out['padding-top']=out['padding-bottom']=v;}
  else if(k==='size'){out.width=out.height=v;}
  else if(k==='border'){out[/^[.\d-]/.test(v)?'border-width':'border-color']=v;}
  else if(k==='text'){out[/^[.\d-]/.test(v)?'font-size':'color']=v.replace(/^color:/,'');}
  else if(k==='font'){out['font-family']='"'+v.replaceAll("'",'').split(':')[0]+'"';}
  else unknown.add(token);
 }
 return out;
}
function evaluate(n,env){if(!n)return undefined;if(ts.isParenthesizedExpression(n))return evaluate(n.expression,env);if(ts.isStringLiteral(n)||ts.isNoSubstitutionTemplateLiteral(n))return n.text;if(ts.isIdentifier(n))return env[n.text];if(n.kind===ts.SyntaxKind.TrueKeyword)return true;if(n.kind===ts.SyntaxKind.FalseKeyword)return false;
 if(ts.isConditionalExpression(n))return evaluate(evaluate(n.condition,env)?n.whenTrue:n.whenFalse,env);
 if(ts.isBinaryExpression(n)){const a=evaluate(n.left,env),op=n.operatorToken.kind;if(op===ts.SyntaxKind.BarBarToken)return a||evaluate(n.right,env);if(op===ts.SyntaxKind.AmpersandAmpersandToken)return a&&evaluate(n.right,env);if(op===ts.SyntaxKind.EqualsEqualsEqualsToken)return a===evaluate(n.right,env);}
 if(ts.isTemplateExpression(n))return n.head.text+n.templateSpans.map(s=>(evaluate(s.expression,env)||'')+s.literal.text).join('');
 if(ts.isObjectLiteralExpression(n))return Object.fromEntries(n.properties.filter(ts.isPropertyAssignment).map(p=>[p.name.getText().replaceAll('"','').replaceAll("'",''),evaluate(p.initializer,env)]));
 return undefined;
}
const assetIndex={};
for(const key of ['hero-dark-desktop','hero-dark-mobile','hero-light-desktop','hero-light-mobile','compare-dark-desktop','compare-dark-mobile','compare-light-desktop','compare-light-mobile','widget-playing']){
 const code=contexts[key];if(!code)throw new Error('Missing context '+key);const source=ts.createSourceFile('context.tsx',code,ts.ScriptTarget.Latest,true,ts.ScriptKind.TSX),env={playback:'Poster',isPlaying:false,className:undefined};
 for(const m of code.matchAll(/const (\w+) = "(https:\/\/www\.figma\.com\/api\/mcp\/asset\/[^\"]+)";/g)){
  const local='/assets/figma/'+path.basename(m[2]);env[m[1]]=local;plan.set(local,{url:m[2],local});
 }
 assetIndex[key]={play:env.imgPlay||env.imgPlayDemo,pause:env.imgPause||env.imgPauseDemo};
 if(key==='widget-playing')continue;
 let root;
 for(const stmt of source.statements)if(ts.isFunctionDeclaration(stmt)&&stmt.body){const r=stmt.body.statements.find(ts.isReturnStatement);if(r&&(ts.isJsxElement(r.expression)||ts.isParenthesizedExpression(r.expression)))root=r.expression;}
 if(!root)throw new Error('Missing JSX root '+key);
 const mobile=key.endsWith('mobile'),w=mobile?342:1440,h=mobile?384:900;
 function render(n,level=0){
  if(ts.isParenthesizedExpression(n))return render(n.expression,level);
  if(ts.isJsxExpression(n)){if(!n.expression)return '';const e=n.expression;if(ts.isBinaryExpression(e)&&e.operatorToken.kind===ts.SyntaxKind.AmpersandAmpersandToken)return evaluate(e.left,env)?render(e.right,level):'';if(ts.isParenthesizedExpression(e))return render(e.expression,level);const v=evaluate(e,env);return typeof v==='string'?esc(v):'';}
  if(ts.isJsxText(n)){const value=n.text.replace(/\s+/g,' ').trim();return value?esc(value):'';}
  if(!ts.isJsxElement(n)&&!ts.isJsxSelfClosingElement(n))return '';
  const open=ts.isJsxElement(n)?n.openingElement:n,attrs={};
  for(const a of open.attributes.properties)if(ts.isJsxAttribute(a)){const v=a.initializer;attrs[a.name.text]=!v?'':ts.isStringLiteral(v)?v.text:evaluate(v.expression,env);}
  if(attrs['data-name']==='Animated content viewport'||attrs['data-name']==='Play demonstration'||attrs['data-name']==='Pause demonstration')return '';
  let tag=open.tagName.getText(source);if(tag==='button')tag='div';if(!['div','img','p','span'].includes(tag))throw new Error('Unsupported art node '+tag);
  const styles={margin:'0','box-sizing':'border-box',...css(attrs.className||'')};
  for(const[k,v]of Object.entries(attrs.style||{}))styles[k.replace(/[A-Z]/g,s=>'-'+s.toLowerCase())]=v;
  // Stroke paint is inside the Figma frame, without taking layout space.
  if(level===0&&styles['border-width']){styles.outline=styles['border-width']+' solid '+(styles['border-color']||'transparent');styles['outline-offset']='-'+styles['border-width'];styles['border-width']='0';}
  if(level===1&&styles.position==='absolute'){for(const p of ['left','top'])if(/^-?[\d.]+px$/.test(styles[p]||''))styles[p]=(Number(styles[p].slice(0,-2))+1)+'px';}
  const attr=Object.entries(attrs).filter(([k,v])=>!['className','style','id','data-node-id','height','width'].includes(k)&&v!==undefined).map(([k,v])=>' '+k+'="'+esc(v)+'"').join('');
  const style=' style="'+esc(Object.entries(styles).map(([k,v])=>k+':'+v).join(';'))+'"';
  if(tag==='img')return '<img'+attr+style+' loading="lazy" decoding="async">';
  return '<'+tag+attr+style+'>'+(n.children||[]).map(c=>render(c,level+1)).join('')+'</'+tag+'>';
 }
 const html='<svg xmlns="http://www.w3.org/2000/svg" class="product-art" width="'+w+'" height="'+h+'" viewBox="0 0 '+w+' '+h+'" aria-hidden="true" focusable="false"><foreignObject width="'+w+'" height="'+h+'"><div xmlns="http://www.w3.org/1999/xhtml" style="width:'+w+'px;height:'+h+'px;font-size:16px;line-height:1.5">'+render(root)+'</div></foreignObject></svg>';
 fs.writeFileSync(path.join(dir,key+'.html'),html);
}
if(unknown.size)throw new Error('Unconverted design classes: '+[...unknown].join(', '));
const used=new Set();for(const file of fs.readdirSync(dir))for(const m of fs.readFileSync(path.join(dir,file),'utf8').matchAll(/\/assets\/figma\/[a-zA-Z0-9-]+\.(?:svg|png)/g))used.add(m[0]);
for(const a of Object.values(assetIndex))for(const p of Object.values(a))if(p)used.add(p);
const needed=[...plan.values()].filter(a=>used.has(a.local));
fs.writeFileSync('/private/tmp/glance-web-assets-plan.json',JSON.stringify(needed));fs.writeFileSync(path.join(dir,'controls.json'),JSON.stringify(assetIndex,null,2)+'\n');
console.log('Converted eight native product views; '+needed.length+' exact Figma assets required.');
