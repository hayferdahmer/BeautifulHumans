# Модель данных Beautiful Humans

**Версия схемы:** 1  
**Хранение:** `player:getModData().BH`  
**Версионирование:** `schemaVersion`

---

## 1. CharacterExtension

```lua
{
    schemaVersion = 1,

    anatomy = {
        zones = {
            left_thigh = {
                injuries = { ... },
                updatedAt = 123.5,
            },
        },
        nextInjurySeq = 2,
        healedCount = 0,
        lastTick = 120.0,
    },

    physiology = {
        pain = 18.5,
        bloodLoss = 4.0,
        fatigue = 0.0,
        lastUpdate = 121.0,
    },

    medical = {
        processedRequests = {},
        processedSeq = 0,
        lastActionAt = 0,
    },

    mind = {
        stress = 0,
        fear = 0,
    },

    exposure = {},

    metadata = {
        createdAt = 100.0,
        updatedAt = 121.0,
        createdVersion = "0.1.0",
        updatedVersion = "0.1.0",
        ownerKey = "player:1",
    },
}
```

### 1.1. Инварианты

- `schemaVersion` — целое, не больше поддерживаемого.
- `anatomy.zones` — таблица по стабильным id зон.
- `nextInjurySeq` — целое ≥ 1, больше любого числового суффикса id.
- `physiology.pain`, `bloodLoss`, `fatigue` — 0..100.
- `medical.processedRequests` — не более 32 записей.
- Общее число травм — не более 64.
- Травм на зону — не более 8.
- Все числовые поля конечны; `NaN`/`inf` запрещены.

---

## 2. AnatomyZone

```lua
left_thigh = {
    injuries = {
        ["left_thigh-000001"] = { ... },
    },
    updatedAt = 123.5,
}
```

### 2.1. Стабильные зоны

| id | `BodyPartType` | fallback index | группа |
|---|---|---:|---|
| `left_hand` | `Left_Hand` | 0 | left_arm |
| `right_hand` | `Right_Hand` | 1 | right_arm |
| `left_forearm` | `Left_Forearm` | 2 | left_arm |
| `right_forearm` | `Right_Forearm` | 3 | right_arm |
| `left_upper_arm` | `Left_UpperArm` | 4 | left_arm |
| `right_upper_arm` | `Right_UpperArm` | 5 | right_arm |
| `chest` | `Torso_Upper` | 6 | torso |
| `abdomen` | `Torso_Lower` | 7 | torso |
| `head` | `Head` | 8 | head |
| `neck` | `Neck` | 9 | head |
| `groin` | `Groin` | 10 | torso |
| `left_thigh` | `Left_Thigh` | 11 | left_leg |
| `right_thigh` | `Right_Thigh` | 12 | right_leg |
| `left_shin` | `Left_Shin` | 13 | left_leg |
| `right_shin` | `Right_Shin` | 14 | right_leg |
| `left_foot` | `Left_Foot` | 15 | left_leg |
| `right_foot` | `Right_Foot` | 16 | right_leg |

Индексы разрешаются через `BodyPartType.ToIndex(...)` при загрузке. Fallback
используется только в тестах и при отсутствии enum.

---

## 3. Injury

```lua
{
    id = "left_thigh-000001",
    zone = "left_thigh",
    kind = "cut",
    severity = 42.5,
    bleeding = 12.0,
    contamination = 6.0,
    infection = 0.0,
    pain = 23.4,
    healing = 18.0,
    status = "healing",
    source = "zombie",

    createdAt = 120.0,
    updatedAt = 132.0,
    treatmentCount = 1,

    bandaged = true,
    bandageDirty = false,
    splinted = false,
    stitched = false,
    cleaned = true,
    examined = true,

    meta = {
        initialSeverity = 60,
        observedFromBase = true,
        externalBandage = false,
        mergedCount = 0,
    },
}
```

### 3.1. Допустимые `kind`

```text
abrasion
bruise
burn
cut
deep_wound
fracture
puncture
sprain
bite
```

### 3.2. Допустимые `status`

```text
active
healing
infected
healed
```

`healed` обычно удаляется из таблицы, но допускается в старых данных.

### 3.3. Допустимые `source`

```text
debug
environment
fall
medical
unknown
vehicle
weapon
zombie
```

### 3.4. Смысл полей

