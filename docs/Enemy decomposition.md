**Жесткий план декомпозиции enemy.gd (без двусмысленности)**

Ниже план как техпроект с фиксированным порядком фаз. Он рассчитан на реальный безопасный рефакторинг enemy.gd (сейчас 3412 строк, core-узкое место runtime\_budget\_tick() в enemy.gd (line 510)), с учетом соседних модулей и тестового контура.

**Что фиксируем сразу (обязательные инварианты на весь рефактор)**

- Поведение AI не меняется.

- Схема GameConfig.ai\_balance не меняется (ключи остаются там же), значит config\_validator.gd (line 166) не меняется по смыслу.

- Публичный API Enemy сохраняется (методы из enemy.gd (line 332), 491, 499, 510, 835, 845, 859, 863, 886, 891, 921, 934, 1284, 1288, 1294, 1319, 1329, 1333, 1337, 1341, 1381, 1388, 1395, 3340, 3345, 3350, 3355).

- Ключи get\_debug\_detection\_snapshot() сохраняются без переименований.

- Контракт EnemyPursuitSystem.execute\_intent() сохраняется (ключи результата из enemy\_pursuit\_system.gd (line 443)).

- Контракт EnemyUtilityBrain.update(ctx) сохраняется (контекстные ключи из enemy\_utility\_brain.gd (line 70) и \_choose\_intent в enemy\_utility\_brain.gd (line 97)).

- Контракт EnemySquadSystem.get\_assignment() сохраняется (поля assignment из enemy\_squad\_system.gd (line 78)).

**Целевая архитектура после завершения**

- Enemy остается оркестратором CharacterBody2D.

- Выносятся runtime-блоки в отдельные RefCounted helper-скрипты:

- enemy\_combat\_search\_runtime.gd

- enemy\_fire\_control\_runtime.gd

- enemy\_combat\_role\_runtime.gd

- enemy\_alert\_latch\_runtime.gd

- enemy\_detection\_runtime.gd

- enemy\_debug\_snapshot\_runtime.gd

- EnemyDamageRuntime (enemy\_damage\_runtime.gd) остается как есть и служит шаблоном стиля.

**Критичные повторы / задвоения логики, которые нужно убрать (и где именно)**

- Дублирование обработки “источника шума/вызова” (investigate anchor + dynamic hold + flashlight delay) между on\_heard\_shot() (enemy.gd (line 863)) и apply\_teammate\_call() (enemy.gd (line 891)).

- Дублирование очистки/заполнения текущего search-node в combat search (повторяется в enemy.gd (line 2514), 2635, 2721).

- Дублирование zone lookup в \_get\_zone\_state() (enemy.gd (line 1309)) и \_is\_zone\_lockdown() (enemy.gd (line 1653)).

- Дублирование nav\_system.is\_point\_in\_shadow(...) проверок по всему файлу.

- Дублирование групповых reset-комбинаций (\_reset\_first\_shot\_delay\_state, \_reset\_combat\_role\_runtime, \_reset\_combat\_search\_state) в нескольких местах (enemy.gd (line 2096), 2136, initialize()).

- Дублирование белых-box тестов через приватные поля Enemy в отдельных тестах и внутри test\_runner\_node.gd (line 1012).

- Важное: двойной вызов room-alert snapshot в runtime\_budget\_tick() (enemy.gd (line 653) и 755) не удаляется как “дубликат поведения”, он остается как две разные фазы, но оборачивается в один helper.

## **Фаза 0. Заморозка контрактов и границ рефактора**

- Цель: зафиксировать, что именно нельзя сломать при переносе кода.

- Изменения: добавить рефакторный контракт в docs/ (один файл) с перечислением неизменяемых публичных API, debug snapshot keys, pursue-result keys, utility-context keys.

- Переносится: ничего.

- Удаляется: ничего.

- Новые тесты (обязательные):

- test\_enemy\_debug\_detection\_snapshot\_contract.gd (проверка набора ключей snapshot, только shape/keys)

- test\_enemy\_runtime\_public\_api\_contract.gd (наличие публичных методов Enemy)

- test\_enemy\_pursuit\_execute\_result\_contract.gd (shape результата execute\_intent, если такого отдельного нет)

- Влияние на соседние модули: только фиксация контрактов Enemy, EnemyPursuitSystem, EnemyUtilityBrain, EnemySquadSystem, ConfigValidator.

- Критерий завершения: все контрактные тесты зеленые до начала переноса логики.

## **Фаза 1. Механическая дедупликация внутри **enemy.gd** (без выноса по файлам)**

- Цель: сократить копипасту и подготовить безопасные точки выноса.

- Изменения: добавить приватные helper-методы внутри Enemy и заменить повторы на вызовы helper-ов.

- Переносится: логика остается в Enemy, только реорганизуется.

- Удаляется (копипаста):

- повторяющиеся блоки из on\_heard\_shot() и apply\_teammate\_call()

- повторяющиеся блоки очистки/установки \_combat\_search\_current\_node\_\*

- повторяющийся zone lookup код из \_get\_zone\_state() и \_is\_zone\_lockdown()

- повторяющиеся nav\_system.has\_method("is\_point\_in\_shadow") куски через один helper

- Обязательные новые helper-методы (в этом же файле):

- \_apply\_investigate\_anchor\_from\_signal\_pos(...)

- \_roll\_flashlight\_delay\_for\_signal\_distance(...)

- \_point\_in\_shadow(pos: Vector2) -\> bool

- \_clear\_combat\_search\_current\_node\_selection()

- \_apply\_combat\_search\_pick\_result(pick: Dictionary)

- \_resolve\_zone\_state\_for\_room(room\_id: int) -\> int

- \_capture\_room\_alert\_snapshot() (один helper, вызывается дважды в разных фазах tick)

- Новые тесты:

- не добавлять новых behavior-тестов, достаточно существующих regression + контрактов из Фазы 0

