# Integration tests

## Runtime self-test mod

`BHTestMod` is an independent mod that depends on `BeautifulHumansCore`. It
validates that:

- Core, Persistence, Anatomy, Physiology and Medical modules reach `ready`;
- a character extension is created and survives a simulated reload;
- an injury can be created and bandaged through the public API;
- duplicate request protection works;
- the internal event bus delivers events.

The test is intentionally independent of the main mod's load order.

### Install

```powershell
node tools/build.mjs
Copy-Item -Recurse -Force releases\BeautifulHumansCore "$env:USERPROFILE\Zomboid\mods\BeautifulHumansCore"
Copy-Item -Recurse -Force releases\BHTestMod "$env:USERPROFILE\Zomboid\mods\BHTestMod"
```

Enable both mods in the in-game mod list. `BHTestMod` declares
`require=BeautifulHumansCore`, so the game should enforce the dependency.

### Expected output

In `%USERPROFILE%\Zomboid\console.txt`:

```text
BH_TEST_RESULT PASS total=11 failures=0 version=0.1.0
```

A failing check prints `[BHTest] FAIL ...` immediately before the summary.

### Manual scenario

1. Start a debug single-player game.
2. Open the Lua console and run `BH.Commands.Self()`.
3. Run `BH.Commands.Injury("left_thigh", "cut", 60)`.
4. Run `BH.Commands.Treat(nil, "bandage")`.
5. Run `BH.Commands.Self()` again and confirm bleeding is zero.
6. Save, quit and reload; run `BH.Commands.Self()` and confirm the injury is
   still present exactly once.

This scenario is the minimum evidence for the first vertical slice. It is not a
substitute for a full multiplayer authority test.
