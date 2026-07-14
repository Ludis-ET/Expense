import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.join(__dirname, "..", "public", "icons");

/** Full-bleed square mark   required for reliable Chrome / Android install. */
function appIconSvg(rounded = false) {
  const radius = rounded ? "114" : "0";
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">
  <defs>
    <linearGradient id="bg" x1="12%" y1="0%" x2="88%" y2="100%">
      <stop offset="0%" stop-color="#34d399"/>
      <stop offset="42%" stop-color="#059669"/>
      <stop offset="100%" stop-color="#115e59"/>
    </linearGradient>
  </defs>
  <rect width="512" height="512" rx="${radius}" fill="url(#bg)"/>
  <path fill="none" stroke="#ffffff" stroke-width="22" stroke-linecap="round"
    d="M256 108a148 148 0 0 1 0 296a148 148 0 0 1 0-296"
    stroke-dasharray="412 54" stroke-dashoffset="27"/>
  <path fill="#ffffff"
    d="M322 186.5c-11.5-24.5-37.5-40.5-70.5-40.5-51 0-84.5 30-84.5 72.5 0 30.5 17.5 51.5 52.5 64l40.5 14.5c19 7 27.5 15.5 27.5 30.5 0 19.5-17.5 32.5-45.5 32.5-26.5 0-46-11.5-56.5-33.5l-36.5 19c17.5 37 52 55 93 55 56.5 0 93.5-33 93.5-79.5 0-34.5-19.5-56.5-56-69.5l-42-15c-16.5-6-23-13-23-25.5 0-17 15-28 39-28 21.5 0 37 9 45.5 26.5l36.5-19.5z"/>
</svg>`);
}

async function writePng(input, size, filename) {
  const dest = path.join(outDir, filename);
  await sharp(input)
    .resize(size, size, { fit: "fill" })
    .flatten({ background: { r: 5, g: 150, b: 105 } })
    .png({ compressionLevel: 9, force: true })
    .toFile(dest);
  const meta = await sharp(dest).metadata();
  console.log(`✓ ${filename} ${meta.width}×${meta.height}`);
}

async function main() {
  fs.mkdirSync(outDir, { recursive: true });

  const fullBleed = appIconSvg(false);
  const rounded = appIconSvg(true);

  // Install / PWA   full-bleed opaque squares (Chrome is strict about this)
  await writePng(fullBleed, 512, "icon-512.png");
  await writePng(fullBleed, 192, "icon-192.png");
  await writePng(fullBleed, 512, "icon-512-maskable.png");

  // Home-screen / apple / brand   rounded ok
  await writePng(rounded, 180, "apple-touch-icon.png");

  const tiny =
    Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#34d399"/><stop offset="100%" stop-color="#115e59"/></linearGradient></defs>
  <rect width="32" height="32" rx="8" fill="url(#g)"/>
  <circle cx="16" cy="16" r="9.5" fill="none" stroke="#fff" stroke-width="2.2"/>
  <path fill="#fff" d="M21.2 11.2c-.7-1.5-2.3-2.4-4.3-2.4-3.1 0-5.1 1.8-5.1 4.3 0 1.8 1 3 3.1 3.8l2.4.85c1.1.4 1.6.9 1.6 1.8 0 1.15-1 1.9-2.7 1.9-1.55 0-2.7-.65-3.3-1.95l-2.2 1.15c1 2.15 3 3.2 5.5 3.2 3.35 0 5.55-1.95 5.55-4.7 0-2-1.15-3.3-3.3-4.1l-2.5-.9c-1-.35-1.35-.75-1.35-1.5 0-1 .9-1.65 2.3-1.65 1.25 0 2.15.5 2.65 1.55l2.15-1.15z"/>
</svg>`);
  await writePng(tiny, 32, "favicon-32.png");
  await writePng(tiny, 16, "favicon-16.png");

  // Keep SVG source in sync (full-bleed for favicon.svg crispness at any size)
  fs.writeFileSync(
    path.join(outDir, "icon.svg"),
    appIconSvg(true).toString("utf8"),
  );
  console.log("Done   install icons are full-bleed opaque squares.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
