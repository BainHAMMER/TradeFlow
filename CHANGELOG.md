# Changelog

## v1.0.9
- **Profit Scanner (`Gold/hr` Sort, Source Filters & Queue Integration) (`Modules\Profit\ProfitEngine.lua`, `Modules\Profit\ProfitView.lua`, `Core\Queue.lua`):**
  - Added **Sort: Gold/hr** (`Доход/ч`) ranking recipes by hourly profit across full crafting + subcraft cast duration, automatically comparing intermediate subcraft vs direct AH purchase (`gphCraftPlan`) when sorting by `Gold/hr` (while expanding subcrafts from owned bags when `Only from bags` or `Shift+Click` is used).
  - Added unlearned recipe source filters (**Trainer**, **Vendor (in stock)**, **Other**) to the Profit scanner.
  - Updated **Queue All** (`В очередь все`) in Details and `Shift+Click` (`+Queue`) in Profit to subtract materials already reserved by existing queue steps (`GetRemainingCraftableCount`).
- **AH Sniper Fast Buyout, Manual Targets & Budget Limits (`Modules\Profit\Sniper.lua`, `Modules\Profit\ProfitView.lua`, `UI\MainFrame.lua`):**
  - Added 2-step `#hwevent`-compliant **Fast Buyout** button on the floating AH Sniper bar with live price/availability verification and automatic cancellation if a deal vanishes or exceeds the target price.
  - Added **Sniper Settings** popup (`Settings` in Sniper tab / `Limits` on AH bar) with configurable buyout limits: **Max budget per buyout** (default `10g`), **Min gold reserve in bags** (default `0`), and **Max quantity per buyout** (default `200`).
  - Added manual Sniper target input (item name, item ID, bag drag-and-drop, or `Shift+Click` link), exact price editing, `/tf snipe` command, and recursive subcraft expansion to AH reagents when clicking `Snipe` on a recipe.
- **Toggleable Craft & Cashflow Profit Log (`Modules\Profit\ProfitLog.lua`, `Modules\Profit\ProfitView.lua`, `UI\VendorAuction.lua`):**
  - Added **Mode: Craft** (`Крафт`) and **Mode: Cash** (`Касса`) toggle in the Profit Log subtab, tracking real AH purchases (shopping list & sniper), event-driven vendor reagent/scroll purchases (`BuyMerchantItem` & merchant catalog bag delta), trainer recipe learning expenses, vendor sales of crafted items, and AH mail payouts (including disenchant materials from crafted items).
  - Tracks real purchase lots (`purchaseLots`) to compute actual craft costs (`(факт)`) in Craft mode and moved **Clear Profit Log** into the **Settings** window to prevent accidental resets.
- **Enchanting Target Slot & Spacebar Confirm (`Core\Core.lua`, `UI\QueueView.lua`):**
  - Added automatic target item/slot selection for Enchanting (`CraftEnchant`) with a drag-and-drop manual target slot in the Queue panel and temporary `Spacebar` confirmation for `ReplaceEnchant` prompts.
- **Recipe Favorites Synced with Blizzard UI (`Core\Core.lua`, `UI\MainFrame.lua`, `Modules\Profit\ProfitView.lua`):**
  - Added right-click favorite toggling on recipes in the left list, Details icon, and Profit scanner with bidirectional `C_TradeSkillUI.SetRecipeFavorite` / `TRADE_SKILL_FAVORITES_CHANGED` synchronization, star badges, top pinning, and a dedicated **Favorites** category.
- **Leveling Planner, Queue & Performance Improvements (`Core\Planner.lua`, `Core\Queue.lua`, `Core\Prices.lua`, `UI\VendorAuction.lua`):**
  - Split planner recipe source checkboxes into **Trainer**, **Vendor (in stock)** (`Data\Vendor.lua` `VendorRecipeScrolls`), and **Other** (scrolls/drops/quests with AH price), ordered intermediate subcrafts before consumer steps, and expanded unlearned subcrafts in routes and shopping lists.
  - Filtered non-disenchantable items (wands, shirts, tabards, bags, fishing poles) and integrated `DisenchantBuddy.API.v1` when available.
  - Debounced Auctionator shopping list syncs (`ScheduleAuctionatorSync`), deferred background syncs while the Auction House is open, converted header profession icons and Details **Craft** button to `SecureActionButtonTemplate`, and eliminated CPU/GC spikes during route calculation and UI refreshes.

