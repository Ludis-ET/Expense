import { Router } from "express";
import { env } from "../../config/env.js";
import { asyncHandler } from "../../core/http.js";

/**
 * Public app-release metadata for the Android client.
 * No auth   the APK URL should be a direct download (GitHub Release, R2, etc.).
 */
export const appRouter = Router();

appRouter.get(
  "/android-update",
  asyncHandler(async (_req, res) => {
    const versionCode = env.ANDROID_LATEST_VERSION_CODE;
    const apkUrl = env.ANDROID_APK_URL;

    if (!versionCode || !apkUrl) {
      res.json({
        configured: false,
        updateAvailable: false,
        platform: "android",
      });
      return;
    }

    res.json({
      configured: true,
      platform: "android",
      versionCode,
      versionName: env.ANDROID_LATEST_VERSION_NAME ?? String(versionCode),
      apkUrl,
      changelog: env.ANDROID_CHANGELOG || "",
      forceUpdate: Boolean(env.ANDROID_FORCE_UPDATE),
      minSupportedVersionCode: env.ANDROID_MIN_VERSION_CODE ?? 1,
    });
  }),
);
