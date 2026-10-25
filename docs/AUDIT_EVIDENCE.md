# Audit evidence

Краткие воспроизводимые доказательства Stage 0. Полные логи не коммитятся,
потому что содержат пути и состояние тестового мира.

---

## 1. Версия игры

Из лога запуска выделенного сервера:

```text
LOG : General ...> version=42.21.0 4a0e9546ec demo=false
LOG : General ...> revision=4a0e9546ec
```

Steam:

```text
appid=108600
buildid=25485521
depot 108604 manifest=7544133343391543313
```

---

## 2. Загрузка мода

```text
LOG : Mod ...> loading BeautifulHumansCore
LOG : Mod ...> loading BHTestMod
[BH][INFO][core] Booting Beautiful Humans | version=0.1.0
[BH][INFO][integration] Registering game events
```

---

## 3. Запуск модулей

```text
[BH][INFO][integration] Start event received | OnServerStarted
[BH][INFO][core] Resolving modules
[BH][INFO][core] Core module ready
[BH][INFO][persistence] Persistence ready
[BH][INFO][anatomy] Anatomy ready | zones=17, engineResolved=true
[BH][INFO][physiology] Physiology ready
[BH][INFO][medical] Medical ready | treatments=6
[BH][INFO][integration] Integration module ready | engineZones=17
[BH][INFO][testmod] Test module initialised
[BH][INFO][core] Modules initialised | ready=7, failed=0, skipped=0
```

---

## 4. Runtime self-test

```text
BH_TEST_RESULT PASS total=11 failures=0 version=0.1.0
```

Проверки:

1. core version;
2. `bh.core` ready;
3. `bh.anatomy` ready;
4. `bh.medical` ready;
5. 17 zones;
6. character extension;
7. injury creation;
8. treatment;
9. bleeding stopped;
10. reload without duplicate;
11. event bus.

---

## 5. Unit-тесты

```text
TEST_SUMMARY total=39 passed=39 failed=0 assertions=128
```

---

## 6. Что это доказывает

- мод загружается в 42.21.0;
- структура `42/mod.info` + `42/media/lua` корректна;
- события `OnServerStarted` и `OnGameStart` регистрируются;
- модули разрешаются и инициализируются;
- `ModData`/character extension работает;
- доменный цикл травмы и лечения работает;
- тестовый мод может зависеть от Core.

## 7. Что это не доказывает

- сохранение и загрузку реального персонажа;
- повреждение от зомби в игровом сценарии;
- мультиплеерную синхронизацию;
- производительность при массовых сценах;
- совместимость с другими модами.