- Влияние на соседние модули: отсутствует.

- Критерий завершения: поведение не меняется, только сокращена копипаста.

## **Фаза 2. Каркас рантайм-модулей (скелеты + wiring, без переноса логики)**

- Цель: подготовить инфраструктуру для поэтапного выноса без больших diff-ов.

- Изменения в enemy.gd:

- добавить preload-константы новых runtime helper-скриптов

- добавить поля объектов runtime (\_combat\_search\_runtime, \_fire\_control\_runtime, \_combat\_role\_runtime, \_alert\_latch\_runtime, \_detection\_runtime, \_debug\_snapshot\_runtime)

- создать и инициализировать их в \_ready() / initialize()

- Переносится: ничего (кроме wiring).

- Удаляется: ничего.

- Новые файлы (создаются пустые рабочие каркасы):

- enemy\_combat\_search\_runtime.gd

- enemy\_fire\_control\_runtime.gd

- enemy\_combat\_role\_runtime.gd

- enemy\_alert\_latch\_runtime.gd

- enemy\_detection\_runtime.gd

- enemy\_debug\_snapshot\_runtime.gd

- Новые тесты:

- test\_enemy\_runtime\_helpers\_exist\_and\_wired.gd (или добавить в test\_refactor\_kpi\_contract.gd)

- Влияние на соседние модули:

- test\_refactor\_kpi\_contract.gd (line 121) позже будет расширен на новые helper scripts

- test\_extended\_stealth\_release\_gate.gd (line 11) dependency grep пока не трогаем

- Критерий завершения: проект запускается, тесты проходят, behavior не изменен.

- Нормативный контракт этой фазы (обязательный, дальше не дрейфует по shape):

- `enemy_combat_search_runtime.gd` обязан экспортировать confirm/debug фрагменты и иметь API: `reset_state`, `record_execution_feedback`, `apply_repath_recovery_feedback`, `tick_runtime`.

- `enemy_fire_control_runtime.gd` обязан иметь API: `evaluate_fire_contact`, `can_fire_contact_allows_shot`, `resolve_shotgun_fire_block_reason`, `resolve_shotgun_fire_schedule_block_reason`, `should_fire_now`, `update_first_shot_delay_runtime`, `try_fire_at_player`, static debug alias methods.

- `enemy_combat_role_runtime.gd` обязан иметь API: `reset_state`, `resolve_runtime_role`, `update_runtime`, `assignment_supports_flank_role`, `resolve_contextual_combat_role`.

- `enemy_alert_latch_runtime.gd` обязан иметь API: `resolve_room_alert_snapshot`, `sync_combat_latch_with_awareness_state`, `update_combat_latch_migration`, `get_zone_state`, `is_zone_lockdown`.

- `enemy_detection_runtime.gd` обязан иметь API: `tick_reaction_warmup`, `on_heard_shot`, `apply_teammate_call`, `apply_blood_evidence`, `resolve_known_target_context`, `build_utility_context`, `apply_runtime_intent_stability_policy`, `compute_flashlight_active`.

- `enemy_debug_snapshot_runtime.gd` обязан иметь API: `refresh_transition_guard_tick`, `emit_stealth_debug_trace_if_needed`, `export_snapshot`.

- Контракт shape-словарей фиксируется на этой фазе и затем не переименовывается:

- `EnemyPursuitSystem.execute_intent()` result keys: `request_fire`, `path_failed`, `path_failed_reason`, `policy_blocked_segment`, `movement_intent`, `shadow_scan_status`, `shadow_scan_complete_reason`, `shadow_scan_target`, `plan_id`, `intent_target`, `plan_target`, `shadow_unreachable_fsm_state`, `repath_recovery_request_next_search_node`, `repath_recovery_reason`, `repath_recovery_blocked_point`, `repath_recovery_blocked_point_valid`, `repath_recovery_repeat_count`, `repath_recovery_preserve_intent`, `repath_recovery_intent_target`.

- Utility context keys из `Enemy._build_utility_context`: `dist`, `los`, `alert_level`, `combat_lock`, `last_seen_age`, `last_seen_pos`, `has_last_seen`, `dist_to_last_seen`, `investigate_anchor`, `has_investigate_anchor`, `dist_to_investigate_anchor`, `role`, `slot_role`, `slot_position`, `dist_to_slot`, `hp_ratio`, `path_ok`, `slot_path_status`, `slot_path_eta_sec`, `flank_slot_contract_ok`, `has_slot`, `player_pos`, `known_target_pos`, `target_is_last_seen`, `has_known_target`, `target_context_exists`, `home_position`, `shadow_scan_target`, `has_shadow_scan_target`, `shadow_scan_target_in_shadow`, `shadow_scan_source`, `shadow_scan_completed`, `shadow_scan_completed_reason`.

- Fire contact keys из `_evaluate_fire_contact`: `los`, `inside_fov`, `in_fire_range`, `not_occluded_by_world`, `shadow_rule_passed`, `weapon_ready`, `friendly_block`, `valid_contact_for_fire`, `occlusion_kind`.

- Room alert snapshot keys: `effective`, `transient`, `latch_count`.

- `get_debug_detection_snapshot()` keyset считается frozen contract (без rename/remove).

## **Фаза 3. Вынос CombatSearchRuntime (первый большой блок, наибольший ROI)**

- Цель: вынести самый самостоятельный доменный блок (combat search) из Enemy.

- Источник в Enemy: кластер combat\_search\_\* state и методы в районе enemy.gd (lines 2508-3076), плюс вызовы в runtime\_budget\_tick() (enemy.gd (line 581), 691, 692).

- Переносится в enemy\_combat\_search\_runtime.gd:

- все поля \_combat\_search\_\*

- \_record\_combat\_search\_execution\_feedback

- \_apply\_combat\_search\_repath\_recovery\_feedback

- \_current\_pursuit\_shadow\_search\_stage

