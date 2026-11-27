# Technical Changelog (Repo-only)

Detailed implementation notes for developers. End-user release notes live in [CHANGELOG.md](CHANGELOG.md).

## v1.0.17
### RU
- **Синхронизация активной профессии и прокси:** `GetActiveClientSkillLine()` проверяет `C_TradeSkillUI.IsTradeSkillReady()` (устраняет рассинхрон с `IsClientRecipeReady()` при закрытии серверной сессии); `TradeFlowSecureProfProxy` переведён на стратум `DIALOG` (`FrameLevel 50`) поверх `TradeFlowMainFrame` (`HIGH` + `SetToplevel(true)`).
- **Защита от secret values:** добавлен `SafeNumber(v)` с проверкой `issecretvalue(v)` в `GetRecipeCooldownRemaining`, `GetRecipeBaseCooldown` и `GetRecipeCastTime` (`Core/Core.lua`).
- **Порционная закупка у торговца:** `BuyVendorShoppingList` в `UI/VendorAuction.lua` отправляет `BuyMerchantItem` через `PumpBuyCalls()` порциями по 4 вызова каждые `0.15с` с проверкой `MerchantFrame:IsShown()`.

### EN
- **Active Profession Sync & Proxy Strata:** `GetActiveClientSkillLine()` now checks `C_TradeSkillUI.IsTradeSkillReady()` to stay aligned with `IsClientRecipeReady()`; `TradeFlowSecureProfProxy` moved to `DIALOG` strata above `TradeFlowMainFrame` (`HIGH` + `SetToplevel(true)`).
- **Secret Value Guard:** Added `SafeNumber(v)` using `issecretvalue(v)` across `GetRecipeCooldownRemaining`, `GetRecipeBaseCooldown`, and `GetRecipeCastTime`.
- **Paced Vendor Restocking:** `BuyVendorShoppingList` paces `BuyMerchantItem` calls via `PumpBuyCalls()` (4 calls per `0.15s` tick, guarded by `MerchantFrame:IsShown()`).

---

## v1.0.16
### RU
- **Быстрый батч-скан Снайпера:** `C_AuctionHouse.SearchForItemKeys` (чанки по 100, `AUCTION_HOUSE_BROWSE_RESULTS_UPDATED`/`ADDED`, `HasFullBrowseResults`/`RequestMoreBrowseResults`, фолбэк на `Auctionator.API.v1.MultiSearchAdvanced`), обход 5с троттлинга в `Core/Prices.lua` (`ProcessBrowseResults`) для активного батча и очистка пропавших хитов.
- **Периодический авто-скан и дозагрузка стакана:** тикер `ScheduleNextSnipeAutoScan` (`1–15s`, `snipeAutoScanInterval`) с защитами `pendingBuy`, `IsThrottledMessageSystemReady`, `lastExternalAhActivityAt`; `RequestTopSnipeHitDetails` (`SendSearchQuery`, 3с таймаут по `detailQueryToken`, `SNIPE_BUY_WAIT` на кнопке до прихода `COMMODITY_SEARCH_RESULTS_UPDATED`).
- **EMA авто-подстройка и управление целями:** `UpdateSnipeMarketEMA` (`alpha=0.25`, `EMA_SAMPLE_INTERVAL=15s`, `EMA_LOW_STREAK_THRESHOLD=4`, `EMA_MAX_UP_MULT=1.5`), `GetSnipeLiveMarketPrice`, `SetSnipeTargetEnabled`, инлайн-`priceBox` с `editingItemID` защитой при скролле/пересортировке, `ResetSnipeTargetPin`, синхронизация `snipeDiscountPct` (`5–80%`).
- **UI и упаковка:** сохранение `windowPos` (`absRight`/`absTop`, `ApplyUIScale(skipSave)`), `TradeFlowMainFrame` переведён на `HIGH` + динамический `FrameLevel + 20` для `TradeFlowSecureProfProxy`, `d.cooldownText` в шапке деталей, тултипы для всех опций `ToggleSettingsFrame` и модулей (`settingsTipKey`), `CHANGELOG_TECH.md` добавлен в `.pkgmeta` `ignore`.

