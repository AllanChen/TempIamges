export const OFFICIAL_MANIFESTS = [
  {
    schemaVersion: 1, id: "a0d3311a-b952-4831-8ee4-69f72c381a88", version: "1.0.0", name: "Remove Background",
    summary: "Remove an image background while preserving fine subject edges.", author: "Glance",
    iconURL: "https://resouces.pppron.com/f2e11606-79b8-4af5-88eb-e84448d41bdc.png", official: true,
    execution: { mode: "cloud" }, commands: [{ id: "remove-background", name: "Remove Background", description: "Create a transparent-background copy of the selected image.", inputTypes: ["image"], inputMimeTypes: ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"], outputs: ["image"], taskType: "image.remove-background.v1", requiresUpload: true, parameterSchema: { type: "object", properties: {}, additionalProperties: false } }],
    privacy: { uploadsMedia: true, notice: "The selected image will be uploaded to Glance for cloud processing." }, minimumGlanceVersion: "2.0.0", updatedAt: "2026-09-10T09:00:05.000Z",
    signature: { algorithm: "Ed25519", keyID: "glance-market-2026-01", value: "zy73uJQFinTMf3x6YRGqqbj0j5imnj6uSRC0d0brRnQ9HDO362kK3syq1oiDRHkAhfgmCvpyL81-79FFI-jwDA" }
  },
  {
    schemaVersion: 1, id: "ddd803cf-e9f2-4bd7-ad2e-1e6887188f7f", version: "1.0.0", name: "超分", summary: "图生图超分辨率，提升图片清晰度与细节。", author: "Glance",
    iconURL: "https://pub-69ca10693ab14c1c8f42d54f13c55810.r2.dev/cdf855c7-700f-47e6-bf4d-e9bb6de4793c.jpg", official: true, execution: { mode: "cloud" },
    commands: [{ id: "upscale", name: "超分", description: "上传一张图片，生成更高分辨率的清晰版本。", inputTypes: ["image"], inputMimeTypes: ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"], outputs: ["image"], taskType: "image.upscale.v1", requiresUpload: true, parameterSchema: { type: "object", properties: {}, additionalProperties: false } }],
    privacy: { uploadsMedia: true, notice: "The selected image will be uploaded to Glance for cloud processing." }, minimumGlanceVersion: "2.0.0", updatedAt: "2026-09-14T09:52:45.000Z",
    signature: { algorithm: "Ed25519", keyID: "glance-market-2026-01", value: "JoR297ENCoPT9aBPYdZfJ4qeyVIfINofrRFf_qRFz_hPsdSPbnIl7pgvceECMQlyTiIm4ppZBrlHFFbvHpqfBQ" }
  },
  {
    schemaVersion: 1, id: "7cc3967a-60ac-4677-9817-72f57f5ef5fa", version: "1.0.0", name: "RemoveBG 高级", summary: "图生图高级背景移除，保留精细主体边缘。", author: "Glance",
    iconURL: "https://rh-images.xiaoyaoyou.com/f3257c885c1aaa9dddfcc32ac04c6ba1/2026-09-10/fc739596d0b2188498113e409c99debc.gif?imageMogr2/format/webp/ignore-error/1&imageMogr2/format/webp/rquality/60/ignore-error/1/minisize/1", official: true, execution: { mode: "cloud" },
    commands: [{ id: "remove-bg-pro", name: "RemoveBG 高级", description: "上传一张图片，高级移除背景并生成透明背景副本。", inputTypes: ["image"], inputMimeTypes: ["image/jpeg", "image/png", "image/webp", "image/heic", "image/heif"], outputs: ["image"], taskType: "image.remove-bg-pro.v1", requiresUpload: true, parameterSchema: { type: "object", properties: {}, additionalProperties: false } }],
    privacy: { uploadsMedia: true, notice: "The selected image will be uploaded to Glance for cloud processing." }, minimumGlanceVersion: "2.0.0", updatedAt: "2026-09-14T09:52:28.000Z",
    signature: { algorithm: "Ed25519", keyID: "glance-market-2026-01", value: "6d8xIl0LbcrSYklhedefTLgl3PmSKSQyjScX5bCYl7IB7mGMIpBhbTDOt16Fut4ypiOOS7sQ8B8Gea9WlvvgBA" }
  }
] as const;
