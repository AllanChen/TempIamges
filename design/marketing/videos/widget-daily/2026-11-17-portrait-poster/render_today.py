import sys,runpy
from pathlib import Path
base=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(base))
sys.argv += ['--widget','bgpro','--no-url']
import importlib.util
spec=importlib.util.spec_from_file_location('daily_module',base/'render.py')
module=importlib.util.module_from_spec(spec)
sys.modules['daily_module']=module
spec.loader.exec_module(module)
d=module.__dict__
g=d['main'].__globals__
g['OUTDIR']=Path(__file__).resolve().parent
g['VDIR']=g['OUTDIR']/'unused-voice'
g['NOTE']=g['h'].L('Redrawn UI · Example effect','界面重绘 · 示例效果')
g['S']['hook']=(g['h'].L('A portrait for your poster?','海报缺一张人像？'),g['h'].L('Start with a cutout.','先把人物抠出来。'))
g['S']['demo']=(g['h'].L('Right-click.','右键选择，'),g['h'].L('Remove the background.','人物背景分离。'))
g['S']['result']=(g['h'].L('Preview the cutout.','看看抠图结果，'),g['h'].L('Compare before and after.','前后对比更直观。'))
g['S']['detail']=g['h'].L('Example portrait cutout for a poster workflow','人像抠图示例，用于海报制作流程')
from PIL import Image
import subprocess
icon=g['OUTDIR']/'app-icon.png'
subprocess.run(['sips','-s','format','png','/Applications/Glance.app/Contents/Resources/AppIcon.icns','--out',str(icon)],check=True,stdout=subprocess.DEVNULL)
g['z'].LOGO=Image.open(icon).convert('RGBA')
g['main']()
f=g['OUTDIR']/('narration-'+g['h'].LANG+'.txt')
s=f.read_text(); s='Music + on-screen text only; no narration.\n'+s[s.index('On-screen text:'):] if 'On-screen text:' in s else '背景音乐 + 画面文字，无人声。\n'+s[s.index('画面大字：'):]
f.write_text(s)
