#!/usr/bin/env node
/**
 * Copy runtime vendor packages from an existing install (fully offline).
 * Roots: argon2, @prisma/client, exceljs, pdfkit (+ dependency trees).
 * Resolves each dependency from its parent package dir (pnpm-compatible).
 * Handles packages that omit "./package.json" from "exports" (e.g. fontkit).
 */
import { createRequire } from "node:module";
import fs from "node:fs";
import path from "node:path";

const backendRoot = process.argv[2];
const destRoot = process.argv[3];
if (!backendRoot || !destRoot) {
  console.error("usage: copy-runtime-vendor.mjs <backendDir> <destNodeModules>");
  process.exit(1);
}

const roots = ["argon2", "@prisma/client", "exceljs", "pdfkit"];
const copied = new Set(); // real package dirs copied

function copyDir(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.cpSync(src, dest, { recursive: true, dereference: true });
}

function destFor(name) {
  return path.join(destRoot, ...name.split("/"));
}

function readPkg(dir) {
  return JSON.parse(fs.readFileSync(path.join(dir, "package.json"), "utf8"));
}

/** Resolve package root even when exports block require('name/package.json'). */
function resolvePkgDir(name, parentDir) {
  const req = createRequire(path.join(parentDir, "package.json"));
  try {
    return path.dirname(req.resolve(`${name}/package.json`));
  } catch {
    // Walk up from a resolvable entry (main/exports ".") to the package root.
    let entry;
    try {
      entry = req.resolve(name);
    } catch (err) {
      const err2 = new Error(`cannot resolve ${name} from ${parentDir}: ${err.message}`);
      err2.code = err.code;
      throw err2;
    }
    let dir = path.dirname(entry);
    while (true) {
      const pj = path.join(dir, "package.json");
      if (fs.existsSync(pj)) {
        try {
          if (readPkg(dir).name === name) return dir;
        } catch {
          /* continue */
        }
      }
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
    throw new Error(`cannot find package root for ${name} (from ${entry})`);
  }
}

function copyPackage(name, parentDir) {
  let srcDir;
  try {
    srcDir = resolvePkgDir(name, parentDir);
  } catch (err) {
    // Optional native build deps may be absent at runtime (prebuilds used).
    console.warn(`skip ${name} (from ${parentDir}): ${err.code || err.message}`);
    return;
  }
  const real = fs.realpathSync(srcDir);
  if (copied.has(real)) return;
  copied.add(real);

  const meta = readPkg(srcDir);
  const dest = destFor(meta.name);
  if (!fs.existsSync(dest)) {
    console.log(`copy ${meta.name}@${meta.version}`);
    copyDir(srcDir, dest);
  }

  const deps = { ...meta.dependencies, ...meta.optionalDependencies };
  for (const dep of Object.keys(deps || {})) {
    copyPackage(dep, srcDir);
  }
}

fs.mkdirSync(destRoot, { recursive: true });
for (const root of roots) copyPackage(root, backendRoot);
console.log(`copied ${copied.size} packages → ${destRoot}`);
