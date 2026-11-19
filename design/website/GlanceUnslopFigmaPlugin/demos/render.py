"""Captioned, portrait-first feature films for the website. No app UI automation.

Actual Widget output pairs are reused where available. Other clips are explicitly
captioned workflow illustrations. Unslop: Damir Sokolovsky, CC BY 4.0.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import concurrent.futures, io, json, math, subprocess, sys

ROOT = Path(__file__).resolve().parent
SRC = ROOT / 'source'
OUT = ROOT / 'media'
OUT.mkdir(exist_ok=True)
W, H, FPS, SECONDS = 720, 480, 8, 6
BG, SURFACE, INK, SECONDARY, LINE, ACCENT = '#151514', '#242422', '#eae7e0', '#a19d94', '#34342f', '#c65a40'
FONT_EN = ROOT.parent / 'reference/fonts/Inter.ttf'
FONT_ZH = Path('/System/Library/Fonts/STHeiti Medium.ttc')

def feature(key, group, zh, en, zhdesc, endesc, zhsteps, ensteps, kind, before='person.png', after=None, credits=None, evidence='workflow'):
    return dict(key=key, group=group, title={'zh':zh,'en':en}, description={'zh':zhdesc,'en':endesc}, steps={'zh':zhsteps,'en':ensteps}, kind=kind, before=before, after=after or before, credits=credits, evidence=evidence)

FEATURES = [
 feature('edit-area','widget','局部编辑','Edit Area','涂抹要修改的位置，用文字说明想要的结果。','Paint a region and describe the change you want.', ['选中人物照片','涂抹选区，输入修改要求','查看局部编辑结果'], ['Open a portrait','Paint the area and describe the edit','Compare the edited region'], 'mask', after='edit-area.png', credits=1,evidence='existing-widget-result'),
 feature('upscale','widget','高清放大','Upscale','提高分辨率，放大检查人物的发丝与面部细节。','Increase resolution and inspect hair and facial detail.', ['打开需要放大的照片','选择高清放大','放大检查细节'], ['Open a small portrait','Choose Upscale','Inspect the larger image'], 'upscale',credits=30),
 feature('background','widget','人物背景分离','Background Remover Pro','分离人物与背景，得到可用于设计的透明 PNG。','Separate the person from the background as a transparent PNG.', ['打开人物照片','选择人物背景分离','查看透明背景结果'], ['Open a portrait','Remove the background','Use the transparent PNG'], 'pair',after='person-transparent.png',credits=20,evidence='existing-user-result'),
 feature('remove-objects','widget','移除物体','Remove Objects','用英文描述不想保留的物体，检查移除前后的变化。','Describe unwanted objects in English and compare the result.', ['打开带手包的原图','输入：Remove the handbag','对比手包移除结果'], ['Open the original portrait','Enter: Remove the handbag','Compare the result'], 'pair',after='person-clean.png',credits=30,evidence='exact-user-reference'),
 feature('video-watermark','widget','视频去水印','Video Watermark Remover','清除视频中的水印，处理后合成为一个视频。','Remove a watermark from a video and return one merged result.', ['导入视频素材','选择视频去水印','播放处理后的视频'], ['Import a video','Choose Video Watermark Remover','Play the cleaned result'], 'watermark-video',credits=100),
 feature('image-host','widget','免费图床','Free Image Host','上传图片或视频，复制生成的链接进行分享。','Upload an image or video and copy its shareable link.', ['选择图片或视频','上传并生成链接','复制分享链接'], ['Choose an image or video','Upload and generate a link','Copy the shareable link'], 'link',credits=29),
 feature('image-prompt','widget','图片转提示词','Image to Prompt','把图片内容转换为可复用的文字描述。','Turn an image into a reusable written description.', ['选择一张人物照片','分析画面内容','复制文字描述'], ['Choose a portrait','Describe its content','Copy the image description'], 'prompt',credits=20),
 feature('image-watermark','widget','图片去水印','Watermark Remover','去除图片中的水印、文字与标记。','Remove watermarks, text and marks from an image.', ['打开带演示水印的图片','选择图片去水印','查看清理后的画面'], ['Open a demo-watermarked image','Choose Watermark Remover','Inspect the cleaned image'], 'watermark',credits=30),
 feature('expand','widget','智能扩图','Expand Image','向画面外延展，让人物照片获得更多构图空间。','Extend the frame to give a portrait more room.', ['打开原始构图','选择智能扩图','对比扩展后的画面'], ['Open the original framing','Choose Expand Image','Compare the extended frame'], 'pair',before='expand-before.png',after='expand-after.png',credits=30,evidence='existing-widget-result'),
 feature('outfit','widget','AI 换装','Outfit Swap','使用人物图和服装参考图，查看换装后的效果。','Use a person image and an outfit reference to change clothing.', ['添加人物与服装参考','选择 AI 换装','对比穿搭变化'], ['Add a person and outfit reference','Choose Outfit Swap','Compare the clothing'], 'pair',before='outfit-before.webp',after='outfit-after.png',credits=30,evidence='existing-widget-result'),
 feature('reframe','widget','图生图','Redraw & Reframe','重新生成画面，并按选择的画幅比例输出。','Regenerate an image at the aspect ratio you choose.', ['选择原图','选择画幅与生成要求','查看重新构图的结果'], ['Choose the original','Select a ratio and instructions','Review the regenerated image'], 'pair',after='reframe.png',credits=30,evidence='existing-widget-result'),
 feature('export-formats','pro','格式转换与另存为','Convert & Save As','导出 PNG、JPG 或 WebP，把结果保存成新文件。','Export PNG, JPG or WebP and save a new file.', ['打开原始图片','选择 PNG、JPG 或 WebP','另存为新的图片文件'], ['Open the original','Choose PNG, JPG or WebP','Save a new image file'], 'formats'),
 feature('export-icon','pro','导出 Mac 图标','Export a Mac Icon','把图片导出为 ICNS，用作 Mac 图标素材。','Export an image as an ICNS file for a Mac icon.', ['打开图标素材','选择导出为 Icon','保存 ICNS 图标文件'], ['Open your icon artwork','Choose Save as Icon','Save the ICNS file'], 'icon'),
 feature('compress','pro','图片压缩','Compress Images','调整质量与格式，保存体积更小的文件。','Choose quality and format to save a smaller file.', ['打开原图','调整压缩质量','保存更小的文件'], ['Open the original','Adjust compression quality','Save the smaller file'], 'compress'),
 feature('resize','pro','调整图片尺寸','Resize Images','按比例调整像素尺寸，为分享或交付准备图片。','Scale the pixel dimensions for sharing or delivery.', ['查看原图尺寸','选择缩放比例','保存调整后的图片'], ['Check the original size','Choose the scale','Save the resized image'], 'resize'),
 feature('copy-image','pro','复制图片','Copy an Image','把图片复制到剪贴板，再粘贴到其他应用。','Copy an image to the clipboard and paste it into another app.', ['打开原图','选择复制图片','粘贴到其他应用'], ['Open the original','Choose Copy Image','Paste into another app'], 'copy'),
 feature('rotate-save','pro','旋转后导出','Rotate & Export','向左或向右旋转显示，再将当前方向导出。','Rotate left or right and export the current orientation.', ['查看原始方向','向左或向右旋转','导出旋转后的文件'], ['View the original orientation','Rotate left or right','Export the rotated file'], 'rotate'),
 feature('flip-save','pro','翻转后导出','Flip & Export','水平或垂直翻转显示，再将当前画面导出。','Flip horizontally or vertically, then export the image.', ['查看原始画面','水平或垂直翻转','导出翻转后的文件'], ['View the original','Flip horizontally or vertically','Export the flipped image'], 'flip'),
 feature('base64-encode','pro','图片转 Base64','Image to Base64','将图片转换为 Base64，直接复制编码内容。','Convert an image to Base64 and copy its encoded data.', ['打开人物图片','选择复制为 Base64','复制编码内容'], ['Open a portrait','Choose Copy as Base64','Copy the encoded data'], 'encode'),
 feature('base64-decode','pro','Base64 转图片','Base64 to Image','粘贴 Base64 数据，恢复为可查看的图片。','Paste Base64 data and recover a viewable image.', ['粘贴 Base64 数据','选择转换为图片','查看解码后的图片'], ['Paste Base64 data','Convert it to an image','View the decoded image'], 'decode'),
]

def font(size, lang): return ImageFont.truetype(str(FONT_ZH if lang == 'zh' else FONT_EN), size)
def text(im, xy, value, size=28, color=INK, lang='en', anchor=None):
    ImageDraw.Draw(im).text(xy, value, font=font(size,lang), fill=color, anchor=anchor)
def wrapped(value, limit, size, lang):
    f = font(size,lang); out=[]; row=''
    units=list(value) if lang=='zh' else value.split(' ')
    for word in units:
        candidate=row+(' ' if row and lang=='en' else '')+word
        if f.getlength(candidate)>limit and row: out.append(row);row=word
        else:row=candidate
    if row:out.append(row)
    return out
def box(im, rect, fill=SURFACE, radius=8, outline=None): ImageDraw.Draw(im).rounded_rectangle(rect,radius,fill,outline=outline)

IMAGES={}
def photo(name):
    if name not in IMAGES: IMAGES[name]=Image.open(SRC/name).convert('RGBA')
    return IMAGES[name].copy()
def checker(im,rect):
    x,y,w,h=map(round,rect);d=ImageDraw.Draw(im)
    for yy in range(y,y+h,16):
        for xx in range(x,x+w,16): d.rectangle((xx,yy,min(xx+15,x+w),min(yy+15,y+h)),fill='#e7e4dc' if ((xx-x)//16+(yy-y)//16)%2 else '#bcb9b0')
def place(im,src,rect,fit=True,checkerboard=False):
    x,y,w,h=map(round,rect)
    if checkerboard:checker(im,rect)
    image=ImageOps.contain(src,(w,h),Image.Resampling.LANCZOS) if fit else ImageOps.fit(src,(w,h),Image.Resampling.LANCZOS)
    px=x+(w-image.width)//2;py=y+(h-image.height)//2
    im.paste(image,(px,py),image if image.mode=='RGBA' else None)
def cursor(im, progress, target=(520,225)):
    # Shizuka's existing ease-out curve: cubic-bezier(.22, 1, .36, 1).
    x=min(1,progress*1.8);lo,hi=0.,1.
    for _ in range(12):
        u=(lo+hi)/2;cx=3*(1-u)**2*u*.22+3*(1-u)*u*u*.36+u**3
        if cx<x:lo=u
        else:hi=u
    q=3*(1-u)**2*u+3*(1-u)*u*u+u**3
    px=round(668+(target[0]-668)*q);py=round(346+(target[1]-346)*q)
    d=ImageDraw.Draw(im)
    if progress>.75:d.ellipse((px-15,py-15,px+15,py+15),outline=ACCENT,width=2)
    d.polygon([(px,py),(px+5,py+27),(px+11,py+19),(px+20,py+22)],fill=INK,outline='#0f0f0e')
def label(im,x,y,value,lang):
    width=round(font(24,lang).getlength(value))+24;box(im,(x,y,x+width,y+34),'#151514',6);text(im,(x+12,y+3),value,24,INK,lang)

def view(f, lang, phase, progress):
    im=Image.new('RGB',(W,H),BG); d=ImageDraw.Draw(im)
    text(im,(24,14),f['title'][lang],30,INK,lang)
    # Explicitly distinguish stored results from explanatory workflows.
    badge=('结果演示' if f['evidence']!='workflow' else '流程演示') if lang=='zh' else ('Result demo' if f['evidence']!='workflow' else 'Workflow demo')
    text(im,(W-24,24),badge,20,SECONDARY,lang,'ra')
    d.line((24,58,696,58),fill=LINE)
    source=photo(f['before']);result=photo(f['after']);kind=f['kind']
    area=(36,74,648,286)
    if kind in ['pair','mask']:
        if phase<2:
            place(im,source,(74 if phase==1 else 170,74,280 if phase==1 else 380,286))
            if phase==1 and kind=='mask':
                # Painted selection is an overlay, not an altered source asset.
                overlay=Image.new('RGBA',im.size);od=ImageDraw.Draw(overlay);od.ellipse((246,218,293,282),fill=(198,90,64,110),outline=ACCENT,width=3);im=Image.alpha_composite(im.convert('RGBA'),overlay).convert('RGB')
            if phase==1:
                box(im,(388,110,684,294),SURFACE,8,LINE)
                text(im,(410,130),'AI Widgets',24,SECONDARY,'en')
                box(im,(400,184,672,268),'#34342f',6)
                for j,line in enumerate(wrapped(f['title'][lang],246,24,lang)):text(im,(414,196+j*28),line,24,INK,lang)
                cursor(im,progress)
        else:
            place(im,source,(38,74,310,286));place(im,result,(372,74,310,286),checkerboard=f['key']=='background')
            if progress<.45:
                # Reveal the stored output, then hold it long enough to compare.
                old=Image.new('RGB',im.size,BG);place(old,source,(372,74,310,286));cut=round(372+310*min(1,progress/.45))
                im.paste(old.crop((cut,74,682,360)),(cut,74));ImageDraw.Draw(im).line((cut,74,cut,360),fill=INK,width=2)
            label(im,42,320,'原图' if lang=='zh' else 'Original',lang);label(im,376,320,'结果' if lang=='zh' else 'Result',lang)
    elif kind=='upscale':
        crop=source.crop((180,90,650,620))
        if phase<2:crop=crop.resize((48,54),Image.Resampling.BOX).resize((310,286),Image.Resampling.NEAREST)
        place(im,crop,area)
        if phase==1:label(im,400,306,'高清放大' if lang=='zh' else 'Upscale',lang)
        if phase==2:label(im,400,306,'检查细节' if lang=='zh' else 'Inspect detail',lang)
    elif kind.startswith('watermark'):
        # A labelled demo watermark is composited over a portrait-derived clip.
        place(im,source,(142,74,436,286))
        if kind=='watermark-video':
            label(im,38,80,('视频' if lang=='zh' else 'Video')+' 00:0'+str(int(progress*2+phase)),lang)
            d.line((54,354,666,354),fill=LINE,width=4);d.line((54,354,round(54+(phase+progress)/3*612),354),fill=INK,width=4)
        if phase<2:
            box(im,(240,182,480,228),'#eee9df',6);text(im,(360,188),'GLANCE DEMO',26,'#1c1b19','en','ma')
    elif kind in ['link','prompt','encode','decode','copy']:
        if phase<2 and kind!='decode':place(im,source,(52,78,250,278))
        else:place(im,source,(52,78,250,278))
        box(im,(326,84,682,346),SURFACE,8,LINE)
        values={
          'link': ['图片 / 视频','上传获取链接','复制分享链接'] if lang=='zh' else ['Image / video','Generate a link','Copy link'],
          'prompt':['识别人物与场景','短发女性，针织上衣','自然光，城市街景'] if lang=='zh' else ['Person and setting','A woman in a knit top','Daylight, city setting'],
          'encode':['图片 → Base64','data:image/png;','base64,iVBOR...'] if lang=='zh' else ['Image → Base64','data:image/png;','base64,iVBOR...'],
          'decode':['Base64 → 图片','data:image/png;','图片已解码'] if lang=='zh' else ['Base64 → Image','data:image/png;','Image decoded'],
          'copy':['Glance','复制图片','已粘贴到文档'] if lang=='zh' else ['Glance','Copy Image','Pasted into a document']
        }[kind]
        for j,value in enumerate(values[:phase+1]):
            for k,line in enumerate(wrapped(value,308,26,lang)):text(im,(348,112+j*70+k*30),line,26,INK if j==phase else SECONDARY,lang)
        if kind=='decode' and phase<2:box(im,(52,78,302,356),SURFACE,8);text(im,(177,202),'Base64',28,SECONDARY,'en','mm')
    else:
        image=source
        if kind=='rotate' and phase>0:image=source.rotate(90 if phase==1 else -90,expand=True)
        if kind=='flip' and phase>0:image=ImageOps.mirror(source) if phase==1 else ImageOps.flip(source)
        if kind=='resize' and phase>0:image=source.resize((471,836),Image.Resampling.LANCZOS)
        if kind=='icon':image=ImageOps.fit(source,(240,240),Image.Resampling.LANCZOS,centering=(.5,.22))
        place(im,image,(38,76,318,282))
        box(im,(382,88,684,340),SURFACE,8,LINE)
        values={
          'formats':['PNG','JPG','WebP'], 'icon':['Icon','.icns','Mac'],
          'compress':['PNG',('质量 75%' if lang=='zh' else 'Quality 75%'),('较小的文件' if lang=='zh' else 'Smaller file')],
          'resize':['941 × 1672','50%','471 × 836'],
          'rotate':['0°','90°','−90°'],
          'flip':(['原图','水平翻转','垂直翻转'] if lang=='zh' else ['Original','Horizontal','Vertical'])
        }[kind]
        for j,value in enumerate(values):
            y=118+j*66
            if j==phase:box(im,(398,y-7,668,y+40),'#3b3b36',6)
            text(im,(416,y),value,27,INK if j==phase else SECONDARY,lang)
    if phase==1 and kind not in ['pair','mask']:cursor(im,progress)
    # Quiet step markers and burnt-in explanation belong to every exported clip.
    d=ImageDraw.Draw(im)
    for i in range(3):d.rounded_rectangle((24+i*32,376,44+i*32,380),2,fill=INK if i==phase else LINE)
    lines=wrapped(f['steps'][lang][phase],672,28,lang)
    for i,line in enumerate(lines):text(im,(24,398+i*34),line,28,INK,lang)
    return im

def render_job(job):
    f,lang=job;key=f['key'];name=f'{key}-{lang}'
    frames=[]
    for phase in range(3):
        for i in range(FPS*2):
            # Transform content only where the feature needs it; no decorative motion.
            frames.append(view(f,lang,phase,i/(FPS*2-1)))
    # A fixed palette avoids GIF shimmer; stable repeated frames merge naturally.
    sheet=Image.new('RGB',(W*3,H))
    for i in range(3):sheet.paste(frames[i*FPS*2+8],(i*W,0))
    palette=sheet.quantize(colors=192,method=Image.Quantize.MEDIANCUT)
    frames=[frames[-1]]*4+frames
    indexed=[im.quantize(palette=palette,dither=Image.Dither.NONE) for im in frames]
    indexed[0].save(OUT/f'{name}.gif',save_all=True,append_images=indexed[1:],duration=125,loop=0,optimize=True,disposal=2)
    frames[0].save(OUT/f'{name}-poster.jpg',quality=88)
    strip=Image.new('RGB',(W*3,H))
    for i in range(3):strip.paste(frames[i*FPS*2+12],(i*W,0))
    strip.resize((1080,240)).save(OUT/f'{name}-storyboard.jpg',quality=86)
    proc=subprocess.Popen(['ffmpeg','-v','error','-y','-f','rawvideo','-pix_fmt','rgb24','-s',f'{W}x{H}','-r',str(FPS),'-i','-','-an','-c:v','libx264','-preset','fast','-crf','23','-pix_fmt','yuv420p','-movflags','+faststart',str(OUT/f'{name}.mp4')],stdin=subprocess.PIPE)
    for im in frames:proc.stdin.write(im.tobytes())
    proc.stdin.close()
    if proc.wait():raise RuntimeError(name+' MP4 encoding failed')
    gif=Image.open(OUT/f'{name}.gif')
    durations=[]
    for i in range(gif.n_frames):gif.seek(i);durations.append(gif.info.get('duration',0))
    if gif.n_frames<3 or sum(durations)<5000:raise ValueError(name+' must be animated for six seconds')
    return dict(key=key,lang=lang,gif=f'media/{name}.gif',mp4=f'media/{name}.mp4',poster=f'media/{name}-poster.jpg',frames=gif.n_frames,durationMs=sum(durations),bytes=(OUT/f'{name}.gif').stat().st_size)

if __name__=='__main__':
    selected=[f for f in FEATURES if '--one' not in sys.argv or f['key']==sys.argv[sys.argv.index('--one')+1]]
    jobs=[(f,lang) for f in selected for lang in ['zh','en']]
    results=[]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(render_job,jobs):
            results.append(result);print('Rendered',result['key'],result['lang'],result['frames'],'frames',round(result['bytes']/1024),'KB',flush=True)
    # A targeted rerender keeps the complete media inventory in the manifest.
    inventory=[]
    for f in FEATURES:
        for lang in ['zh','en']:
            name=f"{f['key']}-{lang}";path=OUT/f'{name}.gif'
            if not path.exists() or not (OUT/f'{name}.mp4').exists():continue
            gif=Image.open(path);duration=0
            for i in range(gif.n_frames):gif.seek(i);duration+=gif.info.get('duration',0)
            inventory.append(dict(key=f['key'],lang=lang,gif=f'media/{name}.gif',mp4=f'media/{name}.mp4',poster=f'media/{name}-poster.jpg',frames=gif.n_frames,durationMs=duration,bytes=path.stat().st_size))
    (ROOT/'manifest.json').write_text(json.dumps(dict(width=W,height=H,features=FEATURES,assets=inventory),ensure_ascii=False,indent=2)+'\n')
    print('DONE:',len(results),'captioned GIF + MP4 pairs',flush=True)
