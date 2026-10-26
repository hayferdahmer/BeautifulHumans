#!/usr/bin/env node
/**
 * Headless test runner for the pure-Lua BH modules.
 *
 * The production runtime is Project Zomboid's Kahlua VM. This harness uses
 * fengari (Lua 5.3) to catch syntax errors and exercise pure rules without
 * launching the game. In-game integration tests live in tests/integration.
 */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");

function loadFengari() {
  const candidates = [
    path.join(here, ".deps", "node_modules", "fengari"),
    path.join(here, "node_modules", "fengari"),
  ];
  for (const candidate of candidates) {
    if (!fs.existsSync(candidate)) continue;
    const localRequire = createRequire(path.join(candidate, "package.json"));
    return localRequire("fengari");
  }
  return createRequire(import.meta.url)("fengari");
}

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = loadFengari();
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

function fail(message) {
  console.error(message);
  lua.lua_close(L);
  process.exit(1);
}

function setGlobalFunction(name, callback) {
  lua.lua_pushcfunction(L, callback);
  lua.lua_setglobal(L, to_luastring(name));
}

// Source files are loaded in dependency order. `require` is a no-op because
// each file is already present in the VM; this mirrors Kahlua's shared Lua
// environment closely enough for pure rules.
setGlobalFunction("require", () => {
  lua.lua_pushboolean(L, 1);
  return 1;
});

const sources = [
  "src/shared/BH/Util.lua",
  "src/shared/BH/Log.lua",
  "src/shared/BH/Config.lua",
  "src/shared/BH/EventBus.lua",
  "src/shared/BH/ModuleRegistry.lua",
  "src/shared/BH/Core.lua",
  "src/shared/BH/Persistence/Schema.lua",
  "src/shared/BH/Persistence/Persistence.lua",
  "src/shared/BH/Anatomy/Zones.lua",
  "src/shared/BH/Anatomy/Rules.lua",
  "src/shared/BH/Anatomy/Model.lua",
  "src/shared/BH/Physiology/Physiology.lua",
  "src/shared/BH/Medical/Treatments.lua",
  "src/shared/BH/Medical/Medical.lua",
  // Integration files are loaded for syntax/registration checks. Their game
  // event callbacks are not invoked without a running game.
  "src/shared/BH/Integration/PlayerObserver.lua",
  "src/shared/BH/Integration/Commands.lua",
  "src/shared/BH/Integration/GameEvents.lua",
  "tests/unit/runner.lua",
  "tests/unit/spec_core.lua",
  "tests/unit/spec_persistence.lua",
  "tests/unit/spec_anatomy.lua",
  "tests/unit/spec_medical.lua",
  "tests/unit/spec_physiology.lua",
];

for (const relative of sources) {
  const absolute = path.join(root, relative);
  if (!fs.existsSync(absolute)) {
    fail(`Missing source: ${relative}`);
  }
  const code = fs.readFileSync(absolute, "utf8");
  const status = lauxlib.luaL_loadstring(L, to_luastring(code));
  if (status !== lua.LUA_OK) {
    fail(`Lua parse error in ${relative}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
  }
  const callStatus = lua.lua_pcall(L, 0, 0, 0);
  if (callStatus !== lua.LUA_OK) {
    fail(`Lua runtime error in ${relative}: ${to_jsstring(lua.lua_tostring(L, -1))}`);
  }
}

lua.lua_getglobal(L, to_luastring("BH_TEST_RUN"));
if (!lua.lua_isfunction(L, -1)) {
  fail("BH_TEST_RUN is not defined");
}
const runStatus = lua.lua_pcall(L, 0, 1, 0);
if (runStatus !== lua.LUA_OK) {
  fail(`Test runner crashed: ${to_jsstring(lua.lua_tostring(L, -1))}`);
}
const success = lua.lua_toboolean(L, -1) === true;
lua.lua_pop(L, 1);
lua.lua_close(L);
process.exit(success ? 0 : 1);
