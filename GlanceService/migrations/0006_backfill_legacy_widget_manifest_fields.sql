UPDATE widget_versions
SET manifest_json = json_set(
  manifest_json,
  '$.minimumGlanceVersion', COALESCE(NULLIF(json_extract(manifest_json, '$.minimumGlanceVersion'), ''), '2.0.0'),
  '$.updatedAt', COALESCE(NULLIF(json_extract(manifest_json, '$.updatedAt'), ''), updated_at),
  '$.signature', json(COALESCE(
    json_extract(manifest_json, '$.signature'),
    '{"algorithm":"Ed25519","keyID":"admin-console","value":"admin-created"}'
  ))
), updated_at = CURRENT_TIMESTAMP
WHERE widget_id = '55e64c7e-f079-448a-b5bd-7315b2589019'
  AND version = '1.0.0'
  AND status = 'published';
