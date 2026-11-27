# TradeFlow

**TradeFlow** is an all-in-one profession window replacement, smart DAG crafting queue, 1–300 leveling route calculator, and Auction House profit & sniper toolkit for **World of Warcraft Forever (`Interface: 16001`)**.

---

## Key Features (EN)

* **Full Profession Window Replacement:** Clean, single-window layout combining your recipe list (with search, category/source filters, Right-Click favorites synced with Blizzard UI, cooldown timers, and `[craftable] (remaining)` badges), reagent breakdown, leveling planner, profit tools, crafting queue, and shopping list — with a 1-click **"Blizzard UI"** toggle.
* **Compact & Combat-Safe UI:** Collapse the recipe list (`>>`/`<<`), minimize to a compact queue/shopping window (`-`/`+`), adjust independent UI scale (`60%–140%`), and freely open/close the window in combat. Window position is saved across sessions and `/reload`.
* **Smart DAG Crafting Queue (Cross-Profession):** Automatically expands intermediate craftable reagents (such as smelting bars with Mining for Blacksmithing/Engineering) in topological order, accounting for items in your bags and bank, plus total craft time estimation and Enchanting target selection (`Space` to confirm).
* **1–300 Leveling Route Calculator:** Computes the cheapest or fastest path to your target skill (`75 / 150 / 225 / 300`) using exact orange/yellow/green/grey skill-up probabilities, trainer recipe fees, rank milestones, reagent opportunity cost, and optional vendor sellback. Queue the entire route or steps up to the next trainer in one click, and set **TomTom** waypoints for unlearned recipe sources.
* **Profit, Disenchanting & Cashflow Log:**
  * Ranks profitable crafts across your professions by **Profit** or **Gold/hr**, including disenchant expected value (with optional **DisenchantBuddy** data).
  * Tracks crafting profit and full cashflow (**Craft** & **Cash** modes), including Auction House sales, purchases, posting deposits, vendor reagents, and trainer fees.
* **Auction House Sniper:**
  * Fast targeted scanning with a dedicated bar below the Auction House tabs for 1-click buyouts, configurable spending/reserve/quantity limits, per-item pause/pin/`Auto` market adjustment, and manual targets (`/tf snipe`).
  * Optional periodic auto-scan (off by default, `1–15s` interval) that automatically pauses while posting auctions on Blizzard Sell or Auctionator Selling tabs.
* **Auctionator, Vendor, Bank & Trainer Automation:**
  * Reads live auction prices via **Auctionator** (`Auctionator.API.v1`, with TSM / vendor fallbacks) and syncs missing reagents into a `"TradeFlow"` shopping list.
  * 1-click **"Buy Missing"** bar at vendors (paced stack buying with slot verification), **"Withdraw Materials"** bar at the bank (exact stack splitting), and **"Learn Recipes"** bar at profession trainers.
* **Instant RU / EN Switch:** Switch the addon UI language between Russian (`RU`) and English (`EN`) directly from the window header without `/reload`.

### Optional Integrations
* **Auctionator** *(recommended)* — live AH prices and automatic shopping list sync
* **DisenchantBuddy** — disenchant yield and value calculations
* **TomTom** — map waypoints for unlearned recipe sources
* **TradeSkillMaster** — fallback price source

### Slash Commands
* `/tf` or `/tradeflow` — Toggle the TradeFlow window
* `/tf blizz` — Open the default Blizzard Professions window
* `/tf clear` — Clear the active crafting queue
* `/tf snipe <item link or ID> <price>` — Add a manual target to the Auction House Sniper

---

## Возможности (RU)

