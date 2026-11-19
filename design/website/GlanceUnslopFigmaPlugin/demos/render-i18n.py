"""Japanese/German promotional media, reusing real source/result pairs.

Unslop: Damir Sokolovsky, CC BY 4.0. No app launch or cloud request.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from PIL import ImageFont
import importlib.util, json, threading

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'media-i18n';OUT.mkdir(exist_ok=True)
def module(name,file):
 spec=importlib.util.spec_from_file_location(name,ROOT/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
m=module('widget_films','render.py');u=module('upper_films','render-upper.py')
m.OUT=OUT;u.OUT=OUT
JP=Path('/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc')
EN=ROOT.parent/'reference/fonts/Inter.ttf'
ctx=threading.local()
def font(size,lang='en'):return ImageFont.truetype(str(JP if lang=='ja' else EN),size)
m.font=font;u.ft=font
COMMON={
 'Result demo':{'ja':'結果デモ','de':'Ergebnisdemo'},
 'Workflow demo':{'ja':'操作デモ','de':'Ablaufdemo'},
 'Original':{'ja':'元画像','de':'Original'},
 'Result':{'ja':'結果','de':'Ergebnis'},
 'AI Widgets':{'ja':'AI Widget','de':'KI-Widgets'}}
orig_text=m.text
def text(im,xy,value,size=28,color=m.INK,lang='en',anchor=None):
 locale=getattr(ctx,'lang',lang)
 if value in COMMON:value=COMMON[value][locale];lang=locale
 return orig_text(im,xy,value,size,color,lang,anchor)
m.text=text
orig_widget_label=m.label
def widget_label(im,x,y,value,lang):
 return orig_widget_label(im,x,y,COMMON.get(value,{}).get(lang,value),lang)
m.label=widget_label
orig_label=u.label
def label(im,xy,value,size,color,lang='en',anchor=None):
 if value in COMMON:value=COMMON[value][lang]
 return orig_label(im,xy,value,size,color,lang,anchor)
u.label=label
def wrapped(value,limit,size,lang):
 units=list(value) if lang=='ja' else value.split(' ');lines=[];line='';f=font(size,lang)
 for word in units:
  candidate=line+(' ' if line and lang!='ja' else '')+word
  if f.getlength(candidate)>limit and line:lines.append(line);line=word
  else:line=candidate
 if line:lines.append(line)
 return lines
m.wrapped=wrapped;u.wrap=wrapped
COPY={
 'background':{'title':{'ja':'背景切り抜き','de':'Hintergrund entfernen'},'steps':{'ja':['人物写真を開く','背景切り抜きを選ぶ','透過PNGの仕上がりを確認'],'de':['Ein Porträt öffnen','Hintergrund entfernen wählen','Das transparente PNG ansehen']}},
 'expand':{'title':{'ja':'画像拡張','de':'Bild erweitern'},'steps':{'ja':['元の構図を確認','画像拡張を選ぶ','広がった画面を見比べる'],'de':['Den ursprünglichen Ausschnitt öffnen','Bild erweitern wählen','Den erweiterten Bildausschnitt prüfen']}},
 'outfit':{'title':{'ja':'AI着せ替え','de':'Outfit wechseln'},'steps':{'ja':['人物写真と服装の参考を追加','AI着せ替えを選ぶ','コーディネートの変化を確認'],'de':['Person und Kleidungsvorlage hinzufügen','Outfit wechseln wählen','Die neue Kleidung vergleichen']}}
}
u.COPY['compare'].update({
 'ja':['元画像と結果を並べて確認','スライダーで変化を確かめる','バッグを消した仕上がりを確認'],
 'de':['Original und Ergebnis nebeneinander.','Den Regler zum Vergleichen bewegen.','Das Ergebnis ohne Handtasche prüfen.']})

def job(data):
 key,lang,theme,kind=data;ctx.lang=lang
 if key=='compare':a=u.render(data)
 else:
  f=next(f for f in m.FEATURES if f['key']==key).copy();f['title']={**f['title'],**COPY[key]['title']};f['steps']={**f['steps'],**COPY[key]['steps']}
  a=m.render_job((f,lang));a.update(width=720,height=480)
 a.update(theme=theme,kind=kind)
 for role in ['gif','poster','mp4']:a[role]='media-i18n/'+Path(a[role]).name
 return a

if __name__=='__main__':
 jobs=[(key,lang,'shared','widget') for key in COPY for lang in ['ja','de']]+[('compare',lang,theme,kind) for lang in ['ja','de'] for theme in ['sumi','washi'] for kind in ['desktop','mobile']]
 with ThreadPoolExecutor(max_workers=3) as pool:
  assets=[]
  for a in pool.map(job,jobs):assets.append(a);print(a['key'],a['lang'],a['theme'],a['kind'],a['frames'],'frames',round(a['bytes']/1024),'KB',flush=True)
 (ROOT/'i18n-media-manifest.json').write_text(json.dumps({'languages':['ja','de'],'features':['background','remove-objects','expand','outfit'],'assets':assets,'sourceAppLaunched':False,'cloudTasksSubmitted':0},ensure_ascii=False,indent=2)+'\n')
