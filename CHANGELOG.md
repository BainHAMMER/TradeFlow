# Changelog

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