- \_reset\_combat\_search\_state

- \_update\_combat\_search\_runtime

- \_ensure\_combat\_search\_room

- \_build\_combat\_dark\_search\_nodes

- \_select\_next\_combat\_dark\_search\_node

- \_compute\_combat\_search\_room\_coverage

- \_mark\_combat\_search\_current\_node\_covered

- \_update\_combat\_search\_progress

- \_select\_next\_combat\_search\_room

- \_door\_hops\_between

- search-specific constants (COMBAT\_SEARCH\_\*, COMBAT\_DARK\_SEARCH\_\*)

- Остается в Enemy:

- orchestration вызовы из runtime\_budget\_tick()

- построение confirm-config, но данные (search\_progress, total\_cap\_hit, timers) читаются из runtime

- \_resolve\_target\_room\_id (используется не только search)

- Временная совместимость (обязательно на 1 фазу):

- оставить delegating wrappers в Enemy для приватных методов combat search, чтобы не ломать все тесты сразу

- Удаляется (после миграции тестов этой фазы):

- прямые \_combat\_search\_\* поля из Enemy

- дублирующие helper-ы clear/apply pick, если они полностью ушли в runtime

- Новые тесты (обязательные):

- test\_enemy\_combat\_search\_runtime\_unit.gd (node selection, dedup, coverage)

- test\_enemy\_combat\_search\_runtime\_room\_rotation.gd (per-room budget, next room scoring)

- test\_enemy\_combat\_search\_runtime\_repath\_recovery\_contract.gd (repath feedback -\> skip node / rotate)

- test\_enemy\_combat\_search\_runtime\_snapshot\_export.gd (export для debug snapshot)

- Мигрируются существующие тесты:

- test\_combat\_next\_room\_scoring\_no\_loops.gd

- test\_dark\_search\_graph\_progressive\_coverage.gd

- test\_combat\_search\_per\_room\_budget\_and\_total\_cap.gd

- test\_alert\_combat\_search\_session\_completion\_contract.gd

- test\_repeated\_blocked\_point\_triggers\_scan\_then\_search.gd

- test\_unreachable\_shadow\_node\_forces\_scan\_then\_search.gd

- Влияние на соседние модули:

- enemy\_pursuit\_system.gd (line 286) контракт repath\_recovery\_\* ключей не меняется

- test\_extended\_stealth\_release\_gate.gd (line 18) (PHASE-16 grep) нужно обновить, чтобы искать маркеры в новом runtime-файле, а не только в enemy.gd

- Критерий завершения:

- все search-related behavior tests зеленые

- Enemy больше не владеет \_combat\_search\_\* состоянием

- Легаси-правило закрытия фазы:

- для migrated search-тестов запрещены прямые `enemy.set("_combat_search_*", ...)` и `enemy.call("_update_combat_search_runtime", ...)` как primary assertion path; они должны идти через runtime unit API или публичный black-box сценарий.

- wrappers search-кластера допустимы только как переходная совместимость до Фазы 10, затем удаляются в Фазе 11.

## **Фаза 4. Вынос FireControlRuntime (стрельба, gating, telegraph, trace cache)**

- Цель: вынести fire-state-machine и fire-contact evaluation.

- Источник в Enemy: блок enemy.gd (lines 1736-2355) + static debug/cache методы 1860-1876 и \_rebuild\_friendly\_fire\_excludes\_cache.

- Переносится в enemy\_fire\_control\_runtime.gd:

- поля \_shot\_cooldown, \_combat\_first\_\*, \_combat\_telegraph\_\*, \_combat\_fire\_phase, \_combat\_fire\_reposition\_left, \_friendly\_block\_\*

- fire debug state (те, что относятся только к fire decision) как internal runtime state

- \_try\_fire\_at\_player

- \_resolve\_shotgun\_fire\_block\_reason

- \_can\_fire\_contact\_allows\_shot

- \_resolve\_shotgun\_fire\_schedule\_block\_reason

- \_should\_fire\_now

- \_update\_combat\_fire\_cycle\_runtime

- \_begin\_combat\_reposition\_phase

- \_is\_combat\_reposition\_phase\_active

- \_inject\_combat\_cycle\_reposition\_intent

- \_reset\_combat\_fire\_cycle\_state

- \_combat\_fire\_phase\_name

- \_anti\_sync\_fire\_gate\_open

- \_record\_enemy\_shot\_tick

- static debug methods fire-sync/cache (debug\_reset\_fire\_sync\_gate, debug\_reset\_fire\_trace\_cache\_metrics, debug\_get\_fire\_trace\_cache\_metrics)

- \_evaluate\_fire\_contact

- \_trace\_fire\_line

- \_build\_fire\_line\_excludes

- \_is\_player\_collider\_for\_fire

- \_is\_friendly\_collider\_for\_fire

- \_register\_friendly\_block\_and\_reposition

- \_inject\_friendly\_block\_reposition\_intent

- \_intent\_supports\_fire

- \_arm\_first\_combat\_attack\_delay

- \_arm\_first\_shot\_telegraph

- \_cancel\_first\_shot\_telegraph

- \_resolve\_ai\_fire\_profile\_mode

- \_is\_test\_scene\_context

- \_roll\_telegraph\_duration\_sec

- \_is\_first\_shot\_gate\_ready

- \_mark\_enemy\_shot\_success

- \_reset\_first\_shot\_delay\_state

- \_update\_first\_shot\_delay\_runtime

- \_combat\_target\_context\_key

- \_shotgun\_cooldown\_sec

- \_rebuild\_friendly\_fire\_excludes\_cache (static helper)

- Остается в Enemy:

- \_fire\_enemy\_shotgun (фактический projectile/contact emission pipeline)

- \_shotgun\_stats

- WEAPON\_SHOTGUN, public fire constants и public static aliases на переходный период

- Временная совместимость (обязательно):

