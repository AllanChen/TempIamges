# Peek promo — Japanese and German

Source: `/Users/allan/Downloads/promo-peek-sample-no-captions.mp4`.

- [Japanese video](promo-peek-ja-no-captions.mp4) · [Japanese SRT](promo-peek-ja.srt)
- [German video](promo-peek-de-no-captions.mp4) · [German SRT](promo-peek-de.srt)

Both videos preserve the source's 1920 × 1080 resolution, 30 fps and 41.6-second
picture timeline. They contain localized synthetic narration, opening/closing
taglines, and the Option + Space promotional overlay. Subtitles are separate
UTF-8 SRT files, without burned-in dialogue captions. Glance branding, website,
recorded terminal content, and recorded application menus remain as captured.

Narration uses the installed macOS voices Kyoko (Japanese) and Anna (German).
Original English narration is replaced; the source is silent during its long
demonstration pauses. The new narration retains those pauses. Sentence timing
and small pitch-preserving speed adjustments are recorded in each language's
`timing.json`. Maximum speed adjustment is approximately 11%.

`copy.json` and each `voice/*.txt` contain the editable copy. Voice AIFF files
and final mixed WAV files are retained for revisions.

## Source review

83 frames sampled at 2 fps, plus frame-by-frame checks of title/shortcut timing.
English speech was transcribed locally with Whisper base, then obvious ASR
errors ("Your deep and flow", "Peak") were corrected using context and the
captioned reference video. No Glance UI was opened or operated.

| Time | Picture | Narration intent |
| --- | --- | --- |
| 0–2 s | Glance opening title | Establish focus / flow |
| 2–6.4 s | Select local file path in terminal | AI supplies a path to inspect |
| 6.4–10.1 s | Image preview | Switching apps interrupts focus |
| 10.1–15.2 s | Select paths, show two images | Select path, Option + Space, preview in place |
| 15.2–25 s | Side-by-side and slider comparison | Files, documents, links without leaving chat; then pause |
| 25–34.6 s | Image view and Widgets menu | Preview is only the beginning |
| 34.6–36.3 s | Return to terminal | Pause |
| 36.3–41.6 s | Glance closing title and website | Quick preview; edit with AI when needed |

The recording opens the Widgets menu but does not execute an AI task. The
localized narration therefore makes no claim that an AI result is shown.

## Reproduction

From the repository root:

```sh
.venv/bin/python design/marketing/videos/promo-peek-localized/localize.py prepare
```

Synthesize `ja/voice/00.txt` through `06.txt` with `say -v Kyoko -r 220`, and
`de/voice/00.txt` through `06.txt` with `say -v Anna -r 190`, writing each to its
matching `.aiff` path. Then render:

```sh
.venv/bin/python design/marketing/videos/promo-peek-localized/localize.py ja
.venv/bin/python design/marketing/videos/promo-peek-localized/localize.py de
```

The renderer checks stream dimensions and duration and decodes each entire
output with FFmpeg to check file integrity. Exported stills allow inspection
of localized title and shortcut typography without operating the app.
