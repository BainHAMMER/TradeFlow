# Changelog

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