- Enemy.debug\_reset\_fire\_sync\_gate() и другие static debug методы остаются как aliases/proxy на runtime (tests уже используют Enemy.\*)

- Enemy.SHOTGUN\_FIRE\_BLOCK\_\*, Enemy.COMBAT\_FIRE\_PHASE\_\* остаются как публичные константы-алиасы (не удалять)

- Удаляется (после миграции):

- внутренний fire runtime state из Enemy

- прямой fire-logic код из Enemy

- Новые тесты (обязательные):

- test\_enemy\_fire\_control\_runtime\_unit.gd

- test\_enemy\_fire\_control\_first\_shot\_gate\_runtime.gd

- test\_enemy\_fire\_control\_schedule\_runtime.gd

- test\_enemy\_fire\_trace\_cache\_runtime\_alias\_contract.gd

- Мигрируются существующие тесты:

- test\_enemy\_fire\_decision\_contract.gd

- test\_enemy\_fire\_trace\_cache\_runtime.gd

- test\_first\_shot\_delay\_starts\_on\_first\_valid\_firing\_solution.gd

- test\_first\_shot\_timer\_starts\_on\_first\_valid\_firing\_solution.gd

- test\_first\_shot\_timer\_pause\_and\_reset\_after\_2\_5s.gd

- test\_friendly\_block\_prevents\_fire\_and\_triggers\_reposition.gd

- test\_shadow\_flashlight\_rule\_blocks\_or\_allows\_fire.gd

- test\_3zone\_smoke.gd (убрать прямые pokes \_combat\_first\_shot\_\*, заменить через публичный test hook/runtime debug hook)

- test\_telegraph\_profile\_production\_vs\_debug.gd

- test\_enemy\_fire\_cooldown\_min\_guard.gd

- test\_stealth\_weapon\_pipeline\_equivalence.gd

- Влияние на соседние модули:

- enemy\_pursuit\_system.gd не меняется по контракту request\_fire

- EventBus события emit\_enemy\_shot/emit\_enemy\_contact сохраняются

- Критерий завершения:

- fire-related tests зеленые

- Enemy больше не содержит fire state machine целиком

- Легаси-правило закрытия фазы:

- для fire-тестов запрещены прямые `enemy.set("_shot_cooldown", ...)`, `enemy.set("_combat_first_*", ...)`, `enemy.set("_combat_fire_*", ...)` как основной способ подготовки кейса; вместо этого runtime unit fixture.

- публичные `Enemy.debug_reset_fire_sync_gate()`, `Enemy.debug_reset_fire_trace_cache_metrics()`, `Enemy.debug_get_fire_trace_cache_metrics()` и константы `Enemy.SHOTGUN_FIRE_BLOCK_*`/`Enemy.COMBAT_FIRE_PHASE_*` фиксируются как permanent API.

## **Фаза 5. Вынос CombatRoleRuntime (динамическое переназначение ролей в COMBAT)**

- Цель: изолировать role lock/reassign механику от оркестратора.

- Источник в Enemy: enemy.gd (lines 2357-2506) (и \_combat\_role\_\* поля enemy.gd (lines 262-272)).

- Переносится в enemy\_combat\_role\_runtime.gd:

- все \_combat\_role\_\* поля

- \_resolve\_runtime\_combat\_role

- \_reset\_combat\_role\_runtime

- \_update\_combat\_role\_runtime

- \_reassign\_combat\_role

- \_assignment\_supports\_flank\_role

- \_resolve\_contextual\_combat\_role

- Остается в Enemy:

- SQUAD\_ROLE\_\* константы (публичный контракт для тестов)

- \_resolve\_squad\_assignment() как интеграция с EnemySquadSystem

- \_effective\_squad\_role\_for\_context() пока остается до фазы alert/zone (зависит от lockdown)

- Удаляется (после миграции):

- \_combat\_role\_\* поля и логика из Enemy

- Временная совместимость:

- приватные delegating wrappers \_update\_combat\_role\_runtime и \_resolve\_contextual\_combat\_role держим ровно до миграции тестов

- Новые тесты (обязательные):

- test\_enemy\_combat\_role\_runtime\_unit.gd

- test\_enemy\_combat\_role\_runtime\_assignment\_contract.gd

- Мигрируются существующие тесты:

- test\_combat\_role\_lock\_and\_reassign\_triggers.gd

- test\_tactic\_flank\_requires\_path\_and\_time\_budget.gd

- test\_combat\_flank\_requires\_eta\_and\_path\_ok.gd

- Влияние на соседние модули:

- enemy\_squad\_system.gd (line 78) contract assignment dict keys остается неизменным

- enemy\_utility\_brain.gd (line 103) использование role/slot\_role не меняется

- Критерий завершения:

- role tests зеленые

- Enemy не хранит \_combat\_role\_\*

- Легаси-правило закрытия фазы:

- `test_combat_role_lock_and_reassign_triggers.gd`, `test_tactic_flank_requires_path_and_time_budget.gd`, `test_combat_flank_requires_eta_and_path_ok.gd` перестают быть white-box на `Enemy.call("_update_combat_role_runtime"... )` и переходят на runtime unit harness.

## **Фаза 6. Вынос AlertLatchRuntime (room alert snapshot, combat latch, migration, zone state)**

- Цель: вынести логику room-alert/latch/zone из Enemy.

- Источник в Enemy: enemy.gd (line 1096), 1233, 1244, 1274, 1309, 1653, 2070-2187.

- Переносится в enemy\_alert\_latch\_runtime.gd:

- поля \_combat\_latched, \_combat\_latched\_room\_id, \_combat\_migration\_candidate\_room\_id, \_combat\_migration\_candidate\_elapsed

- \_resolve\_room\_alert\_snapshot

- \_resolve\_room\_alert\_level

- \_raise\_room\_alert\_for\_combat\_same\_tick

- \_sync\_combat\_latch\_with\_awareness\_state

