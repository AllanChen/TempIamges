# Portable App UI reference assets

The active website revision is `website-portrait-views.json`. It overrides the earlier App/photo exports with website-specific Focus and Compare components exported from the independent website file. The source App UI remains unchanged.

The hero and comparison use `photos/portrait-original.png` and `photos/portrait-handbag-removed.png`, copied byte-for-byte from the user's named reference and its original. Editorial portraits in `paris-selfie.jpg` and `paris-balcony.jpg` fill the remaining views. Only these four photo files are included in the active bundle; the earlier landscape assets remain historical reference material.

These assets were exported read-only from the macOS App design in Figma. They let the website generator import the reference visuals into a **separate website file**, without looking up or writing to the App file at runtime.

`app-views.json` retains SVG geometry, editable SVG text, resolved theme colors, and image references. Images are deduplicated in the generated bundle. The source App file is not modified. Source IDs are provenance only; generation does not depend on their presence in the destination file.

The website's text, controls, and layout remain native Figma layers. Product illustrations are self-contained SVG groups, rather than live component links across files.
