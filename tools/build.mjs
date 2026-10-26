#!/usr/bin/env node
/**
 * Reproducible release builder.
 *
 * Output:
 *   releases/BeautifulHumansCore/42/media/lua/{shared,client,server}/...
 *   releases/BHTestMod/42/media/lua/shared/...
 *
 * The build deliberately copies only Lua sources and generated metadata. Game
 * assets will be added by their owning modules once they exist.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const coreSource = path.join(root, "src", "shared", "BH", "Core.lua");
const versionMatch = fs.readFileSync(coreSource, "utf8").match(/BH\.VERSION\s*=\s*"([^"]+)"/);
if (!versionMatch) {
  throw new Error("Could not read BH.VERSION from src/shared/BH/Core.lua");
}
const version = versionMatch[1];

function ensureDir(directory) {
  fs.mkdirSync(directory, { recursive: true });
}

function clean(directory) {
  if (fs.existsSync(directory)) {
    fs.rmSync(directory, { recursive: true, force: true });
  }
}

function copyLuaTree(source, destination) {
  if (!fs.existsSync(source)) return 0;
  ensureDir(destination);
  let copied = 0;
  for (const entry of fs.readdirSync(source, { withFileTypes: true })) {
    const sourcePath = path.join(source, entry.name);
    const destinationPath = path.join(destination, entry.name);
    if (entry.isDirectory()) {
      copied += copyLuaTree(sourcePath, destinationPath);
    } else if (entry.isFile() && entry.name.endsWith(".lua")) {
      fs.copyFileSync(sourcePath, destinationPath);
      copied += 1;
    }
  }
  return copied;
}

function writeModInfo(directory, fields) {
  const lines = Object.entries(fields).map(([key, value]) => `${key}=${value}`);
  fs.writeFileSync(path.join(directory, "mod.info"), lines.join("\n") + "\n", "utf8");
}

function buildCore() {
  const release = path.join(root, "releases", "BeautifulHumansCore");
  clean(release);
  ensureDir(release);

  // Build 42 resolves both a shared "common" root and a versioned root. Keep an
  // explicit (possibly empty) common directory so loaders that probe it first
  // do not reject the mod as malformed.
  ensureDir(path.join(release, "common"));
  for (const rootName of ["common", "42"]) {
    for (const assetDir of ["AnimSets", "actiongroups"]) {
      ensureDir(path.join(release, rootName, "media", assetDir));
    }
  }

  const mediaRoot = path.join(release, "42", "media", "lua");
  const copied =
    copyLuaTree(path.join(root, "src", "shared"), path.join(mediaRoot, "shared")) +
    copyLuaTree(path.join(root, "src", "client"), path.join(mediaRoot, "client")) +
    copyLuaTree(path.join(root, "src", "server"), path.join(mediaRoot, "server"));

  const coreInfo = {
    name: "Beautiful Humans Core",
    id: "BeautifulHumansCore",
    description: "Core framework for the Beautiful Humans survival simulation platform.",
    modversion: version,
    version: "42",
    versionMin: "42.0",
    pzversion: "42",
    author: "Beautiful Humans Team",
    tags: "Core,Framework",
  };
  writeModInfo(release, coreInfo);
  writeModInfo(path.join(release, "42"), coreInfo);
  writeModInfo(path.join(release, "common"), coreInfo);

  fs.writeFileSync(
    path.join(release, "BUILD.json"),
    JSON.stringify(
      {
        id: "BeautifulHumansCore",
        version,
        targetBuild: "42.21.0",
        builtAt: new Date().toISOString(),
        luaFiles: copied,
      },
      null,
      2
    ) + "\n",
    "utf8"
  );

  return { release, copied };
}

function buildTestMod() {
  const release = path.join(root, "releases", "BHTestMod");
  clean(release);
  ensureDir(release);

  ensureDir(path.join(release, "common"));
  for (const rootName of ["common", "42"]) {
    for (const assetDir of ["AnimSets", "actiongroups"]) {
      ensureDir(path.join(release, rootName, "media", assetDir));
    }
  }
  const mediaRoot = path.join(release, "42", "media", "lua");
  const copied = copyLuaTree(
    path.join(root, "tests", "integration", "BHTestMod"),
    path.join(mediaRoot, "shared")
  );

  const testInfo = {
    name: "Beautiful Humans Core Test Mod",
    id: "BHTestMod",
    description: "Runtime self-test for Beautiful Humans Core. Requires BeautifulHumansCore.",
    modversion: version,
    version: "42",
    versionMin: "42.0",
    pzversion: "42",
    author: "Beautiful Humans Team",
    require: "BeautifulHumansCore",
  };
  writeModInfo(release, testInfo);
  writeModInfo(path.join(release, "42"), testInfo);
  writeModInfo(path.join(release, "common"), testInfo);

  fs.writeFileSync(
    path.join(release, "BUILD.json"),
    JSON.stringify(
      {
        id: "BHTestMod",
        version,
        targetBuild: "42.21.0",
        builtAt: new Date().toISOString(),
        luaFiles: copied,
      },
      null,
      2
    ) + "\n",
    "utf8"
  );

  return { release, copied };
}

const core = buildCore();
const testMod = buildTestMod();

console.log(`Built BeautifulHumansCore ${version} (${core.copied} Lua files)`);
console.log(`Built BHTestMod ${version} (${testMod.copied} Lua files)`);
console.log("Releases:");
console.log(`  ${core.release}`);
console.log(`  ${testMod.release}`);