- \_ensure\_combat\_latch\_registered

- \_unregister\_combat\_latch

- \_update\_combat\_latch\_migration

- \_reset\_combat\_migration\_candidate

- \_combat\_room\_migration\_hysteresis\_sec

- \_get\_zone\_state

- \_is\_zone\_lockdown

- общий helper zone lookup (убирает задвоение \_get\_zone\_state vs \_is\_zone\_lockdown)

- Остается в Enemy:

- get\_current\_alert\_level()

- get\_ui\_awareness\_snapshot() (но данные берет из runtime + awareness)

- \_resolve\_effective\_alert\_level\_for\_utility() может остаться в Enemy как orchestration helper

- Удаляется:

- дублирующий zone lookup и room snapshot код в Enemy

- Временная совместимость:

- приватные delegating wrappers на latch-методы держим до миграции тестов

- Новые тесты (обязательные):

- test\_enemy\_alert\_latch\_runtime\_unit.gd

- test\_enemy\_zone\_lockdown\_query\_runtime.gd

- Мигрируются/перепроверяются существующие тесты:

- test\_enemy\_latch\_register\_unregister.gd

- test\_enemy\_latch\_migration.gd

- test\_combat\_room\_alert\_sync.gd

- test\_no\_combat\_latch\_before\_confirm\_complete.gd

- test\_flashlight\_active\_in\_combat\_when\_latched.gd (через интеграцию)

- test\_zone\_enemy\_wiring.gd (убрать проверки `enemy._zone_director` и `enemy._get_zone_state()` через приватный доступ)

- Влияние на соседние модули:

- enemy\_alert\_system.gd API не меняется

- zone\_director.gd API не меняется

- test\_zone\_enemy\_wiring.gd должен остаться зеленым без изменения поведения

- Критерий завершения:

- Enemy больше не владеет latch/zone runtime state

- Легаси-правило закрытия фазы:

- тесты, проверяющие zone/latch, переходят на публичный snapshot/API; обращения к `enemy._zone_director` и приватным zone-методам считаются legacy и удаляются.

## **Фаза 7. Вынос DetectionRuntime (stealth/flashlight/detection/last\_seen/investigate/context builder)**

- Цель: убрать из Enemy самый плотный кластер detection-state и stealth policy.

- Источник в Enemy: блок state enemy.gd (lines 148-220) (частично), методы 810, 863, 891, 921, 1121, 1319-1705, 1527, 1570, 1598-1647, 3082-3138.

- Переносится в enemy\_detection\_runtime.gd:

- detection/visibility/last\_seen/investigate/flashlight state:

- \_player\_visible\_prev, \_confirmed\_visual\_prev

- \_perception\_rng, \_reaction\_warmup\_timer, \_had\_visual\_los\_last\_frame

- \_last\_seen\_pos, \_last\_seen\_age, \_last\_seen\_grace\_timer

- \_investigate\_anchor, \_investigate\_anchor\_valid, \_investigate\_target\_in\_shadow

- flashlight/shadow flags (\_flashlight\_hit\_override, \_flashlight\_activation\_delay\_timer, \_shadow\_check\_flashlight\_override, \_shadow\_linger\_flashlight, \_flashlight\_scanner\_allowed, \_shadow\_scan\_active, \_shadow\_scan\_completed, \_shadow\_scan\_completed\_reason)

- \_test\_last\_stable\_look\_dir, \_test\_los\_look\_grace\_timer

- \_intent\_stability\_lock\_timer, \_intent\_stability\_last\_type

- методы:

- \_tick\_reaction\_warmup

- on\_heard\_shot internal handling body (публичный Enemy.on\_heard\_shot() остается proxy + pursuit forward)

- apply\_teammate\_call internal handling body (публичный метод остается в Enemy)

- apply\_blood\_evidence internal handling body (публичный метод остается в Enemy)

- \_build\_utility\_context

- \_apply\_runtime\_intent\_stability\_policy

- \_is\_canon\_confirm\_mode, \_stealth\_canon\_config, \_confirm\_config\_with\_defaults

- \_flashlight\_policy\_\*

- \_suspicious\_shadow\_scan\_flashlight\_bucket

- \_suspicious\_shadow\_scan\_flashlight\_gate\_passes

- \_compute\_flashlight\_active

- configure\_stealth\_test\_flashlight

- set\_flashlight\_hit\_for\_detection

- set\_shadow\_check\_flashlight

- set\_shadow\_scan\_active

- set\_flashlight\_scanner\_allowed

- is\_flashlight\_active\_for\_navigation

- \_is\_current\_position\_in\_shadow (или использовать shared point-in-shadow helper)

- \_is\_last\_seen\_grace\_active

- \_resolve\_known\_target\_context

- \_seed\_last\_seen\_from\_player\_if\_missing

- \_emit\_stealth\_debug\_trace\_if\_needed переносится в debug runtime только после Фазы 8; на этой фазе можно оставить временно

- Остается в Enemy:

- orchestration в runtime\_budget\_tick() (но использует API detection runtime)

- \_apply\_awareness\_transitions и awareness orchestration

- \_build\_confirm\_runtime\_config может остаться временно до стыковки с search/latch runtime, затем переехать в detection runtime

- Удаляется:

- соответствующие поля и методы detection/flashlight из Enemy

- Новые тесты (обязательные):

- test\_enemy\_detection\_runtime\_flashlight\_policy.gd

- test\_enemy\_detection\_runtime\_last\_seen\_and\_anchor.gd

- test\_enemy\_detection\_runtime\_intent\_stability\_policy.gd

- test\_enemy\_detection\_runtime\_reaction\_warmup.gd

- test\_enemy\_detection\_runtime\_context\_contract.gd (ключи контекста для utility brain)

- Мигрируются существующие тесты:

- test\_reaction\_latency\_window\_respected.gd

- test\_alert\_flashlight\_detection.gd

