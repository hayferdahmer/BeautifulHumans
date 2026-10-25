# Beautiful Humans

<p align="center">
  <b>Единая симуляционная платформа выживания для Project Zomboid Build 42</b><br/>
  <sub>анатомия · физиология · травмы · лечение · модульное ядро</sub>
</p>

> **Текущий статус:** `0.1.0` — фундамент платформы, а не релиз 1.0.0.
> Реализованы Core, Persistence, Anatomy, Physiology, Medical и
> интеграционный слой. NPC, экономика, транспорт и массовая симуляция
> отложены.

---

## Что уже работает

- модульное ядро с направленными зависимостями и изоляцией ошибок;
- версионируемая схема character extension в `player:getModData()`;
- миграции, ремонт и карантин повреждённых записей;
- 17 анатомических зон, привязанных к `BodyPartType`;
- структурированные травмы (порез, укус, перелом, ожог и т.д.);
- несколько травм в одной зоне не перезаписывают друг друга;
- физиологические последствия: боль, кровопотеря, mobility/manipulation;
- диагностика и лечение: examine, clean, bandage, splint, stitch,
  remove bandage;
- идемпотентность лечения по `requestId`;
- внутренняя шина событий с приоритетами и защитой от re-entrancy;
- runtime self-test на выделенном сервере;
- 39 unit-тестов (128 assertions).

## Чего ещё нет

- полноценного игрового UI;
- timed actions и анимаций лечения;
- серверной авторизации лечения в мультиплеере;
- зомби-анатомии и поведения;
- NPC, экономики, жилья, транспорта;
- профилирования FPS;
- теста реального сохранения/загрузки персонажа.

Подробно: [TECHNICAL_AUDIT.md](docs/TECHNICAL_AUDIT.md),
[ROADMAP.md](docs/ROADMAP.md).

---

## Целевая среда

| Параметр | Значение |
|---|---|
| Игра | Project Zomboid |
| Сборка | **42.21.0** |
| Revision | `4a0e9546ec` |
| Steam buildid | `25485521` |
| Режимы | одиночная игра, выделенный сервер |
| Язык | Lua (Kahlua) |

Другая сборка требует повторного аудита.

---

## Установка

### Готовая сборка

Вариант 1 — распаковать `releases/BeautifulHumansCore-0.1.0.zip` в
`%USERPROFILE%\Zomboid\mods` (в архиве уже есть папка `BeautifulHumansCore`).

Вариант 2:

```powershell
Copy-Item -Recurse -Force releases\BeautifulHumansCore "$env:USERPROFILE\Zomboid\mods\BeautifulHumansCore"
```

Включить `Beautiful Humans Core` в списке модов.

### Тестовый мод

```powershell
Copy-Item -Recurse -Force releases\BHTestMod "$env:USERPROFILE\Zomboid\mods\BHTestMod"
```

`BHTestMod` требует `BeautifulHumansCore`. После запуска в `console.txt`
появится:

```text
BH_TEST_RESULT PASS total=11 failures=0 version=0.1.0
```

### Сборка из исходников

```powershell
node tools/build.mjs
node tools/validate.mjs
```

---

## Быстрый старт в игре

1. Запустить debug-режим.
2. Открыть Lua-консоль.
3. Выполнить:

```lua
BH.Commands.Help()
BH.Commands.Injury("left_thigh", "cut", 60)
BH.Commands.Self()
BH.Commands.Treat(nil, "bandage")
BH.Commands.Self()
```

4. Сохранить, выйти, загрузить, снова выполнить `BH.Commands.Self()`.

Ожидаемо: одна травма, кровотечение остановлено, состояние сохранилось.

---

## Тесты

```powershell
pnpm --dir tools install
node tools/run_tests.mjs
```

Ожидаемо:

```text
TEST_SUMMARY total=39 passed=39 failed=0 assertions=128
```

Runtime-тест:

```powershell
node tools/build.mjs
# скопировать releases/BeautifulHumansCore и releases/BHTestMod в Zomboid/mods
# включить оба мода, запустить игру/сервер
```

Подробности: [TESTING.md](docs/TESTING.md).

---

## Структура

```text
BeautifulHumans/
├── docs/                     документация
├── src/
│   ├── shared/BH/            Core, Persistence, Anatomy, Physiology, Medical
│   │   ├── Core.lua
│   │   ├── Persistence/
│   │   ├── Anatomy/
│   │   ├── Physiology/
│   │   ├── Medical/
│   │   └── Integration/
│   ├── shared/BH_Bootstrap.lua
│   ├── client/
│   └── server/
├── tests/
│   ├── unit/                 headless Lua-тесты
│   └── integration/          BHTestMod
├── tools/                    build, validate, test
└── releases/
    ├── BeautifulHumansCore/  готовый мод
    └── BHTestMod/            тестовый мод
```

---

## Документация

| Документ | Содержание |
|---|---|
| [TECHNICAL_AUDIT.md](docs/TECHNICAL_AUDIT.md) | аудит Build 42, матрица реализуемости |
| [AUDIT_EVIDENCE.md](docs/AUDIT_EVIDENCE.md) | краткие логи и результаты проверок |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | слои, зависимости, загрузка, события |
| [DATA_MODEL.md](docs/DATA_MODEL.md) | схема character extension и травм |
| [MODULES.md](docs/MODULES.md) | модули, границы, статусы |
| [NETWORKING.md](docs/NETWORKING.md) | server-authoritative модель |
| [PERFORMANCE.md](docs/PERFORMANCE.md) | бюджеты и план профилирования |
| [TESTING.md](docs/TESTING.md) | тесты и ручные сценарии |
| [PUBLISHING.md](docs/PUBLISHING.md) | создание репозитория GitHub, первый push, релизы |
| [ROADMAP.md](docs/ROADMAP.md) | этапы 0–10 |

---

## Команды разработчика

```lua
BH.Commands.Help()
BH.Commands.Self()
BH.Commands.Injury(zone, kind, severity)
BH.Commands.List()
BH.Commands.Treat(injuryId, action)
BH.Commands.Tick(minutes)
BH.Commands.Heal(injuryId)
BH.Commands.Reset()
BH.Commands.Snapshot()
```

Это **отладочные** команды. Они обходят проверку предметов и не являются
сетевым API.

---

## Известные ограничения

1. Спина не является отдельной зоной `BodyPartType`.
2. `OnPlayerGetDamage` не передаёт body part; зона выводится из состояния.
3. `OnPlayerGetDamage` для кровотечения может срабатывать каждый кадр;
   BH использует throttle и baseline.
4. Лечение в мультиплеере пока не авторизуется сервером.
5. Нет UI и анимаций лечения.
6. Нет NPC и экономики.
7. Нет профилирования FPS.

---

## Совместимость

- Build 42.21.0 — подтверждена.
- Build 41 — не поддерживается.
- Другие моды — не тестировались.
- Прямой перехват стандартных функций не используется.

---

## Лицензия

Лицензия ещё не выбрана. До публичного релиза файл `LICENSE` должен быть
заменён выбранным текстом. Сейчас код является внутренним проектом.
