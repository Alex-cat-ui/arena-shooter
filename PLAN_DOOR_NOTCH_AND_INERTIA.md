# План: двери (hinge notch + реалистичная инерция + anti-pinch)

## 1. Цель
1. Убрать неестественное толкание игрока/монстров дверью при закрытии и при быстром открытии.
2. Сделать удар о лимит открытия мягким и инерционным, без резкого отскока.
3. Обеспечить открытие двери шире 90° там, где это физически возможно, через выемку `notch` у петли.
4. Внести изменения без регрессий по генерации, walkability и визуальным тестам.

## 2. Актуальная архитектура (куда именно вносить правки)
1. Оркестратор layout: `src/systems/procedural_layout_v2.gd`.
2. Геометрия стен и вырезы дверей: `src/systems/layout_wall_builder.gd`.
3. Постановка дверных проёмов (Rect2): `src/systems/layout_door_carver.gd`.
4. Физика створки: `src/systems/door_physics_v3.gd`.
5. Спавн физических дверей в уровне: `src/systems/layout_door_system.gd`.

Ключевое уточнение:
`notch` добавляем в `LayoutWallBuilder`, а не в `ProceduralLayoutV2`, так как вырезание проёмов и sealing живут в модуле стен.

## 3. Ограничения и критерии качества
1. Не ломать контракты модулей (`LayoutWallBuilder` остаётся pure-utility для сегментов/стен).
2. Не повышать `pseudo_gap_count_stat` на валидных сидов.
3. Не вызывать заметного jitter или “дребезга” двери.
4. Не менять поведение legacy-генератора (`src/legacy/*`).

## 4. Реализация notch (широкое открытие > 90°)
### 4.1 Изменения в API/конфиге
1. Добавить в `GameConfig` параметры:
`door_hinge_notch_enabled: bool`,
`door_hinge_notch_depth_px: float`,
`door_hinge_notch_span_ratio: float`.
2. В `ProceduralLayoutV2` пробросить параметры в `LayoutWallBuilder.finalize_wall_segments(...)`.

### 4.2 Изменения в `LayoutWallBuilder`
1. Расширить `finalize_wall_segments(...)` и `cut_doors_from_segments(...)` доп. аргументом `notch_config`.
2. В `cut_doors_from_segments(...)` для каждого `door Rect2` формировать дополнительные интервалы выреза у стороны петли.
3. Вырез делать по оси стены у петли, и при необходимости по примыкающим сегментам, чтобы убрать геометрический клин у hinge.
4. Для сплитов использовать ту же стратегию интервального вычитания, чтобы не плодить дубли логики.
5. Добавить учёт notch-gap в `_is_intentional_gap(...)`, чтобы `seal_non_door_gaps(...)` не “залечивал” notch.

### 4.3 Геометрические правила notch
1. Сторона петли берётся из текущего `DoorPhysicsV3.configure_from_opening(...)` (hinge у начала проёма с `HINGE_INSET_PX`).
2. `notch_depth_px` ограничить сверху `wall_t`, снизу безопасным минимумом.
3. `notch_span = door_length * door_hinge_notch_span_ratio`.
4. Вырез не должен ломать perimeter-контур и не должен делать микро-сегменты `< 2 px`.

## 5. Реалистичная инерция и anti-pinch (без заморозки)
### 5.1 Изменения в `DoorPhysicsV3`
1. Сохранить принцип: дверь не толкает тела активным импульсом (reverse impulse остаётся отключённым).
2. Переделать anti-pinch в направленный:
anti-pinch активируется, когда есть тело в sweep-path и текущий знак угловой скорости ведёт створку в сторону тела.
3. Вместо freeze:
уменьшать closing/opening компонент скорости множителем затухания за кадр.
4. На anti-pinch:
снижать `stiffness` и добавлять небольшой reopen torque, но без реверса “в лоб”.
5. Добавить near-closed damping boost для натурального дотягивания без удара.

### 5.2 Мягкий bounce о лимит
1. Понизить `door_limit_bounce` в `GameConfig` (например 0.35 -> 0.15, финально по тестам).
2. В `_enforce_open_limits()` смягчить минимальный rebound-порог (`0.18`) до адаптивного малого значения, чтобы не было резкого “пинка” при низкой скорости.
3. Проверить, что дверь после удара слегка отъезжает по инерции и возвращается плавно.

## 6. Тесты
### 6.1 Unit: `tests/test_layout_wall_builder.gd`
1. Новый тест: `cut_doors + hinge notch` действительно вырезает дополнительный интервал.
2. Новый тест: `seal_non_door_gaps` не восстанавливает intentional notch-gap.
3. Новый тест: при выключенном notch поведение полностью как раньше.

### 6.2 Интеграция двери: `tests/test_door_physics_full.gd`
1. Обновить `wall_bounce` критерий для более мягкого отскока.
2. Добавить сценарий anti-pinch при быстром открытии рядом с телом.
3. Добавить проверку “нет резкого реверса” (скорость затухает, а не мгновенно меняет знак).

### 6.3 Регресс layout
1. `tests/test_layout_wall_builder.tscn`
2. `tests/test_layout_walkability.tscn`
3. `tests/test_layout_visual_regression.tscn`
4. `tests/test_runner.tscn` (финальная smoke-проверка)

## 7. Порядок выполнения
1. Ввести конфиг-поля notch/bounce в `GameConfig`.
2. Расширить `LayoutWallBuilder` (cut + intentional gap для notch).
3. Пробросить notch config из `ProceduralLayoutV2`.
4. Обновить `DoorPhysicsV3` (направленный anti-pinch + мягкий bounce).
5. Обновить и добавить тесты.
6. Прогнать тестовый набор и оттюнить константы.

## 8. Риски и контрмеры
1. Риск: рост `pseudo_gap_count_stat`.
Контрмера: корректный intentional-gap матчинг для notch и unit-тесты.
2. Риск: переослабление bounce (дверь “липнет” к лимиту).
Контрмера: минимальный адаптивный rebound + тест `wall_bounce`.
3. Риск: anti-pinch начнёт мешать нормальному открытию.
Контрмера: направленная активация по знаку движения и положению тела.
4. Риск: несовпадение hinge-стороны между layout и runtime door.
Контрмера: единое правило hinge-side из `configure_from_opening` и тест на обе ориентации.

## 9. Критерии приёмки
1. На картах со стеной у петли дверь открывается заметно шире 90° при включённом notch.
2. При контакте с телом дверь не выталкивает объект резким depenetration-эффектом.
3. Удар об лимит выглядит мягко и инерционно, без жёсткого мгновенного отскока.
4. `test_layout_visual_regression`, `test_layout_walkability`, `test_door_physics_full` проходят.