- test\_flashlight\_active\_in\_combat\_when\_latched.gd

- test\_flashlight\_bonus\_applies\_in\_combat.gd

- test\_flashlight\_single\_source\_parity.gd

- test\_suspicious\_flashlight\_30\_percent\_seeded.gd

- test\_suspicious\_shadow\_scan.gd

- test\_last\_seen\_grace\_window.gd

- test\_last\_seen\_used\_only\_in\_suspicious\_alert.gd

- test\_combat\_uses\_last\_seen\_not\_live\_player\_pos\_without\_los.gd

- test\_alert\_combat\_context\_never\_patrol.gd

- test\_blood\_evidence\_no\_instant\_combat\_without\_confirm.gd

- test\_blood\_evidence\_sets\_investigate\_anchor.gd

- test\_team\_contain\_with\_flashlight\_pressure.gd

- test\_state\_doctrine\_matrix\_contract.gd (убрать прямой вызов `enemy.call("_build_utility_context", ...)`)

- test\_stealth\_room\_lkp\_search.gd (убрать `enemy.set("_last_seen_*")`/`enemy.set("_investigate_*")`)

- Влияние на соседние модули:

- enemy\_utility\_brain.gd зависим от shape контекста (enemy\_utility\_brain.gd (line 97)), shape нельзя менять

- enemy\_pursuit\_system.gd использует owner callbacks set\_shadow\_check\_flashlight, set\_shadow\_scan\_active, clear\_shadow\_scan\_state path остается рабочим

- Критерий завершения:

- detection/stealth tests зеленые

- Enemy больше не содержит основной stealth/detection state cluster

- Легаси-правило закрытия фазы:

- detection-тесты больше не используют `enemy._awareness`, `enemy._investigate_*`, `enemy._last_seen_*`, `enemy._flashlight_activation_delay_timer`, `enemy.call("_compute_flashlight_active", ...)`, `enemy.call("_tick_reaction_warmup", ...)` напрямую.

## **Фаза 8. Вынос DebugSnapshotRuntime (debug state, snapshot builder, trace logging)**

- Цель: убрать \_debug\_\* state-sprawl из Enemy и стабилизировать debug API.

- Источник в Enemy: \_debug\_\* поля (enemy.gd (lines 171-215), 254-261 и др.), get\_debug\_detection\_snapshot() (enemy.gd (line 1395)), \_refresh\_transition\_guard\_tick() (1081), \_emit\_stealth\_debug\_trace\_if\_needed() (1570).

- Переносится в enemy\_debug\_snapshot\_runtime.gd:

- все \_debug\_\* поля

- \_refresh\_transition\_guard\_tick

- get\_debug\_detection\_snapshot (в виде export\_snapshot(enemy, awareness, runtimes...) или internal accumulated state)

- \_emit\_stealth\_debug\_trace\_if\_needed

- API для записи debug-событий по фазам tick (record\_visibility, record\_fire, record\_transition, record\_alert, record\_intent, record\_facing)

- Остается в Enemy:

- публичный get\_debug\_detection\_snapshot() как thin proxy

- set\_stealth\_test\_debug\_logging() как thin proxy или ownership toggle

- Удаляется:

- \_debug\_\* поля из Enemy

- ручная простыня присваиваний debug полей в хвосте runtime\_budget\_tick() (enemy.gd (lines 769-802))

- Новые тесты (обязательные):

- test\_enemy\_debug\_snapshot\_runtime\_shape\_contract.gd

- test\_enemy\_debug\_snapshot\_runtime\_value\_bridge.gd

- test\_enemy\_debug\_transition\_guard\_runtime.gd

- Мигрируются существующие тесты:

- любые тесты, которые читали snapshot keys напрямую, должны продолжить работать без изменения ключей

- если есть тесты, завязанные на приватные \_debug\_\* поля, перевести на get\_debug\_detection\_snapshot()

- Влияние на соседние модули:

- UI/debug consumers (test\_ui\_snapshot\_driven.gd, debug panels) не должны почувствовать изменений

- Критерий завершения:

- Enemy.get\_debug\_detection\_snapshot() возвращает тот же shape/семантику, Enemy не содержит \_debug\_\* cluster

- Легаси-правило закрытия фазы:

- любые проверки приватных `enemy._debug_*` полей переводятся на `Enemy.get_debug_detection_snapshot()`; keyset snapshot frozen и не меняется.

## **Фаза 9. Сжатие runtime\_budget\_tick() до фазового пайплайна (оркестратор вместо god-method)**

- Цель: превратить runtime\_budget\_tick() (enemy.gd (line 510)) из монолита в читаемый оркестратор фаз.

- Изменения в Enemy:

- разбить логику tick на приватные методы-фазы с фиксированным порядком

- сохранить порядок side-effect-ов и двойной room-alert capture (до и после execute\_intent)

- Предлагаемые фазы (именно в таком порядке):

- \_tick\_phase\_inputs\_and\_visibility(...)

- \_tick\_phase\_awareness\_confirm(...)

- \_tick\_phase\_target\_memory\_and\_alert\_snapshot\_pre\_intent(...)

- \_tick\_phase\_decision\_and\_pursuit(...)

- \_tick\_phase\_combat\_role\_and\_fire(...)

- \_tick\_phase\_alert\_snapshot\_post\_intent(...)

- \_tick\_phase\_ui\_and\_debug(...)

- Переносится: orchestration code внутри Enemy, логика runtime уже вынесена.

- Удаляется:

- монолитные куски внутри runtime\_budget\_tick(); метод должен стать orchestration-only

- Новые тесты (обязательные):

- test\_enemy\_runtime\_tick\_phase\_order\_contract.gd (spy/stub harness, порядок вызовов)

- test\_enemy\_runtime\_tick\_double\_alert\_snapshot\_contract.gd (пред- и пост-intent snapshot остаются двумя фазами)

