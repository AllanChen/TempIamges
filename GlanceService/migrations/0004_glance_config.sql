INSERT OR IGNORE INTO service_settings (key, value, updated_at)
SELECT 'glance_config',
       CASE WHEN value = '0'
            THEN '{"locationBasedUpload":false}'
            ELSE '{"locationBasedUpload":true}' END,
       CURRENT_TIMESTAMP
FROM service_settings
WHERE key = 'location_upload_routing';

INSERT OR IGNORE INTO service_settings (key, value, updated_at)
VALUES ('glance_config', '{"locationBasedUpload":true}', CURRENT_TIMESTAMP);
