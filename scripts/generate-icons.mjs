import sharp from "sharp";
import { mkdirSync } from "fs";

const src = "public/actea-logo.png";

mkdirSync("app", { recursive: true });

const targets = [
  { out: "app/icon.png", size: 128 },
  { out: "app/apple-icon.png", size: 180 },
  { out: "public/actea-logo-192.png", size: 192 },
  { out: "public/actea-logo-512.png", size: 512 },
];

for (const { out, size } of targets) {
  await sharp(src)
    .resize(size, size, { fit: "contain", background: { r: 255, g: 255, b: 255, alpha: 0 } })
    .png()
    .toFile(out);
  console.log("wrote", out);
}
