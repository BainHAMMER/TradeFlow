# TradeFlow

**TradeFlow** is an all-in-one profession window replacement, smart DAG crafting queue, and 1–300 leveling route calculator for **World of Warcraft Forever (`Interface: 16001`)**.

---

## Key Features (EN)

* **Full Profession Window Replacement:** Clean, single-window layout combining your recipe list, detailed reagent breakdown, 1–300 leveling planner, crafting queue, and shopping list — with a 1-click **"Blizzard UI"** toggle whenever you want the default frame.
* **Native Client Item & Spell Resolution:** Every recipe and reagent is resolved live from the game client by ID (`C_Item` / `C_Spell`) with native item quality colors, icons, and full hover tooltips (`Shift+Click` to link or search AH, `Ctrl+Click` to preview).
* **Smart DAG Crafting Queue (Cross-Profession):** Automatically expands intermediate craftable reagents (such as smelting bars with Mining for Blacksmithing/Engineering recipes) in topological order, accounting for items already in your bags.
* **1–300 Cheapest Leveling Calculator:** Computes the most cost-effective path to your target skill (75 / 150 / 225 / 300) using exact orange/yellow/green/grey skill-up probabilities, trainer recipe fees, rank milestones, and optional vendor sellback deduction. Queue the entire route or up to the next trainer visit in one click.
* **Auctionator & Vendor Automation:**
  * Reads live auction prices via `Auctionator.API.v1` (with TSM / vendor fallbacks).
  * Automatically syncs missing reagents into a dedicated `"TradeFlow"` shopping list in **Auctionator** and launches multi-item AH searches.
  * Displays a 1-click **"Buy Missing List"** bar when visiting a vendor (`MERCHANT_SHOW`) to purchase exact required stacks of flux, coal, thread, vials, and spices.
* **Instant RU / EN Switch:** Switch the addon UI language between Russian (`RU`) and English (`EN`) directly from the window header without `/reload`.

### Slash Commands
* `/tf` or `/tradeflow` — Toggle the TradeFlow window
* `/tf blizz` — Open the default Blizzard Professions window
* `/tf clear` — Clear the active crafting queue

---

## Возможности (RU)

* **Полная замена окна профессий:** Единое окно без вложенных вкладок (список рецептов с фильтрами и поиском, детали рецепта и пороги навыка, калькулятор прокачки 1–300, очередь крафта и список покупок) + быстрая кнопка **«Окно Blizzard»** в шапке.
* **Реальные предметы и рецепты по ID из клиента:** Никаких кривых статических таблиц перевода — названия, иконки, качество и полные тултипы берутся напрямую из клиента игры по `itemID` / `spellID`.
* **Умная очередь крафта (DAG + смежные профессии):** Автоматически разворачивает промежуточные полуфабрикаты в правильном порядке (например, выплавку слитков в Горном деле для рецептов Кузнечного дела) с учётом того, что уже лежит в сумках.
* **Калькулятор дешёвой прокачки 1–300:** Строит оптимальный маршрут до выбранной цели (`75 / 150 / 225 / 300`) по реальной цене за `+1` навык с учётом шанса повышения, стоимости рецептов у тренера и выручки от продажи вендору. Отправка всего маршрута или шагов «До тренера» в очередь в 1 клик.
* **Интеграция с Auctionator и автозакупка у вендора:**
  * Расчёт себестоимости, профита и цены за `+1` навык по ценам **Auctionator**.
  * Автоматическое создание и обновление списка закупок `TradeFlow` в Auctionator и живой поиск недостающих реагентов на аукционе.
  * Панель **«Докупить по списку»** при открытии торговца — скупает нужные реагенты (уголь, плавень, нитки, колбы, специи) в 1 клик.
* **Мгновенное переключение языка `RU` / `EN`** прямо в шапке окна без `/reload`.

---

## License & Data Attribution

**TradeFlow** is licensed under the **GNU General Public License v3.0 or later (`GPL-3.0-or-later`)**. See [LICENSE](LICENSE) for full terms.

The static profession tables in `Data/` (`Recipes.lua`, `Thresholds.lua`, `Trainer.lua`, `Vendor.lua`) are derived from the following open-source projects and databases:
* **[SkillUp Forever](https://github.com/cjber/skillup-forever)** by `cjber` (`GPL-3.0-or-later`) — WoW Forever (`1.60.1.70938`) recipe, threshold, trainer, and vendor tables.
* **[wago.tools](https://wago.tools)** DB2 tables (`wow_classic_beta 1.60.1.70938` / `wow_classic_era 1.15.9.70576`).
* **[CMaNGOS classic-db](https://github.com/cmangos/classic-db)** (`GPL-3.0`) — trainer fees and rank quests.
* **[LibPeriodicTable-3.1](https://www.curseforge.com/wow/addons/libperiodictable-3-1)** (`LGPL-2.1`) — vendor reagent item IDs.


