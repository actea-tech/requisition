// Next.js `output: "standalone"` produces a self-contained server.js but
// deliberately excludes `public/` and `.next/static/` — copy them in so the
// standalone build actually serves static assets. Cross-platform (Node
// fs, not shell `cp -r`) since dev happens on Windows and the deploy target
// is Linux.
import { cpSync, existsSync } from "node:fs";

const copies = [
  ["public", ".next/standalone/public"],
  [".next/static", ".next/standalone/.next/static"],
];

for (const [from, to] of copies) {
  if (!existsSync(from)) {
    console.warn(`skip (not found): ${from}`);
    continue;
  }
  cpSync(from, to, { recursive: true });
  console.log(`copied ${from} -> ${to}`);
}
