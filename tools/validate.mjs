#!/usr/bin/env node
/**
 * Static release validation.
 *
 * This is not a substitute for an in-game load test. It catches packaging
 * mistakes that would otherwise cost a game launch to discover.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const releaseRoot = path.join(root, "releases", "BeautifulHumansCore");
const problems = [];

function fail(message) {
  problems.push(message);
}

function read(relative) {
  return fs.readFileSync(path.join(releaseRoot, relative), "utf8");
}

function walk(directory, files = []) {
  if (!fs.existsSync(directory)) return files;
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) walk(absolute, files);
    else if (entry.isFile()) files.push(absolute);
  }
  return files;
}

if (!fs.existsSync(releaseRoot)) {
  fail("releases/BeautifulHumansCore is missing; run `node tools/build.mjs` first");
} else {
  const modInfoPath = path.join(releaseRoot, "mod.info");
  if (!fs.existsSync(modInfoPath)) {
    fail("mod.info is missing");
  } else {
    const modInfo = fs.readFileSync(modInfoPath, "utf8");
    for (const key of ["name", "id", "description", "modversion", "versionMin", "author"]) {
      if (!new RegExp(`^${key}=.+$`, "m").test(modInfo)) fail(`mod.info is missing ${key}`);
    }
    if (!/^id=BeautifulHumansCore$/m.test(modInfo)) fail("mod.info id must be BeautifulHumansCore");
  }

  for (const requiredInfo of ["42/mod.info", "common/mod.info"]) {
    if (!fs.existsSync(path.join(releaseRoot, requiredInfo))) {
      fail(`${requiredInfo} is missing (Build 42 scans version/common roots)`);
    }
  }

  const core = read("42/media/lua/shared/BH/Core.lua");
  const version = core.match(/BH\.VERSION\s*=\s*"([^"]+)"/);
  if (!version) fail("BH.VERSION is missing from Core.lua");
  const modInfo = fs.readFileSync(path.join(releaseRoot, "mod.info"), "utf8");
  if (version && !modInfo.includes(`modversion=${version[1]}`)) {
    fail(`mod.info modversion does not match BH.VERSION ${version[1]}`);
  }

  const files = walk(path.join(releaseRoot, "42"));
  if (files.length === 0) fail("release contains no Lua files");
  const luaFiles = files.filter((file) => file.endsWith(".lua"));
  if (luaFiles.length < 10) fail(`unexpectedly few Lua files: ${luaFiles.length}`);

  const known = new Set();
  for (const file of luaFiles) {
    const relative = path
      .relative(path.join(releaseRoot, "42", "media", "lua"), file)
      .replace(/\\/g, "/")
      .replace(/\.lua$/, "");
    known.add(relative);
    // PZ's require paths omit the shared/client/server root.
    const stripped = relative.replace(/^(shared|client|server)\//, "");
    known.add(stripped);
  }

  for (const file of luaFiles) {
    const source = fs.readFileSync(file, "utf8");
    const relative = path.relative(releaseRoot, file).replace(/\\/g, "/");
    if (/\bos\.execute\b/.test(source)) fail(`${relative}: os.execute is forbidden`);
    if (/\bio\.open\b/.test(source)) fail(`${relative}: direct file IO is forbidden`);

    for (const match of source.matchAll(/require\s+"([^"]+)"/g)) {
      const dependency = match[1];
      if (dependency.startsWith("BH/") && !known.has(dependency)) {
        fail(`${relative}: unresolved require "${dependency}"`);
      }
    }
  }

  const coreModules = [...core.matchAll(/id\s*=\s*"(bh\.[a-z0-9_.-]+)"/g)].map((match) => match[1]);
  if (coreModules.length === 0) fail("no BH module registrations found in Core.lua");
}

if (problems.length > 0) {
  console.error("VALIDATION FAILED");
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

console.log("VALIDATION OK");
console.log(`  release: ${releaseRoot}`);
