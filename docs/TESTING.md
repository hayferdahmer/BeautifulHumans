# Тестирование Beautiful Humans

**Версия:** 0.1.0  
**Целевая сборка:** 42.21.0

---

## 1. Уровни тестов

| Уровень | Где | Что проверяет |
|---|---|---|
| Unit | `tests/unit` | чистые правила, схема, события, модель |
| Integration | `tests/integration` | загрузка мода, модули, character extension, лечение |
| Save/load | ручной сценарий | реальное сохранение персонажа |
| Multiplayer | будущее | серверная авторизация и синхронизация |
| Performance | будущее | сцены S1–S6 |

---

## 2. Unit-тесты

### 2.1. Запуск

```powershell
node tools/run_tests.mjs
```

Требуется `fengari`. Установка:

```powershell
pnpm --dir tools install
```

### 2.2. Результат v0.1

```text
TEST_SUMMARY total=39 passed=39 failed=0 assertions=128
```

### 2.3. Покрытие

| Блок | Тесты |
|---|---|
| Core/Modules | порядок зависимостей, дубликаты, missing, циклы, изоляция ошибок |
| Events | приоритет, ошибка подписчика, re-entrancy, удаление |
| Config | валидация значений |
| Persistence | создание, reload, отсутствие дубликатов, карантин, future schema, v0→v1, ремонт |
| Anatomy | 17 зон, несколько травм, cap, mobility, manipulation, tick, heal |
| Medical | предметы, bandage, duplicate request, remove, splint, clean, diagnose, actions |
| Physiology | pain, bloodLoss, capacity, smoothing |

### 2.4. Ограничение harness

`fengari` — Lua 5.3, а игра использует Kahlua (Lua 5.1 subset). Unit-тесты
ловят синтаксис и логику, но **не заменяют** загрузку в игре. Runtime-тест
обязателен.

---

## 3. Runtime self-test

### 3.1. Состав

`BHTestMod` — независимый мод с `require=BeautifulHumansCore`.

Проверяет:

1. Core version.
2. `bh.core` ready.
3. `bh.anatomy` ready.
4. `bh.medical` ready.
5. 17 зон.
6. Создание character extension.
7. Создание травмы.
8. Применение bandage.
9. Остановку кровотечения.
10. Reload без дубликата.
11. Внутреннюю шину событий.

### 3.2. Запуск

```powershell
node tools/build.mjs
```

Скопировать `releases/BeautifulHumansCore` и `releases/BHTestMod` в
`%USERPROFILE%\Zomboid\mods`, включить оба мода, запустить игру или сервер.

Для выделенного сервера:

```text
cachedir/
├── mods/
│   ├── BeautifulHumansCore/
│   └── BHTestMod/
└── Server/
    └── BHTest.ini
```

`BHTest.ini` должен содержать:

```ini
Mods=BeautifulHumansCore;BHTestMod
WorkshopItems=
Public=false
MaxPlayers=1
```

### 3.3. Ожидаемый результат

В `console.txt` / логе сервера:

```text
[BH][INFO][core] Booting Beautiful Humans
[BH][INFO][integration] Start event received | OnServerStarted
[BH][INFO][core] Resolving modules
[BH][INFO][core] Modules initialised | ready=7, failed=0, skipped=0
[BH][INFO][testmod] Test module initialised
BH_TEST_RESULT PASS total=11 failures=0 version=0.1.0
```

### 3.4. Фактический результат

На целевой сборке 42.21.0 получено именно это. Ошибок `Beautiful Humans`
в логе нет. Ошибки `AdvancedAnimator` о missing `AnimSets`/`actiongroups`
относятся к пустым каталогам ассетов и не являются ошибками Lua.

---

## 4. Обязательный ручной сценарий Stage 2

### Сценарий A — травма

1. Создать нового персонажа в debug-режиме.
2. Открыть Lua-консоль.
3. `BH.Commands.Self()` — убедиться, что расширение создано.
4. `BH.Commands.Injury("left_thigh", "cut", 60)`.
5. `BH.Commands.Self()` — травма есть, кровотечение > 0.
6. `BH.Commands.Treat(nil, "bandage")`.
7. `BH.Commands.Self()` — кровотечение 0, повязка активна.
8. Сохранить, выйти, загрузить.
9. `BH.Commands.Self()` — травма ровно одна, повязка сохранилась.
10. `BH.Commands.Tick(1000)` — травма заживает и исчезает.

### Сценарий B — зомби

Пока не реализован. Требуется Stage 2:
обнаружение → преследование → повреждение → потеря цели → поиск.

### Сценарий C — предмет

Пока не реализован. Требуется Stage 2/4.

---

## 5. Проверки сохранений

Для каждой сохраняемой системы:

- [x] данные в `modData`;
- [x] версия схемы;
- [x] миграция v0→v1;
- [x] ремонт повреждённых полей;
- [x] карантин;
- [x] отсутствие дубликатов при reload (unit);
- [ ] реальное сохранение/загрузка персонажа (ручной тест);
- [ ] размер `modData` после длинной игры.

---

## 6. Сетевые тесты (не реализованы)

- [ ] клиент не может прислать severity;
- [ ] повторный requestId не дублирует эффект;
- [ ] лечение чужой травмы отклоняется;
- [ ] лечение без предмета отклоняется;
- [ ] лечение на расстоянии отклоняется;
- [ ] переподключение не дублирует;
- [ ] перезапуск сервера сохраняет состояние;
- [ ] устаревший ответ не откатывает новое состояние.

---

## 7. Производительность (не реализована)

См. `docs/PERFORMANCE.md`, сцены S1–S6.

---

## 8. Определение готовности задачи

Задача не принимается без:

1. реализации;
2. unit-теста;
3. обработки ошибок;
4. проверки сохранения (если есть состояние);
5. проверки сети (если доступно в MP);
6. документации;
7. подтверждения в целевой сборке.

Загрузка файла без игрового сценария не считается завершённой функцией.

---

## 9. Известные пробелы v0.1

- нет теста с живым игроком;
- нет теста реального save/load;
- нет MP;
- нет UI;
- нет профилирования FPS;
- нет совместимости с другими модами;
- `AdvancedAnimator` шумит из-за пустых каталогов ассетов.

Эти пробелы перечислены в `docs/TECHNICAL_AUDIT.md` и должны быть закрыты до
1.0.0.