## v1.0.8
- **Blizzard Professions Frame Integration & Mining Icon (via PR #5 by `frostmx`):**
  - **First-Open Session Fix (`UI\MainFrame.lua`):** Hid newly created `TradeFlowMainFrame` before attaching `OnHide` so first open after `/reload` or `/tf lang` no longer triggers `CloseTradeSkill()`.
  - **General Tab (`BookPage`) & Fishing (`Core\Core.lua`):** Stopped `SuppressBlizzardFrame()` from hiding Blizzard's general `BookPage` tab or non-TradeFlow professions (e.g. Fishing, tracked via `ns.blizzardOwnsTradeSkill`), and restored TradeFlow cleanly without closing the Blizzard skill.
  - **Return Button & Blizzard UI Button (`Core\Core.lua`, `Locales\*.lua`):** Hooked `Blizzard_Professions` immediately on `ADDON_LOADED`/`PLAYER_LOGIN` so the `TradeFlow` return button is present from the very first `K` press (keeping `preferTradeFlow` intact), and updated `OpenBlizzardProfessions()` to check `GetOpenTradeSkillID()` and print `BLIZZARD_UI_NEED_PROF` when opened via `/tf` with no profession active.
  - **Mining Icon (`Core\Core.lua`):** Updated Mining (`186`) fallback icon to `Trade_Mining` and preserved the `GetProfessionInfo` pickaxe icon across Smelting opens.

## v1.0.7
- **Profit Scanner & AH Reagent Sniper (`Core\Modules.lua`, `Modules\Profit\*`):**
  - Added modular **Profit** tab (with enable/disable toggle in Settings) scanning profitable recipes across current character and alts by channel (`All`, `Safe: Vendor+DE`, `Auction`), margin, freshness, and craftability, with batch `+Queue` shortcuts (`+1 / +5 / +10 / all`).
  - Added **Sniper** subtab and floating AH alert bar: track target buy thresholds (`-20%` from AH or shopping import), sync `"TradeFlow: Sniper"` list in **Auctionator**, auto-scan on AH open (30s cooldown), bulk reprice `-20%`, play audio/chat alerts on new deals (preserving detailed 1-tier commodity counts vs aggregate scans), and open spotted deals directly.
  - Added **Craft Profit Log** subtab tracking actual craft cost/revenue/profit with coalescing, Today / All-time totals, exclusion of queue intermediate subcrafts, and deduction of consumed home-crafted intermediates on final crafts.
- **Queue Crafting Time & Safe Profession Switching (`UI\QueueView.lua`, `Core\Core.lua`, `Core\Queue.lua`):**
  - Displayed estimated crafting duration (`C_Spell.GetSpellInfo`) per queue step and total remaining queue time in the footer.
  - Made sidebar/tab profession switching UI-only and converted the queue action button to `SecureActionButtonTemplate` to prevent `ADDON_ACTION_BLOCKED` taint when switching professions.
- **Bank Withdraw & Container Indexing Fixes (`Core\Inventory.lua`, `UI\VendorAuction.lua`):**
  - Added bank stock deduction in shopping list buy counts, Auctionator sync, and DAG subcraft expansion.
  - Serialized bank withdrawal steps (`0.14s`), fixed `Enum.BagIndex` handling (`ReagentBag = 5` vs `BankBag_1..7 = 6..12`) so full banks no longer throw `"Bank is full"`, and ensured bank withdraw button re-enables cleanly on early bank close.
- **Leveling Planner, Recipe Data & Diagnostics (`Core\Planner.lua`, `Data\Recipes.lua`, `Data\Trainer.lua`, `Core\DebugLog.lua`):**
  - Upgraded the leveling route planner to beam search with exact trainer/book milestone fees, unified return calculation, and category collapse fix (`pinnedRecipeBySkill`).
  - Cleaned specialization-gated recipes from `TrainerFees` and non-Apprentice recipes from `BasicRecipes`.
  - Added persistent `/tf log` diagnostic window (`DebugLog`) capturing `ADDON_ACTION_BLOCKED`, `LUA_WARNING`, bank `UI_ERROR_MESSAGE`, and recent call traces.

## v1.0.6
- **Leveling Calculator Priority Toggle (`UI\RouteView.lua`, `Core\Planner.lua`):**
  - Added a `Priority: Speed` / `Priority: Profit` toggle button in the leveling route calculator.
  - **Speed** mode strongly prioritizes guaranteed (100% orange) and high-chance recipes over low-chance green steps; **Profit** mode minimizes net gold spent / maximizes per-craft profit without inflating profit by `1 / chance`.
  - Fixed simulation math to evaluate owned bag/bank reagents against the full expected `craftsPerPoint` instead of per-single-craft cost.
- **Optional AH Depth & Seen Stock Tracking (`Core\Prices.lua`, `Core\Planner.lua`, `UI\MainFrame.lua`):**
  - Added a **Settings** toggle (`Account for AH seen stock`, off by default) that captures visible Auction House price ladders (up to 25 price tiers per item) from `Auctionator.Database:ProcessScan` and Blizzard AH search updates into `ahStock`.
  - When enabled, the leveling route consumes cheaper AH lots step-by-step and escalates remaining reagent purchases to higher-priced tiers (or flags `Low AH stock` if total visible supply runs out), and Details shows seen AH stock counts alongside `Auction`.
- **Bank Withdraw Bar Fix (`Core\Queue.lua`, `UI\FloatingBars.lua`):** Refreshed bank withdraw bar visibility on `BankFrame` `OnShow`, delayed `BANKFRAME_OPENED`, and `OnInventoryUpdated` so the withdraw prompt appears even before opening the profession window.

## v1.0.5
- **Disenchanting System (`Core\Prices.lua`, `Core\Planner.lua`, `UI\MainFrame.lua`):**
  - Integrated exact Classic / Forever disenchant probability tables (armor & weapon brackets, min-max yields `x1-2`, dust/essence/shard breakdown) via PR #2 (`frostmx`).
  - Added a dedicated Disenchant materials block below reagents in the Details view showing item icons, quantity ranges, drop chances, live Auctionator prices, and net expected value (`-5%`).
  - Economy calculation now evaluates all available output sources (`vendor`, `ah`, `disenchant`) side-by-side in the Details economy panel (highlighting the best source) and includes disenchant return in cost per `+1` skill and the leveling route calculator.
  - Recipes where crafting pays for itself or profits now show green `+amount` in Cost per `+1` skill and sort above zero-cost recipes.
- **Settings Frame (`UI\MainFrame.lua`):** Added a clean **Settings** popup with toggles for `Include disenchant value` (works even without Enchanting on the current character), `Show economy & disenchant in tooltip` (off by default), and `Categories`.
- **UI & Polish:**
  - Lowered `TradeFlowMainFrame` strata to `MEDIUM` so `DressUpFrame` (`Ctrl+Click`) and standard panels open on top cleanly.
  - Replaced the oversized inner economy frame border with a subtle vertical gold divider and verified zero UI overlaps across 0–6 reagents and 3 disenchant rows.
- **Reliability & Performance:** Invalidated `recipeEconomyCache` on async item data loads, prevented partial `liveRecipes` schematic skips during rescan, reset `settingsFrame` on language switch, and precomputed NPC distances before sorting in `Core\Sources.lua`.

## v1.0.4
- **Recipe Sources (`Core\Sources.lua`, `Data\Recipes.lua`):** Added `RecipeScrolls` lookup for unlearned non-trainer recipes, fixing false `trainer: 0c` tags. Shows clickable scroll item link, Auctionator price, client `sourceText`, and optional `QuestieDB` / `AtlasLootClassic` vendor, quest, and drop info (sorted by closest NPC to player).
- **TomTom Waypoints:** Added a `TomTom` button next to recipe sources when `TomTom` is loaded and coordinates are available.
- **UI & Navigation:**
  - Upgraded **Details / Leveling Calculator** and **Queue / Shopping List** buttons into distinct active-tab state toggles.
  - Added optional **Categories** grouping toggle with collapsible category headers in the recipe list.
  - Converted recipe **Sort** button into a dropdown menu; when sorted by **Profit**, non-grey recipes now display their net profit alongside skill-up %.
  - Moved **Sell to vendor** checkbox to the main header so vendor-only profit can be evaluated across the recipe list, details, and leveling calculator.
  - Added a **TradeFlow** return button on Blizzard's `ProfessionsFrame` and fixed switching back without `ADDON_ACTION_FORBIDDEN` or Lua errors.
- **Performance & Hotkey:** Skipped unnecessary leveling-route recalculations when the calculator tab is hidden, cached `GetRecipeEconomy`, skipped redundant `GetRecipeSchematic` calls for already scanned recipes, and improved first-open interception after `/reload`.

## v1.0.3
- Cleaned up unused static data, fixed `REAGENT_FROM_BANK` / `BANK_SHORT` localization, and added CurseForge automatic packaging workflow.