- Переписываются легаси интеграционные тесты, которые дергали приватный room-id helper:

- test\_ai\_transition\_single\_owner.gd

- test\_ai\_no\_duplicate\_state\_change\_per\_tick.gd

- test\_force\_state\_path.gd

- test\_stealth\_room\_alert\_flashlight\_integration.gd

- Влияние на соседние модули:

- AIWatchdog.begin\_ai\_tick()/end\_ai\_tick() остается вокруг всей функции

- EnemyPursuitSystem.execute\_intent() вызывается один раз за tick как и раньше

- Критерий завершения:

- runtime\_budget\_tick() читабелен и содержит только orchestration, без доменной логики

- Легаси-правило закрытия фазы:

- тесты orchestration-слоя не используют `enemy.call("_resolve_room_id_for_events")` и другие private orchestration callbacks напрямую.

## **Фаза 10. Миграция и очистка тестового легаси (white-box на Enemy, встроенные mini-tests, text gates)**

- Цель: убрать тестовый легаси, который привязан к приватным полям/методам Enemy, и обновить gate-тесты на новую архитектуру.

- Удаляется легаси-тестовый стиль:

- прямые enemy.\_... доступы там, где появились runtime unit tests

- прямые enemy.set("\_combat\_search\_\*", ...) для white-box сценариев

- встроенные “Phase X bugfix unit tests” внутри test\_runner\_node.gd (lines 1012-1116)

- Что переносится:

- эти mini-checks выносятся в отдельные файлы или поглощаются существующими standalone тестами (предпочтительно второе, без дублирования)

- Что остается:

- интеграционные и e2e сценарии (3zone, replay, smoke, stress)

- Обязательные изменения в тестах/гейтах:

- test\_extended\_stealth\_release\_gate.gd (line 11) обновить DEPENDENCY\_GATES, чтобы grep смотрел новые runtime-файлы вместо enemy.gd-монолита

- test\_refactor\_kpi\_contract.gd добавить KPI на наличие enemy runtime helper scripts и отсутствие крупных legacy-блоков в enemy.gd

- test\_runner\_node.gd убрать embedded micro-tests Enemy (bugfix-фаза стиль), оставить только регистрацию scene suites

- Новые тесты (обязательные):

- test\_enemy\_refactor\_kpi\_enemy\_helpers.gd (или расширить test\_refactor\_kpi\_contract.gd)

- test\_enemy\_runtime\_compat\_aliases\_contract.gd (если сохраняются статические fire debug aliases на Enemy)

- Полная легаси-матрица закрытия (обязательна к концу этой фазы):

- Search white-box legacy полностью закрыт: `test_combat_next_room_scoring_no_loops.gd`, `test_dark_search_graph_progressive_coverage.gd`, `test_alert_combat_search_session_completion_contract.gd`, `test_repeated_blocked_point_triggers_scan_then_search.gd`, `test_unreachable_shadow_node_forces_scan_then_search.gd`, `test_combat_search_per_room_budget_and_total_cap.gd`.

- Fire white-box legacy полностью закрыт: `test_enemy_fire_decision_contract.gd`, `test_enemy_shotgun_fire_block_reasons.gd`, `test_enemy_fire_trace_cache_runtime.gd`, `test_first_shot_delay_starts_on_first_valid_firing_solution.gd`, `test_first_shot_timer_starts_on_first_valid_firing_solution.gd`, `test_first_shot_timer_pause_and_reset_after_2_5s.gd`, `test_friendly_block_prevents_fire_and_triggers_reposition.gd`, `test_shadow_flashlight_rule_blocks_or_allows_fire.gd`, `test_telegraph_profile_production_vs_debug.gd`, `test_enemy_fire_cooldown_min_guard.gd`, `test_stealth_weapon_pipeline_equivalence.gd`.

- Role white-box legacy полностью закрыт: `test_combat_role_lock_and_reassign_triggers.gd`, `test_tactic_flank_requires_path_and_time_budget.gd`, `test_combat_flank_requires_eta_and_path_ok.gd`.

- Latch/Detection/Orchestration white-box legacy закрыт: `test_zone_enemy_wiring.gd`, `test_state_doctrine_matrix_contract.gd`, `test_last_seen_used_only_in_suspicious_alert.gd`, `test_alert_flashlight_detection.gd`, `test_suspicious_flashlight_30_percent_seeded.gd`, `test_suspicious_shadow_scan.gd`, `test_team_contain_with_flashlight_pressure.gd`, `test_blood_evidence_no_instant_combat_without_confirm.gd`, `test_blood_evidence_sets_investigate_anchor.gd`, `test_reaction_latency_window_respected.gd`, `test_ai_transition_single_owner.gd`, `test_ai_no_duplicate_state_change_per_tick.gd`, `test_force_state_path.gd`, `test_stealth_room_alert_flashlight_integration.gd`.

- Embedded mini-tests удалены: блок `SECTION 18c: Bugfix phase unit tests` в `test_runner_node.gd` и standalone `test_phase_bugfixes.gd`.

- Точный update dependency gates в `test_extended_stealth_release_gate.gd`:

- `PHASE-15`: `rg -n "target_context_exists|SHADOW_BOUNDARY_SCAN|if not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT\\.ALERT" src/systems/enemy_utility_brain.gd src/entities/enemy_detection_runtime.gd src/entities/enemy.gd -S`

- `PHASE-16`: `rg -n "_record_combat_search_execution_feedback|_select_next_combat_dark_search_node|combat_search_shadow_scan_suppressed|combat_search_total_cap_hit" src/entities/enemy_combat_search_runtime.gd src/entities/enemy_debug_snapshot_runtime.gd src/entities/enemy.gd -S`

- `PHASE-17`: `rg -n "repath_recovery_reason|repath_recovery_request_next_search_node|repath_recovery_intent_target" src/systems/enemy_pursuit_system.gd src/entities/enemy_combat_search_runtime.gd -S`

