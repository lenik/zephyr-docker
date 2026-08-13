#!/usr/bin/env node
/**
 * context.d/050app-package.mjs — pin runtime package.json from backend deps.
 * Env: ZEPHYR_REPO (or REPO), ZEPHYR_CTX (or CTX)
 */
import fs from "node:fs";
import path from "node:path";

const repo = process.env.ZEPHYR_REPO || process.env.REPO;
const ctx = process.env.ZEPHYR_CTX || process.env.CTX;
if (!repo || !ctx) {
  console.error("REPO/CTX (or ZEPHYR_REPO/ZEPHYR_CTX) required");
  process.exit(1);
}

const backend = JSON.parse(
  fs.readFileSync(path.join(repo, "backend/package.json"), "utf8"),
);
const names = {
  ...backend.dependencies,
  prisma: backend.devDependencies?.prisma || "6.19.3",
  tsx: backend.devDependencies?.tsx || "4.23.5",
};
const deps = {};
for (const name of Object.keys(names)) {
  const candidates = [
    path.join(repo, "backend/node_modules", name, "package.json"),
    path.join(repo, "node_modules", name, "package.json"),
  ];
  let ver = null;
  for (const c of candidates) {
    if (fs.existsSync(c)) {
      ver = JSON.parse(fs.readFileSync(c, "utf8")).version;
      break;
    }
  }
  deps[name] = ver || String(names[name]).replace(/^[\^~]/, "");
}
const pkg = { name: "zephyr-app", private: true, type: "module", dependencies: deps };
fs.writeFileSync(path.join(ctx, "app/package.json"), JSON.stringify(pkg, null, 2) + "\n");
console.log("wrote app/package.json");
