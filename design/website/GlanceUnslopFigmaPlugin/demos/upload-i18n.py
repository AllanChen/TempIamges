"""Upload the prepared localized films to Figma's single-use asset URLs."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import json,subprocess,sys
ROOT=Path(__file__).resolve().parent
manifest=json.loads((ROOT/'i18n-media-manifest.json').read_text())
urls=json.loads(sys.argv[1]);files=[]
for a in manifest['assets']:
 for role in ['gif','poster']:
  files.append({'asset':{k:a[k] for k in ['key','lang','theme','kind']},'role':role,'path':str(ROOT/a[role]),'mime':'image/gif' if role=='gif' else 'image/jpeg'})
assert len(files)==len(urls)==28
def upload(pair):
 item,url=pair
 r=subprocess.run(['curl','-fsSL','-X','POST','-H','Content-Type: '+item['mime'],'--data-binary','@'+item['path'],url['submitUrl']],capture_output=True,text=True)
 if r.returncode:return {**item,'error':r.stderr[:180]}
 try:d=json.loads(r.stdout)
 except:return {**item,'error':r.stdout[:200]}
 return {**item,'response':d}
with ThreadPoolExecutor(max_workers=4) as pool:results=list(pool.map(upload,zip(files,urls)))
(ROOT/'i18n-upload-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')
failed=[r for r in results if 'error'in r or not r.get('response',{}).get('success')]
print(json.dumps({'uploaded':len(results)-len(failed),'failures':failed},ensure_ascii=False))
if failed:sys.exit(1)