| Поле | Смысл |
|---|---|
| `severity` | тяжесть 0..100, не здоровье |
| `bleeding` | интенсивность кровотечения 0..100 |
| `contamination` | загрязнение раны 0..100 |
| `infection` | прогресс инфекции 0..100 |
| `pain` | вклад в боль |
| `healing` | прогресс заживления 0..100 |
| `bandaged` | повязка активна |
| `splinted` | фиксация активна |
| `stitched` | шов наложен |
| `cleaned` | рана очищена |
| `examined` | игрок знает точную тяжесть |

---

## 4. Состояния лечения

```text
Чистая рана ──clean──> cleaned=true
Рана ──bandage──> bandaged=true, bleeding ↓
bandaged ──remove_bandage──> bandaged=false, возможен возврат крови
fracture/sprain ──splint──> splinted=true
deep_wound/cut ──stitch──> stitched=true
```

Каждое действие:

1. проверяет тип травмы;
2. проверяет предметы;
3. проверяет текущее состояние;
4. проверяет `requestId` на повтор;
5. меняет только свою часть данных;
6. эмитит событие;
7. возвращает `consume`-список для интеграции.

---

## 5. Миграции

### 5.1. Версия 0 → 1

Старый формат:

```lua
{
    schemaVersion = 0,
    injuries = {
        { id = "old-1", zone = "left_thigh", kind = "cut", severity = 30 },
    },
}
```

Преобразуется в:

```lua
{
    schemaVersion = 1,
    anatomy = {
        zones = {
            left_thigh = {
                injuries = {
                    ["old-1"] = { id = "old-1", zone = "left_thigh", kind = "cut", severity = 30 },
                },
            },
        },
    },
}
```

### 5.2. Правила миграции

1. Миграция идемпотентна.
2. Повторная загрузка не должна повторно мигрировать.
3. Неизвестные поля сохраняются, если не конфликтуют.
4. Некорректные поля ремонтируются или удаляются с записью в журнал.
5. Будущая версия схемы не уничтожается: запись карантинируется.
6. Миграция не должна требовать игрового мира.

### 5.3. Карантин

При повреждении:

```lua
player:getModData().BH_QUARANTINE = {
    at = 123.0,
    reason = "character data is not a table",
    version = "0.1.0",
}
```

Исходная запись не копируется в карантин (чтобы не раздувать сохранение).
Диагностическая запись содержит только причину и время.

---

## 6. Лимиты и размер

| Лимит | Значение | Причина |
|---|---:|---|
| Травм на персонажа | 64 | размер сохранения |
| Травм на зону | 8 | читаемость и UI |
| Обработанных запросов | 32 | идемпотентность без роста |
| История травмы | 0 | история не хранится в v0.1 |
| События в журнале | 250 | диагностика в памяти |

При превышении лимита зоны:

- сначала ищется активная травма того же типа;
- если есть — тяжесть/кровотечение объединяются, `meta.mergedCount++`;
- иначе объединяется наименее тяжёлая травма;
- молчаливая потеря данных запрещена: пишется предупреждение.

---

## 7. Пример полного сценария

```lua
local data = BH.Persistence.GetCharacterData(player)
local injury = BH.Anatomy.Model.AddInjury(data, "left_thigh", "cut", 55, "zombie")

local diagnosis = BH.Medical.GetDiagnosis(data, injury.id)
-- severityExact = false, severityBand = "unknown"

BH.Medical.Apply(data, injury.id, "examine", { requestId = "ex-1" })
BH.Medical.Apply(data, injury.id, "clean", {
    hasItem = function(tag) return tag == "Water" end,
    requestId = "clean-1",
})
BH.Medical.Apply(data, injury.id, "bandage", {
    hasItem = function(tag) return tag == "Bandage" end,
    requestId = "band-1",
})

BH.Anatomy.Model.Tick(data, 30)
```

После перезагрузки:

```lua
local reloaded = BH.Persistence.GetCharacterData(player)
local same = BH.Anatomy.Model.FindInjury(reloaded, injury.id)
```

---

## 8. Что не хранится

- ссылки на игровые объекты;
- `IsoPlayer`, `IsoZombie`, `InventoryItem`;
- мировые координаты;
- полные истории действий;
- производные кэши, которые можно пересчитать;
- тексты исключений.

Это предотвращает утечки, циклические ссылки и раздувание сохранений.
