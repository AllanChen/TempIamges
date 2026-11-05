"""Prepare and render Japanese/German editions of the supplied Peek promo.

Run with the repository's .venv/bin/python. Voice AIFFs are synthesized
separately with macOS `say`; this script never launches or controls Glance.
"""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent
SOURCE = Path('/Users/allan/Downloads/promo-peek-sample-no-captions.mp4')
DURATION = 41.6
SLOTS = [(1.6, 6.6), (6.8, 9.8), (10.0, 14.9), (15.1, 19.8),
         (28.0, 31.0), (36.35, 39.8), (39.95, 41.55)]
COPY = {
    'ja': {
        'voice': 'Kyoko', 'rate': 220, 'language': 'jpn',
        'font': '/System/Library/Fonts/ヒラギノ角ゴシック W4.ttc',
        'intro': '素早く確認。流れを止めない。',
        'outro': '素早く確認。必要なときはAIで編集。',
        'shortcut': 'Option + スペース',
        'instruction': 'パスを選択 → プレビュー',
        'spoken': [
            '集中していると、AIがファイルのパスを示し、確認を求めてきます。',
            'アプリを切り替えると、集中が途切れます。',
            'パスを選び、オプションとスペース。その場でプレビュー。',
            'ファイルも、文書も、リンクも。チャットを離れずに確認。',
            'そして、プレビューは始まりにすぎません。',
            'グランス。すぐに確認。必要ならAIで編集。',
            'グランスプレビュードットコム。',
        ],
        'subtitles': [
            '集中していると、AIがファイルのパスを示し、\n確認を求めてきます。',
            'アプリを切り替えると、集中が途切れます。',
            'パスを選び、Option + スペース。\nその場でプレビュー。',
            'ファイルも、文書も、リンクも。\nチャットを離れずに確認。',
            'そして、プレビューは始まりにすぎません。',
            'Glance。すぐに確認。必要ならAIで編集。',
            'glancepreview.com',
        ],
    },
    'de': {
        'voice': 'Anna', 'rate': 190, 'language': 'deu',
        'font': '/System/Library/Fonts/Helvetica.ttc',
        'intro': 'Schnell ansehen. Im Flow bleiben.',
        'outro': 'Schnell ansehen. Bei Bedarf mit KI bearbeiten.',
        'shortcut': 'Option + Leertaste',
        'instruction': 'Pfad auswählen → Vorschau',
        'spoken': [
            'Du bist im Flow. Dann nennt dir die KI einen lokalen Dateipfad, den du prüfen sollst.',
            'Dafür die App wechseln? Schon ist der Fokus weg.',
            'Mit Glance: Pfad markieren, Option und Leertaste drücken. Sofort erscheint die Vorschau.',
            'Dateien, Dokumente, Links. Vorschau direkt im Chat.',
            'Und die Vorschau ist erst der Anfang.',
            'Glance. Schnell ansehen. Bei Bedarf mit KI bearbeiten.',
            'Glance Preview Punkt com.',
        ],
        'subtitles': [
            'Du bist im Flow. Dann nennt dir die KI einen\nlokalen Dateipfad, den du prüfen sollst.',
            'Dafür die App wechseln?\nSchon ist der Fokus weg.',
            'Mit Glance: Pfad markieren, Option + Leertaste drücken.\nSofort erscheint die Vorschau.',
            'Dateien, Dokumente, Links.\nVorschau direkt im Chat.',
            'Und die Vorschau ist erst der Anfang.',
            'Glance. Schnell ansehen.\nBei Bedarf mit KI bearbeiten.',
            'glancepreview.com',
        ],
    },
}


def run(args):
    subprocess.run([str(a) for a in args], check=True)


def probe(path):
    return json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-show_format', '-show_streams', '-of', 'json', str(path)]))


def stamp(seconds):
    ms = round(seconds * 1000)
    return f'{ms // 3600000:02}:{ms // 60000 % 60:02}:{ms // 1000 % 60:02},{ms % 1000:03}'


def prepare():
    from PIL import Image, ImageDraw
    badge = Image.new('RGBA', (722 * 3, 164 * 3))
    ImageDraw.Draw(badge).rounded_rectangle((0, 0, 722 * 3 - 1, 164 * 3 - 1),
                                          radius=26 * 3, fill=(17, 17, 17, 255))
    badge.resize((722, 164), Image.Resampling.LANCZOS).save(ROOT / 'shortcut-badge.png')
    for lang, copy in COPY.items():
        folder = ROOT / lang
        (folder / 'voice').mkdir(parents=True, exist_ok=True)
        for i, text in enumerate(copy['spoken']):
            (folder / 'voice' / f'{i:02}.txt').write_text(text + '\n')
        for key in ['intro', 'outro', 'shortcut', 'instruction']:
            (folder / f'{key}.txt').write_text(copy[key])
    (ROOT / 'copy.json').write_text(json.dumps(COPY, ensure_ascii=False, indent=2) + '\n')