### EN
- **Fast Batch Sniper Scan:** Native `C_AuctionHouse.SearchForItemKeys` (100-item chunks, pagination via `AUCTION_HOUSE_BROWSE_RESULTS_ADDED`, fallback to `MultiSearchAdvanced`), batch-aware `ProcessBrowseResults` in `Core/Prices.lua`, and stale-hit clearing.
- **Periodic Auto-Scan & Hit Breakdown:** `ScheduleNextSnipeAutoScan` (`1–15s`) with `pendingBuy`/throttle/external-activity guards; `RequestTopSnipeHitDetails` (`SendSearchQuery` + 3s `detailQueryToken` guard + `SNIPE_BUY_WAIT` state).
- **EMA Repricing & Target Controls:** `UpdateSnipeMarketEMA`, `GetSnipeLiveMarketPrice`, per-item `enabled` toggle, inline `priceBox` with `editingItemID` scroll/re-sort safety, `ResetSnipeTargetPin`, and dynamic `snipeDiscountPct`.
- **UI & Packaging:** Scale-independent `windowPos` persistence (`ApplyUIScale(skipSave)`), `HIGH` strata on `TradeFlowMainFrame` + dynamic `FrameLevel + 20` on `TradeFlowSecureProfProxy`, `d.cooldownText` header anchor, Settings tooltips (`settingsTipKey`), and `.pkgmeta` ignore for `CHANGELOG_TECH.md`.

---

