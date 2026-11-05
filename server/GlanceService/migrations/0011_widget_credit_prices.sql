-- Initialize every existing version to one credit. D1 records this migration
-- once, so subsequent Admin price edits are retained across deployments.
-- Changing a third-party manifest invalidates its old signature. The catalog
-- and publication paths re-sign these manifests with the configured signing key.
UPDATE widget_versions
SET manifest_json = json_set(
  json_remove(manifest_json, '$.signature'),
  '$.creditCost', 1
)
WHERE json_extract(manifest_json, '$.creditCost') IS NOT 1
  AND COALESCE(json_extract(manifest_json, '$.official'), 0) <> 1;

UPDATE widget_versions
SET manifest_json = json_set(manifest_json, '$.creditCost', 1)
WHERE json_extract(manifest_json, '$.creditCost') IS NOT 1
  AND json_extract(manifest_json, '$.official') = 1;
