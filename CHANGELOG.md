# Changelog

Все заметные изменения Beautiful Humans.

## [0.1.0] — 2026-10-25

Первый фундамент платформы. Это **не** релиз 1.0.0.

### Added

- BH Core: пространство имён, конфигурация, журнал, шина событий, реестр
  модулей, разрешение зависимостей, диагностика.
- BH Persistence: character extension в `player:getModData()`, схема v1,
  миграция v0, ремонт, карантин, лимиты.
- BH Anatomy: 17 зон `BodyPartType`, модель травм, функциональные штрафы,
  тик кровотечения/заживления.
- BH Physiology: боль, кровопотеря, mobility/manipulation/consciousness/
  respiration, capacity.
- BH Medical: каталог действий, проверки, эффекты, идемпотентность,
  диагностика.
- BH Integration: `OnGameStart`, `OnServerStarted`, `OnCreatePlayer`,
  `OnPlayerUpdate`, `OnPlayerGetDamage`, `OnPlayerDeath`, `OnHitZombie`,
  `OnPostSave`.
- Отладочные команды `BH.Commands.*`.
- Тестовый мод `BHTestMod`.
- 39 unit-тестов, 128 assertions.
- Runtime self-test на выделенном сервере 42.21.0.
- Документация Stage 0/1.
- `.gitattributes` для Lua/JSON/бинарных файлов.
- GitHub Actions workflow `.github/workflows/validate.yml`.
- Инструкция по публикации `docs/PUBLISHING.md`.

### Verified

- Игра: Project Zomboid 42.21.0, revision `4a0e9546ec`, buildid `25485521`.
- Загрузка `BeautifulHumansCore` и `BHTestMod`.
- 7 модулей `ready`, 0 failed, 0 skipped.
- `BH_TEST_RESULT PASS total=11 failures=0`.

### Known limitations

- нет UI и timed actions;
- нет серверной авторизации лечения;
- нет NPC, экономики, транспорта;
- нет зомби-анатомии;
- нет профилирования FPS;
- реальное сохранение/загрузка персонажа ещё не проверены.

### Fixed during development

- `next()` отсутствует/недоступен в Kahlua: заменён на `BH.Util.TableCount`.
- Build 42 требует `mod.info` в `common/` или `<version>/`, а не только в
  корне мода.
- `OnServerStarted` добавлен для запуска модулей на выделенном сервере.
