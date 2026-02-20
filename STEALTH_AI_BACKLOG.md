# Stealth & AI Improvement Backlog
_Последнее обновление: 2026-02-19_

## Жанровый контекст
- **Стелс**: Hitman (без социального стелса) / Chronicles of Riddick / Manhunt
- **Комбат**: Hotline Miami (быстро, летально) + FEAR (тактический ИИ, координация)

---

## Статус: В очереди на реализацию

### Патруль
- **[8B] Cross-room patrol** — 20% шанс, enemy продлевает маршрут в соседнюю комнату (25% вглубь)

### Awareness / Perception
- **[AI-1] Recognition delay** — 0.15-0.3s warmup перед тем как suspicion начинает расти
- **[AI-6] Peripheral suspicion** — вне 120° FOV, в радиусе 150px → 0.05/s suspicion gain (без LOS)

### Координация врагов
- **[AI-2] Share search anchors** — enemy в ALERT broadcasts last_seen_pos через EventBus соседним врагам
- **[AI-3] Interrupt reaction** — enemy у waypoint делает LOOK sweep если рядом есть blood/body marker
- **[AI-4] Coordinated search formation** — squad назначает разные anchor points в search mode (extend squad roles на ALERT state)
- **[AI-5] Combat→ALERT memory** — использует позицию в момент потери LOS как начало поиска, не устаревший _last_seen_pos

### Teammate calls
- **[TC-1] Fix teammate calls** — убрать фильтр `from_state != "SUSPICIOUS"`, заменить на whitelist `["CALM", "SUSPICIOUS"]`

### FEAR: тактический комбат
- **[FEAR-1] Suppression state** — enemy под sustained fire (3+ выстрелов в 100px за 1.5с) → SUPPRESSED: остаётся за укрытием даже с чистым шотом. Даёт окно для flank-роли.
- **[FEAR-2] Last man panic** — последний живой враг в зоне: прижимается к укрытию, отступает к doorway, стреляет редко
- **[FEAR-3] Flanking via alternate path** — squad coordinator: PRESSURE идёт напрямую, FLANK идёт через соседнюю комнату с другой стороны
- **[FEAR-4] Reactive position change** — если игрок не двигался 3+ сек в COMBAT → squad одновременно меняет approach angles

### Manhunt: тёмный стелс
- **[MH-1] Door stacking** — enemy в ALERT паузит у doorway 0.5-1с, делает LOOK sweep перед входом в комнату

### Тела / Evidence
- **[BD-1] Death Marker (CorpseMarker)** — Area2D на позиции смерти, TTL 60-120с, радиус 80px. Патруль входит → `body_found` event → ALERT. После обнаружения уничтожается.
- **[BD-2] Missing Contact** — при патруле у door-adjacent точек: если в соседней комнате нет живых врагов из того же squad_id где раньше были → SUSPICIOUS с reason `missing_contact`

### Stealth Kill — Kill from Behind
- **[SK-1] Kill from behind** — keybind E, мгновенное бесшумное убийство
  - **Угол**: 60° конус за спиной врага (±30° от обратного facing direction)
  - **Условие**: `can_see_player() == false` (враг не видит игрока в данный момент). Работает в ЛЮБОМ состоянии — CALM/SUSPICIOUS/ALERT/COMBAT — если враг не смотрит на игрока
  - **Дальность**: melee range (~80px, уточнить с katana range)
  - **Активация**: нажал E → начинается 4-секундная процедура убийства
    - Оба (игрок и враг) ЗАБЛОКИРОВАНЫ на 4 секунды — не двигаются, не стреляют
    - Через 4 секунды → враг умирает. До этого — живой, просто удерживается
    - Прерывание НЕ предусмотрено (committed action — как в Manhunt)
    - Если другой враг видит игрока во время этих 4 секунд — он реагирует нормально (опасность!)
    - Это и есть основной риск: тихо, но ты уязвим 4 секунды
  - **Шум**: ноль. Абсолютно бесшумно.
  - **Бублик подозрения**: пока игрок заходит в back-cone, у врага МЕДЛЕННО нарастает suspicion (peripheral suspicion из [AI-6], или отдельный rate ещё тише). Это создаёт напряжение — нельзя торчать за спиной бесконечно, враг повернётся. Визуально — existing suspicion ring растёт.
  - **Анимация**: placeholder — enemy freeze на все 4 секунды потом смерть. Слот под будущую анимацию takedown.
  - **Дизайн-логика**: тихое убийство = медленное и опасное. Громкое (выстрел) = мгновенное но шумное. Трейдофф.
  - **UI hint**: highlight на враге (outline?) когда игрок в kill window и E доступен

---

## На будущее (не в ближайшем плане)

- Hunt Mode — зона "просыпается" после 2-3 тихих убийств (cross-room patrol 60%, sweep behavior)
- Kill noise tiers — тихий/быстрый/брутальный кил с разным noise radius
- Attract / бросок объекта — создать noise event в точке для отвлечения
- Execution window — момент в LOOK sweep когда можно пройти за спиной
- Blood trail — раненый игрок оставляет следы, enemy в ALERT получает direction hint
- Ambient noise masking — зоны где шаги не генерируют noise events
- Missing Contact (расширенный) — drag/hide body чтобы убрать с маршрута