* **Полная замена окна профессий:** Единое окно со списком рецептов (поиск, фильтры по категориям и источникам неизученных рецептов, Избранное по ПКМ с синхронизацией с окном Blizzard, таймеры кулдаунов и счётчики `[доступно] (остаток)`), деталями рецепта, калькулятором прокачки, вкладкой заработка, очередью крафта и списком покупок — плюс кнопка **«Окно Blizzard»** в шапке.
* **Компактный и безопасный в бою интерфейс:** Сворачивание списка рецептов (`>>`/`<<`), компактный режим очереди (`-`/`+`), отдельный масштаб окна (`60%–140%`), сохранение позиции окна между сессиями и свободное открытие/закрытие прямо в бою.
* **Умная очередь крафта (DAG + смежные профессии):** Автоматически разворачивает промежуточные полуфабрикаты в нужном порядке (например, выплавку слитков в Горном деле для Кузнечного дела) с учётом реагентов в сумках и банке, показывает общее время крафта и поддерживает выбор цели для Наложения чар (`Пробел` для подтверждения).
* **Калькулятор прокачки 1–300:** Строит самый дешёвый или самый быстрый маршрут до выбранной цели (`75 / 150 / 225 / 300`) по реальной цене за `+1` навык с учётом шансов повышения, стоимости рецептов у тренера, рыночной стоимости имеющихся реагентов и выручки от продажи торговцу. Отправка всего маршрута или шагов «До тренера» в 1 клик, а также метки **TomTom** для источников рецептов.
* **Заработок, распыление и журнал прибыли:**
  * Поиск выгодных крафтов по **Прибыли** и **Доходу/ч**, включая расчёт распыления (с поддержкой **DisenchantBuddy**).
  * Лог заработка в режимах **«Крафт»** и **«Касса»** с учётом продаж, покупок, залогов аукциона, закупок у торговцев и обучения у тренеров.
* **Снайпер аукциона:**
  * Быстрое сканирование целей и плашка под нижними вкладками аукциона для быстрого выкупа, лимиты расходов/резерва/количества, пауза/фиксация цены/авто-подстройка под рынок по каждому предмету и ручное добавление целей (`/tf snipe`).
  * Опциональный авто-скан (выключен по умолчанию, интервал `1–15` сек), автоматически ставящийся на паузу на вкладках продажи Blizzard и Auctionator.
* **Автоматизация аукциона, торговца, банка и тренера:**
  * Живые цены и автообновление списка закупок `TradeFlow` через **Auctionator**.
  * Плашки в 1 клик: **«Докупить по списку»** у торговца (порционная покупка с проверкой слотов), **«Забрать материалы»** в банке (аккуратное разделение стаков) и **«Изучить рецепты»** у тренера.
* **Мгновенное переключение языка `RU` / `EN`** прямо в шапке окна без `/reload`.

### Опциональные аддоны
* **Auctionator** *(рекомендуется)* — актуальные цены аукциона и синхронизация списка покупок
* **DisenchantBuddy** — расчёт стоимости распыления
* **TomTom** — метки на карте для источников неизученных рецептов
* **TradeSkillMaster** — резервный источник цен

### Команды чата
* `/tf` или `/tradeflow` — Открыть / скрыть окно TradeFlow
* `/tf blizz` — Открыть стандартное окно профессий Blizzard
* `/tf clear` — Очистить очередь крафта
* `/tf snipe <ссылка или ID предмета> <цена>` — Добавить цель в Снайпер вручную

---

## License & Data Attribution

**TradeFlow** is licensed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)**. See [LICENSE](LICENSE) for full terms.

The static profession tables in `Data/` (`Recipes.lua`, `Thresholds.lua`, `Trainer.lua`, `Vendor.lua`) are derived from the following open-source projects and databases:
* **[SkillUp Forever](https://github.com/cjber/skillup-forever)** by `cjber` (`GPL-3.0-or-later`) — WoW Forever (`1.60.1.70938`) recipe, threshold, trainer, and vendor tables.
* **[wago.tools](https://wago.tools)** DB2 tables (`wow_classic_beta 1.60.1.70938` / `wow_classic_era 1.15.9.70576`).
* **[CMaNGOS classic-db](https://github.com/cmangos/classic-db)** (`GPL-3.0`) — trainer fees and rank quests.
* **[LibPeriodicTable-3.1](https://www.curseforge.com/wow/addons/libperiodictable-3-1)** (`LGPL-2.1`) — vendor reagent item IDs.
