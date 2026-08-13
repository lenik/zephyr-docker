#!/usr/bin/env node
/**
 * context.d/100e2e-pin.mjs — pin e2e package.json + rewrite playwright.config.ts
 * Env: REPO/CTX (or ZEPHYR_*)
 */
import fs from "node:fs";
import path from "node:path";

const repo = process.env.ZEPHYR_REPO || process.env.REPO;
const ctx = process.env.ZEPHYR_CTX || process.env.CTX;
if (!repo || !ctx) {
  console.error("REPO/CTX required");
  process.exit(1);
}

const e2ePkg = JSON.parse(
  fs.readFileSync(path.join(repo, "web-e2e/package.json"), "utf8"),
);
const names = { ...e2ePkg.devDependencies };
const deps = {};
for (const name of Object.keys(names)) {
  const candidates = [
    path.join(repo, "web-e2e/node_modules", name, "package.json"),
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
const pkg = {
  name: "zephyr-e2e",
  private: true,
  type: "module",
  scripts: {
    ...e2ePkg.scripts,
    "auth:setup": "playwright test --project=setup",
    "test:smoke": "playwright test --project=chromium --grep @smoke",
    "test:p0": "playwright test --project=chromium --grep @p0",
    test: "playwright test --project=chromium",
  },
  dependencies: deps,
};
fs.writeFileSync(path.join(ctx, "e2e/package.json"), JSON.stringify(pkg, null, 2) + "\n");

const cfgPath = path.join(ctx, "e2e/playwright.config.ts");
let cfg = fs.readFileSync(cfgPath, "utf8");
if (!cfg.includes("disable-dev-shm-usage")) {
  cfg = cfg.replace(
    /use: \{\n(\s+)baseURL,/,
    `use: {\n$1baseURL,\n$1launchOptions: {\n$1  args: ["--disable-dev-shm-usage", "--no-sandbox"],\n$1},`,
  );
}
cfg = cfg.replace(
  /projects: \[[\s\S]*?\n  \],\n\}\);/,
  `projects: [
    {
      name: "setup",
      testMatch: /auth\\.setup\\.ts/,
    },
    {
      name: "chromium",
      dependencies: ["setup"],
      testIgnore: /auth\\.setup\\.ts/,
      use: {
        ...devices["Desktop Chrome"],
        viewport: { width: 1440, height: 900 },
        storageState: path.join(__dirname, ".auth/admin.json"),
      },
    },
    {
      name: "mobile-chromium",
      dependencies: ["setup"],
      testIgnore: /auth\\.setup\\.ts/,
      grep: /@mobile/,
      use: {
        ...devices["Pixel 7"],
        viewport: { width: 390, height: 844 },
        storageState: path.join(__dirname, ".auth/collector.json"),
      },
    },
  ],
});`,
);
fs.writeFileSync(cfgPath, cfg);
console.log("pinned e2e package.json + playwright.config.ts");
