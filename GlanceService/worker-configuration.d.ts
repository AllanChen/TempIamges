interface Env {
  DB: D1Database;
  BUCKET: R2Bucket;
  PUBLIC_ORIGIN: string;
  SESSION_SECRET: string;
  ADMIN_TOKEN: string;
  WORKER_TOKEN_PEPPER: string;
  MEDIA_SIGNING_SECRET: string;
}