def render(lang):
    copy = COPY[lang]
    folder = ROOT / lang
    inputs = []
    filters = []
    report = []
    for i, (start, end) in enumerate(SLOTS):
        raw = folder / 'voice' / f'{i:02}.aiff'
        duration = float(probe(raw)['format']['duration'])
        # Trim TTS trailing padding; fit each sentence to its visual beat without cutting words.
        clean = folder / 'voice' / f'{i:02}.wav'
        run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', raw,
             '-af', 'silenceremove=start_periods=1:start_duration=0.01:start_threshold=-50dB,'
             'areverse,silenceremove=start_periods=1:start_duration=0.01:start_threshold=-50dB,areverse',
             '-ar', '48000', '-ac', '1', clean])
        duration = float(probe(clean)['format']['duration'])
        tempo = max(1.0, duration / (end - start - 0.05))
        actual_end = start + duration / tempo
        inputs += ['-i', clean]
        filters.append(f'[{i}:a]atempo={tempo:.6f},afade=t=out:st={max(0,duration/tempo-0.02):.6f}:d=0.02,'
                       f'adelay={round(start*1000)}:all=1[a{i}]')
        report.append({'start': start, 'end': actual_end, 'raw_seconds': duration,
                       'tempo': tempo, 'text': copy['subtitles'][i]})
    filters.append(''.join(f'[a{i}]' for i in range(len(SLOTS))) +
                   f'amix=inputs={len(SLOTS)}:normalize=0,apad,atrim=duration={DURATION},'
                   'loudnorm=I=-16:TP=-1.5:LRA=7[audio]')
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', *inputs,
         '-filter_complex', ';'.join(filters), '-map', '[audio]', '-c:a', 'pcm_s16le', folder / 'narration.wav'])
    srt = ROOT / f'promo-peek-{lang}.srt'
    srt.write_text('\n\n'.join(f"{i+1}\n{stamp(r['start'])} --> {stamp(r['end'])}\n{r['text']}"
                               for i, r in enumerate(report)) + '\n')
    (folder / 'timing.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    # Only promotional text is replaced. Recorded terminal/app UI stays as captured.
    font = copy['font']
    def title(key, y, size, enabled, color='0xb9b9b9'):
        text_font = ('/System/Library/Fonts/Supplemental/Arial Unicode.ttf'
                     if lang == 'de' and key == 'instruction' else font)
        return (f"drawtext=fontfile='{text_font}':textfile='{folder / (key + '.txt')}':"
                f"fontsize={size}:fontcolor={color}:x=(w-text_w)/2:y={y}:enable='{enabled}'")
    video_filters = [
        "drawbox=x=570:y=568:w=780:h=62:color=0x0B0B0D:t=fill:enable='lt(t,2)'",
        title('intro', 580, 29, 'lt(t,2)'),
        "drawbox=x=500:y=540:w=920:h=60:color=0x0B0B0D:t=fill:enable='gte(t,36.3)'",
        title('outro', 553, 27, 'gte(t,36.3)'),
    ]
    # Exact shortcut interval is supplied from the source review.
    shortcut_start, shortcut_end = 6.4, 13.533333333
    interval = f'gte(t,{shortcut_start})*lt(t,{shortcut_end})'
    video_filters += [
        title('shortcut', 850, 58, interval, 'white'),
        title('instruction', 929, 29, interval, '0xf4b447'),
    ]
    video_filter = (f"[0:v][2:v]overlay=x=600:y=820:enable='{interval}'," +
                    ','.join(video_filters) + '[video]')
    (folder / 'video-filter.txt').write_text(video_filter)
    output = ROOT / f'promo-peek-{lang}-no-captions.mp4'
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', SOURCE,
         '-i', folder / 'narration.wav', '-i', ROOT / 'shortcut-badge.png',
         '-filter_complex', video_filter,
         '-map', '[video]', '-map', '1:a:0', '-c:v', 'libx264', '-preset', 'fast',
         '-crf', '18', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '192k',
         '-metadata:s:a:0', f"language={copy['language']}",
         '-metadata', f'title=Glance Peek — {lang.upper()}',
         '-movflags', '+faststart', '-t', str(DURATION), output])
    info = probe(output)
    assert abs(float(info['format']['duration']) - DURATION) < 0.1
    assert info['streams'][0]['width'] == 1920 and info['streams'][0]['height'] == 1080
    run(['ffmpeg', '-v', 'error', '-i', output, '-f', 'null', '-'])
    print(json.dumps({'output': str(output), 'seconds': info['format']['duration'],
                      'max_tempo': max(r['tempo'] for r in report)}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['prepare', 'ja', 'de'])
    action = parser.parse_args().action
    prepare() if action == 'prepare' else render(action)
