# Image opening entry consistency investigation

- Symptom: hotkey image previews used PreviewPanel while Finder double-click opened ImageInspectWindow.
- Root cause: `loadAndShowMedia` always rendered PreviewPanel, while `application(_:open:)` had a separate Image Inspect path.
- Fix: pure image selections now use the same centralized Image Inspect opener and preferred mode as Finder-opened images. Mixed/non-image results retain their existing viewers.
- Related changes: Image Inspect gained a localized Finder reveal button; its metadata fields and the remaining login/theme UI now have English and Simplified Chinese strings.
- Evidence: Swift syntax parsing, strings plist validation, zero missing localization keys, entry-routing assertions, Finder target assertions, and `git diff --check` passed.
- Regression test: the project has no test target; focused source-level routing assertions verify that pure-image routing precedes PreviewPanel loading and that compare-slot Finder targeting is retained.
- Status: DONE.
