# Arena Shooter

2D top-down экшен-прототип на Godot 4 с тактическим AI-слоем.

Текущий вектор: гибрид быстрого боевого темпа (в духе Hotline Miami) и комнатного напряжения/охоты (в духе Manhunt), с переходом к уровням существенно большего масштаба.

## Статус Проекта

Проект уже играбелен и покрыт автотестами. В рабочем контуре есть:

- движение игрока, прицеливание, стрельба, переключение оружия;
- процедурная генерация комнат и цикл миссий в одной сцене уровня;
- room-based спавн врагов и тактическое поведение AI;
- runtime budget scheduler для AI/pathing (bounded work per frame);
- взаимодействие с дверями и выбивание дверей;
- боевой пайплайн, VFX/SFX, музыкальные контексты;
- headless тестовые suite.

Кодовая база находится в активной миграции:

- legacy-контуры ближнего боя удалены из рабочего runtime/UI и актуальной документации;
- текущий фокус миграции: data-driven баланс и унификация AI-сигналов.

## Технологии

- Engine: Godot 4.x (фичи проекта ориентированы на 4.6)
- Язык: GDScript
- Подход: autoload-синглтоны + системная оркестрация сцены
- Тесты: headless scene-based suites

## Быстрый Старт

### Запуск из редактора

1. Открыть папку проекта в Godot.
2. Главная сцена: `res://scenes/app_root.tscn`.
3. Нажать `F5`.

### Запуск из CLI

```bash
godot --path . --scene res://scenes/app_root.tscn
```

Если Godot установлен через snap, команда может выглядеть так:

```bash
/snap/godot-4/current/godot-4 --path . --scene res://scenes/app_root.tscn
```

## Управление

### Базовое

- `W A S D`: движение
- `Mouse`: прицеливание
- `LMB`: выстрел
- `Mouse Wheel`: переключение оружия
- `1..6`: прямой выбор слота оружия
- `Esc`: пауза

### Двери

- `E`: interact (открыть/закрыть)
- `Q`: kick

### Debug / Runtime

- `F1`: принудительный `GAME_OVER`
- `F2`: принудительный `LEVEL_COMPLETE`
- `F3`: debug overlay
- `F4`: регенерация процедурного layout
- `F7`: включение/выключение огнестрела у врагов
- `F8`: загрузка `res://src/levels/stealth_test_room.tscn` (если `F8` не занят в `InputMap`)

## Что Уже Есть В Геймплее

- Свободное top-down перемещение с accel/decel.
- Система оружия на 6 слотов:
  - `pistol`
  - `auto`
  - `shotgun`
  - `plasma`
  - `rocket`
  - `chain_lightning`
- Боевой пайплайн и урон:
  - TTL и жизненный цикл снарядов;
  - агрегация дроби для shotgun;
  - глобальные contact i-frames.
- Процедурная генерация комнатного уровня (`ProceduralLayoutV2`).
- Статический room-based спавн врагов (`RoomEnemySpawner`).
- Граф комнат и room-aware навигация (`RoomNavSystem`).
- Тактический AI-слой:
  - room alert propagation/decay;
  - роли отряда (pressure/hold/flank);
  - utility intents + pursuit execution;
  - визуальные alert-маркеры.
- Runtime budgeting для больших карт:
  - budget `ms/frame` для AI/pathing;
  - квоты `enemy_ai`, `squad_rebuild`, `nav_tasks`;
  - round-robin tick по врагам.
- Переход по миссиям через северный триггер после зачистки.
- Физические двери с anti-pinch поведением.
- Визуально-аудио стек: combat feedback, atmosphere, shadows, music contexts, SFX routing.

## Поток Состояний

Состояния игры управляются через `StateManager` и `EventBus`:

- `MAIN_MENU`
- `SETTINGS`
- `LEVEL_SETUP`
- `PLAYING`
- `PAUSED`
- `GAME_OVER`
- `LEVEL_COMPLETE`

`app_root.gd` выступает composition root для UI и lifecycle уровня.

## Структура Репозитория

```text
arena-shooter/
|- assets/                  # спрайты, текстуры, аудио
|- scenes/
|  |- app_root.tscn
|  |- entities/
|  |- levels/level_mvp.tscn
|  |- ui/
|- src/
|  |- core/                 # GameConfig, RuntimeState, StateManager, validators
|  |- entities/             # player, enemy, projectile
|  |- levels/               # оркестрация уровня
|  |- systems/              # combat, AI, audio, VFX, doors, layout, nav
|  |- ui/                   # скрипты меню и экранов
|- tests/                   # headless suites и smoke тесты
|- project.godot
```

## Конфигурация И Баланс

Сейчас основной источник конфигурации - `GameConfig` (autoload) + системные дефолты в коде.

План миграции: вынести combat/AI tuning в единый data-driven слой, чтобы убрать дубли и упростить баланс для больших уровней.

Для runtime budgeting используется секция `GameConfig.ai_balance.runtime_budget`:

- `frame_budget_ms`
- `enemy_ai_quota`
- `squad_rebuild_quota`
- `nav_tasks_quota`

## Тестирование

Полный headless прогон:

```bash
godot --headless --path . --scene res://tests/test_runner.tscn
```

Smoke-тест:

```bash
godot --headless --path . --scene res://tests/test_level_smoke.tscn
```

Ключевые suite по AI/runtime budgeting:

```bash
godot --headless --path . --scene res://tests/test_enemy_runtime_budget_scheduler.tscn
godot --headless --path . --scene res://tests/test_enemy_behavior_integration.tscn
```

Для snap-установки:

```bash
/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_runner.tscn
/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_level_smoke.tscn
```

## Известный Техдолг

- Часть баланса AI/combat все еще зашита в константах разных систем.
- Alert/suspicion логика приводится к единому источнику истины.
- Квота `nav_tasks` заведена в runtime scheduler, но очередь фоновых nav-задач в `RoomNavSystem` пока минимальная.

## Ближайшее Направление

1. Ввести единый data-driven баланс-конфиг.
2. Финализировать single-source модель alert/suspicion.
3. Подготовить AI/pathing/runtime budgeting к картам сильно большего размера.