## v1.0.15
### RU
- **Оптимизация производительности (устранена просадка FPS после крафта):**
  - Перерисовка окна после крафта из очереди объединена в один проход вместо трёх (дебаунс по затишью + окно ожидания сумок и скана профессии), записи `liveRecipes` обновляются на месте без лишних сбросов кэша, добавлено кэширование расчёта докрафта промежуточных реагентов (спасибо `frostmx`, PR #7).
- **Кулдауны на крафты:**
  - Базовое время восстановления рецепта (`GetSpellBaseCooldown`) отображается ещё до крафта (янтарный бейдж `[КД: ...]` в списке рецептов, строка в деталях и тултипе).
  - Активные таймеры КД обновляются в реальном времени (1с тикер, перерисовка только при изменении отформатированного текста без мутации SavedVariables).
- **Умный забор материалов из банка:**
  - Подбор стаков сначала забирает наибольшие целые стаки `<=` нехватки, а на финальный остаток безопасно отделяет ровно нужное количество из наименьшего стака (`SplitContainerItem` с защитой от залоченных слотов, резервированием слотов назначения и фоллбэком на `UseContainerItem`).
- **Экономика, Доход/ч и «Касса»:**
  - В `EvaluateGoldPerHour` при сбыте через распыление учитывается время каста «Распыления» (spell `13262`, fallback `3.0s`), с автоматическим сравнением против более быстрых каналов (`vendor`/`ah`).
  - Исправлен `ns.GetSkillUpReturn` при снятой галке «Продажа торговцу» — вычитается лучшая доступная выручка (включая аукцион `-5%`).
  - В режиме «Касса» скрыта подпись `*/шт.` для `ah_deposit` и строк с `unitP == 0`.

### EN
- **Performance Optimization:** Coalesced post-craft `RefreshVisibleUI` via trailing debounce + `MarkCraftSettle`, in-place `liveRecipes` updates, and `GetCraftableReagentCount`/`GetCraftableReagentFromPool` caching (PR #7 by `frostmx`).
- **Recipe Cooldowns:** Added `GetSpellBaseCooldown` display before crafting and a 1s live cooldown ticker with text-diffing.
- **Smart Bank Withdrawal:** Largest whole stacks `<= rem` first, then lock-guarded `SplitContainerItem` + reverse bag-slot reservation + `UseContainerItem` fallback.
- **Economy, Gold/hr & Cashflow:** Included Disenchant cast time (`13262`) in `EvaluateGoldPerHour`, fixed `GetSkillUpReturn` when `Sell to vendor` is unchecked, and hid `/ea` on `ah_deposit` and `0c/ea` rows.

---

## v1.0.14
### RU
- **Кулдауны на крафты:** отображение оставшегося КД в списке (`[КД: ...]`), деталях, тултипе и очереди (`На КД (...)`); блокировка кнопки «Создать».
- **Учёт залогов АХ в «Кассе»:** хуки `PostItem`/`PostCommodity` + точное сопоставление `PLAYER_MONEY`; возврат залога в письме с АХ автоматически сводит итог к `цена - 5%`.
- **Исправления UI:** `DetachSecureProfProxy` скрывает `GameTooltip` только при `GameTooltip:IsOwned(prev)`; `TradeFlowSecureProfProxy` перенесён на стратум `HIGH` с `SetAllPoints`, исправлен `AnyUp`, добавлена анимация нажатия и авто-отцепление.

### EN
- **Recipe Cooldowns:** Remaining CD shown across recipe list, Details, tooltip, and Queue; Craft button disabled while on CD.
- **AH Deposit Tracking:** `PostItem`/`PostCommodity` hooks + exact `PLAYER_MONEY` reconciliation in Cash mode.
- **UI Fixes:** `GameTooltip:IsOwned(prev)` guard in `DetachSecureProfProxy`; `TradeFlowSecureProfProxy` moved to `HIGH` strata with `SetAllPoints`, `AnyUp`-only click handling, press animation, and auto-detach.

---

## v1.0.13
### RU
- Перепривязка `TradeFlowSecureProfProxy` при неподвижном курсоре после обновления окна.
- Исключение всех крафтовых жезлов и экипировки Наложения чар из расчёта распыления (с `DisenchantBuddy` и без него).

### EN
- Stationary hover re-attach for `TradeFlowSecureProfProxy`.
- Excluded all crafted wands and Enchanting-crafted gear from disenchant calculations (with or without `DisenchantBuddy`).

---

## v1.0.12
### RU
- Счётчик оставшихся крафтов `(M)` за вычетом материалов, зарезервированных в очереди (`GetRemainingCraftableCount`).
- В Калькуляторе прокачки реагенты в сумках/банке оцениваются по рыночной стоимости (упущенная выгода), а не как `0c`.

### EN
- Added remaining craftable badge `(M)` minus active queue reservations (`GetRemainingCraftableCount`).
- Leveling Planner values owned bag/bank reagents at market opportunity cost instead of `0c`.

---

## v1.0.11
- Вынос защищённого каста смены профессии в прокси на `UIParent` — главное окно больше не имеет protected-детей и свободно закрывается/управляется в бою.
- Настроена публикация `CHANGELOG.md` через `.pkgmeta` для CurseForge и GitHub Releases.

## v1.0.10
- Вертикальный скроллбар списка рецептов, сворачивание левой панели (`>>`/`<<`), минимизация окна (`-`/`+`), независимый слайдер масштаба `60%–140%`.
- Исправлены: ПКМ-избранное с синхронизацией `C_TradeSkillUI`, `ADDON_ACTION_BLOCKED` в бою, ошибка разделения стаков при заборе из банка.

## v1.0.9
- Сортировка `Доход/ч`, фильтры неизученных рецептов по источникам, вычет очереди в `В очередь все` и `Shift+ЛКМ`.
- Снайпер аукциона: быстрый выкуп на плашке, окно лимитов (`10g` / `200` / резерв), ручное добавление и `/tf snipe`.
- Журнал заработка («Крафт» и «Касса»), выбор цели Наложения чар + `Пробел`, ПКМ-избранное.

## v1.0.8
- Исправлено закрытие сессии профессии после `/reload`/смены языка, работа с общим окном Blizzard и профессиями вне TradeFlow, кнопка возврата и иконка Горного дела.

## v1.0.7
- Вкладка «Заработок» (сканер, Снайпер, Лог), время крафта и очереди, безопасное переключение профессий, забор материалов из банка, `/tf log`.

## v1.0.6
- Переключатель `Скорость / Прибыль` в планировщике, опция `checkAuctionStock` (глубина стакана AH), исправление плашки банка.

## v1.0.5
- Расчёт распыления (Disenchant) и окно настроек.

## v1.0.4
- Источники неизученных рецептов, интеграция с TomTom, категории, сортировки, галка «Продажа торговцу», кнопка возврата из окна Blizzard.

## v1.0.3
- Очистка статических таблиц, исправление локализации банковских реагентов и настройка автосборки для CurseForge.
