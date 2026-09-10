# Side-by-side filmstrip selection investigation

- Symptom: replacing the left compare image could leave the original focused thumbnail highlighted, producing three highlighted thumbnails.
- Root cause: `ImageFilmstripView` rendered `focusedIndex` and both `compareIndices` as independent border states.
- Fix: when `compareIndices` exists, suppress the focus/browse selection and derive borders only from pair membership.
- Evidence: Swift syntax parsing, `git diff --check`, and a truth-table probe covering focus and compare states passed.
- Regression coverage: truth-table probe confirmed `selected=0, pair=(2,1)` produces `[1,2]`, not `[0,1,2]`. The project has no test target.
- Status: DONE.
