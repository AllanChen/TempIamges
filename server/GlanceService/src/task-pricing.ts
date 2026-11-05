// Quote arithmetic is independent of UI rounding and provider clip counts.
export const VIDEO_WATERMARK_ID = '783745bf-501d-4cfd-b2b8-69d32a8d90a8';
export type DurationBilling = { mode: 'duration'; unitSeconds: 10 };
export type VideoEvidence = { durationSeconds: number; byteSize: number; sha256: string };
export const VIDEO_LIMITS = { maxBytes: 50 * 1024 * 1024, maxSegments: 24, maxDurationSeconds: 187.2 };

export function validDurationBilling(value: unknown): value is DurationBilling {
  if (!value || typeof value !== 'object') return false;
  const billing = value as Record<string, unknown>;
  return billing.mode === 'duration' && billing.unitSeconds === 10;
}

export function validVideoEvidence(value: unknown): value is VideoEvidence {
  if (!value || typeof value !== 'object') return false;
  const v = value as VideoEvidence;
  return typeof v.durationSeconds === 'number' && Number.isFinite(v.durationSeconds) && v.durationSeconds > 0
    && Number.isSafeInteger(v.byteSize) && v.byteSize > 0
    && typeof v.sha256 === 'string' && /^[a-f0-9]{64}$/.test(v.sha256);
}

export function videoUnits(seconds: number) { return Math.ceil(seconds / 10); }
export function videoFits(v: VideoEvidence) {
  const segments = Math.ceil(v.durationSeconds / (v.durationSeconds <= 8 ? 8 : 7.8));
  return v.byteSize <= VIDEO_LIMITS.maxBytes && segments <= VIDEO_LIMITS.maxSegments;
}

export function matchesVideoEvidence(quoted: VideoEvidence, actual: VideoEvidence) {
  // AVFoundation and ffprobe may differ slightly at container boundaries, but
  // they must agree on both the charged units and the supported clip count.
  return validVideoEvidence(actual) && videoFits(actual)
    && quoted.sha256 === actual.sha256 && quoted.byteSize === actual.byteSize
    && Math.abs(quoted.durationSeconds - actual.durationSeconds) <= 0.1
    && videoUnits(quoted.durationSeconds) === videoUnits(actual.durationSeconds);
}