- `PHASE-18`: `rg -n "slot_role|cover_source|cover_los_break_quality|flank_slot_contract_ok" src/systems/enemy_squad_system.gd src/systems/enemy_utility_brain.gd src/entities/enemy_detection_runtime.gd -S`

- KPI-contract update (обязательный):

- В `test_refactor_kpi_contract.gd` добавить проверки наличия `enemy_*_runtime.gd` helper scripts и wiring preload markers в `enemy.gd`.

- Начиная с Фазы 11 KPI проверяет отсутствие legacy runtime prefixes в `enemy.gd`: `_combat_search_`, `_combat_role_`, `_combat_first_`, `_combat_telegraph_`, `_debug_last_`.

- Zero-tolerance grep для phase close:

- `rg -n "enemy\\._|enemy\\.set\\(\"_|enemy\\.call\\(\"_" tests -S`

- ожидаемый результат: 0 матчей для `Enemy`-тестов, кроме явно зафиксированных permanent public API проверок.

- Влияние на соседние модули:

- нет gameplay-влияния, только тестовая инфраструктура и текстовые dependency gates

- Критерий завершения:

- нет встроенных white-box mini-tests в test\_runner\_node.gd для Enemy

- dependency gates и KPI gates зеленые

## **Фаза 11. Финальная чистка compatibility wrappers и переносов**

- Цель: удалить временные delegating wrappers и завершить декомпозицию.

- Удаляется из Enemy:

- временные приватные delegating wrappers к runtime-модулям (combat search / fire / role / latch / detection), если тесты мигрированы

- временные compatibility hooks, созданные только ради промежуточной миграции

- точный список wrappers, которые должны исчезнуть в этой фазе:

- search: `_update_combat_search_runtime`, `_record_combat_search_execution_feedback`, `_apply_combat_search_repath_recovery_feedback`, `_select_next_combat_dark_search_node`, `_select_next_combat_search_room`, `_build_combat_dark_search_nodes`, `_update_combat_search_progress`.

- fire: `_resolve_shotgun_fire_block_reason`, `_resolve_shotgun_fire_schedule_block_reason`, `_can_fire_contact_allows_shot`, `_should_fire_now`, `_update_first_shot_delay_runtime`, `_reset_first_shot_delay_state`, `_register_friendly_block_and_reposition`, `_build_fire_line_excludes`, `_roll_telegraph_duration_sec`, `_resolve_ai_fire_profile_mode`, `_shotgun_cooldown_sec`, `_shotgun_stats`.

- role: `_update_combat_role_runtime`, `_reset_combat_role_runtime`, `_assignment_supports_flank_role`, `_resolve_contextual_combat_role`.

- latch/zone: `_resolve_room_alert_snapshot`, `_sync_combat_latch_with_awareness_state`, `_update_combat_latch_migration`, `_get_zone_state`, `_is_zone_lockdown`.

- detection: `_tick_reaction_warmup`, `_build_utility_context`, `_resolve_known_target_context`, `_compute_flashlight_active`.

- Что сохраняется намеренно (не удалять):

- публичные методы Enemy

- публичные константы Enemy.SQUAD\_ROLE\_\*, Enemy.SHOTGUN\_FIRE\_BLOCK\_\*, Enemy.COMBAT\_FIRE\_PHASE\_\* (если на них завязаны тесты/код)

- публичные static debug aliases Enemy.debug\_reset\_fire\_sync\_gate(), Enemy.debug\_reset\_fire\_trace\_cache\_metrics(), Enemy.debug\_get\_fire\_trace\_cache\_metrics() (либо оставить permanently, либо убрать только после полной замены всех ссылок)

- Новые тесты:

- не добавлять новые behavior-тесты; только повторный прогон всех контрактов + regression gates

- Влияние на соседние модули:

- не должно быть, если соблюдены alias/public API инварианты

- Критерий завершения:

- Enemy — оркестратор + Godot node lifecycle + wiring + presenters, без крупных доменных runtime-state кластеров

## **Фаза 12. Полный регрессионный прогон и выпускной gate**

- Цель: подтвердить отсутствие регрессий после удаления совместимости.

- Обязательный прогон:

- targeted unit suites по новым runtime-модулям

- существующие integration suites по enemy/stealth/combat/search/fire

- test\_refactor\_kpi\_contract.gd

- test\_extended\_stealth\_release\_gate.gd

- performance/replay/checklist gates (через ваш текущий CI/runner)

- Точный минимальный командный набор финального gate:

- `xvfb-run -a godot-4 --headless res://tests/test_navigation_path_policy_parity.tscn`

- `xvfb-run -a godot-4 --headless res://tests/test_shadow_policy_hard_block_without_grant.tscn`

- `xvfb-run -a godot-4 --headless res://tests/test_shadow_stall_escapes_to_light.tscn`

- `xvfb-run -a godot-4 --headless res://tests/test_pursuit_stall_fallback_invariants.tscn`

- `xvfb-run -a godot-4 --headless res://tests/test_combat_no_los_never_hold_range.tscn`

- `xvfb-run -a godot-4 --headless res://tests/test_refactor_kpi_contract.tscn`

- `xvfb-run -a godot-4 --headless res://tests/test_extended_stealth_release_gate.tscn`

- `xvfb-run -a godot-4 --headless res://tests/test_runner.tscn`

- Удаляется: ничего.

- Критерий завершения:

- все обязательные suites зелёные

- dependency gates обновлены и проходят

- нет прямых white-box обращений к приватному state Enemy, кроме осознанно сохраненных интеграционных исключений (если такие останутся, их список фиксируется)


## **Сводные блоки**

- Нормативные и легаси-правила из бывшего блока `Дополнение v2.1` встроены в соответствующие фазы (2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12).

- Для передачи другому разработчику используется только фазовая структура выше: один phase = один PR, отдельного “надфазного” блока больше нет.
