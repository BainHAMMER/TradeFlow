# Changelog / Список изменений

## v1.0.13
### RU
- **Исправление переключения профессии из очереди и шапки:**
  - Исправлена ситуация, когда при наведённом курсоре на кнопку «Выбрать: ...» в очереди, «Открыть проф.» в деталях или иконку профессии в шапке после обновления окна клик не переключал активную профессию в клиенте игры — защищённый прокси теперь автоматически перепривязывается без необходимости уводить курсор.
- **Исправление расчёта распыления для Наложения чар:**
  - Все крафтовые жезлы (включая кастомные жезлы WoW Forever, такие как «Жезл из ветви грез») и экипировка, создаваемая Наложением чар, автоматически исключаются из расчёта выручки и прибыли от распыления (работает как с `DisenchantBuddy`, так и без него).

### EN
- **Profession Switching Button Fix:**
  - Fixed an issue where clicking `Switch to: ...` in the Queue, `Open Prof` in Details, or a header profession icon failed to switch the active game profession if the cursor remained stationary over the button during a UI refresh; the secure switch proxy now re-attaches automatically.
- **Enchanting Disenchant Exclusion Fix:**
  - Automatically excluded all crafted wands (including custom WoW Forever wands) and Enchanting-crafted gear from disenchant value and profit calculations, both with and without `DisenchantBuddy`.

---

## v1.0.12
### RU
- **Счётчик доступных крафтов за вычетом очереди:**
  - В списке рецептов слева и во вкладке «Заработок» рядом с общим доступным количеством `[N]` добавлен второй счётчик в круглых скобках `(M)` (или `(0)` серым цветом), показывающий сколько ещё штук можно поставить в очередь после вычета материалов, уже зарезервированных в текущей очереди крафта.
- **Калькулятор прокачки (упущенная выгода реагентов в наличии):**
  - Реагенты, которые уже лежат в сумках или банке персонажа, при построении маршрута прокачки теперь оцениваются по их рыночной стоимости на аукционе / себестоимости крафта (упущенная выгода), а не как бесплатные (`0c`). Это устраняет выбор невыгодных рецептов только из-за наличия дорогих реагентов в сумке. Бесплатными для последующих шагов считаются только полуфабрикаты, созданные предыдущим шагом самого маршрута.

### EN
- **Remaining Craftable Count Badge (Minus Queue):**
  - Added a secondary `(M)` badge next to `[N]` in the recipe list and Profit Scanner showing how many additional crafts can be queued after subtracting materials already reserved by the active crafting queue (displayed as grey `(0)` when all available materials are reserved).
- **Leveling Calculator (Opportunity Cost for Owned Reagents):**
  - Reagents already in the player's bags or bank are now valued at their market / crafting price (opportunity cost) during route planning rather than `0c`, preventing the calculator from picking inefficient recipes simply because expensive materials happen to be in the inventory. Only intermediate items produced by an earlier step of the route itself carry `0c` purchase cost.

---

## v1.0.11
### RU
- **Свободное закрытие и управление окном в бою:**
  - Защищённый каст смены профессии вынесен во внешний прокси на `UIParent`, благодаря чему главное окно `TradeFlow` больше не блокируется движком WoW в бою и мгновенно закрывается (по `X`, клавише `Esc` или `/tf`), открывается, сворачивается и меняет масштаб прямо во время боя.
- **Оформление списка изменений:**
  - Настроена публикация форматированного списка изменений на CurseForge и GitHub Releases вместо сырого лога коммитов.

### EN
- **Combat-Safe Window Closing & Controls:**
  - Moved secure profession switching to an external `UIParent` proxy button so the main `TradeFlow` window is never locked down during combat and can be closed (`X`, `Esc`, `/tf`), opened, minimized, and scaled freely while in combat.
- **Release Notes Formatting:**
  - Configured formatted Markdown changelog publishing for CurseForge and GitHub Releases instead of raw git commit logs.

---

## v1.0.10
### RU
- **Управление окном и список рецептов:**
  - Добавлен вертикальный ползунок прокрутки в список рецептов слева.
  - Добавлена кнопка сворачивания списка рецептов (`>>` / `<<`) в левом верхнем углу шапки — складывает левую панель и уменьшает ширину окна почти вдвое.
  - Добавлена кнопка минимизации окна (`-` / `+`) рядом с крестиком закрытия — сворачивает окно до компактной панели «Очередь / Список покупок».
  - В окно «Настройки» добавлен ползунок «Масштаб окна» (`60%–140%` с кнопкой сброса `100%`), работающий отдельно от общего масштаба интерфейса игры.
- **Исправления:**
  - Исправлено добавление рецептов в избранное по ПКМ (звезда больше не сбрасывается при первом нажатии во время синхронизации с интерфейсом Blizzard).
  - Исправлена блокировка `ADDON_ACTION_BLOCKED` при открытии или закрытии окна профессий во время боя (открытие/закрытие откладывается до выхода из боя).
  - Исправлена ошибка «Эти предметы разделить невозможно» при автоматическом заборе материалов из банка.

### EN
- **Window Controls & Recipe List:**
  - Added a vertical scrollbar to the recipe list.
  - Added a button (`>>` / `<<`) in the top-left header to collapse/expand the recipe list pane.
  - Added a minimize button (`-` / `+`) next to the close button to compact the window down to the Queue & Shopping List panel.
  - Added an independent Window Scale slider (`60%–140%` with a `100%` reset button) in Settings.
- **Fixes:**
  - Fixed right-click recipe favorite toggling so the star no longer resets on the first click while syncing with the Blizzard UI.
  - Fixed combat lockdown errors (`ADDON_ACTION_BLOCKED`) when opening or closing the window during combat.
  - Fixed `"Couldn't split those items"` errors when automatically withdrawing materials from the bank.

---

## v1.0.9
### RU
- **Модуль «Заработок» и очередь:**
  - Добавлена сортировка **«Сорт: Доход/ч»** — ранжирует рецепты по прибыли в час с учётом полного времени крафта и промежуточных полуфабрикатов (автоматически сравнивая покупку полуфабриката на аукционе и его ручной крафт).
  - Добавлены фильтры неизученных рецептов по источникам: **«У тренера»**, **«У вендора (в наличии)»**, **«Прочие»**.
  - Кнопки **«В очередь все»** и `Shift+ЛКМ` по `+Очередь` теперь вычитают материалы, которые уже зарезервированы текущей очередью крафта.
- **Снайпер аукциона:**
  - Добавлена кнопка быстрого выкупа на плашке Снайпера над аукционом (с проверкой актуальной цены и авто-отменой, если дешёвый лот уже купили).
  - Добавлено окно **«Настройки снайпера»** («Лимиты»): максимальный бюджет на один выкуп (по умолчанию `10g`), неснижаемый резерв золота в сумке и лимит штук за одну покупку (по умолчанию `200`).
  - Добавлено ручное добавление предметов в Снайпер (по названию, ID, перетаскиванием из сумки, `Shift+кликом` или командой `/tf snipe`).
- **Журнал заработка («Крафт» и «Касса»):**
  - Добавлен переключатель режимов **«Крафт»** (расчётная прибыль с учётом фактической цены закупки материалов) и **«Касса»** (реальное движение золота: закупки на АХ, покупки реагентов у торговцев, обучение у тренера, продажа вендору и выручка с почты АХ, включая материалы от распыления).
  - Кнопка **«Очистить лог заработка»** перенесена в окно «Настройки» для защиты от случайного сброса.
- **Наложение чар и Избранное:**
  - Добавлен слот выбора цели для Наложения чар в панели очереди (автовыбор подходящей вещи или перетаскивание вручную) и подтверждение замены чар клавишей `Пробел`.
  - Добавлено добавление/удаление рецептов в **Избранное** по ПКМ с синхронизацией со стандартным окном профессий Blizzard и отдельной категорией «Избранное».

### EN
- **Profit Scanner & Queue:**
  - Added **Sort: Gold/hr** ranking recipes by hourly profit across full crafting and subcraft duration.
  - Added unlearned recipe source filters (**Trainer**, **Vendor (in stock)**, **Other**).
  - **Queue All** and `Shift+Click` on `+Queue` now subtract materials already reserved by the active crafting queue.
- **AH Sniper:**
  - Added a fast buyout button on the floating AH Sniper bar with live price verification and auto-cancel if a deal vanishes.
  - Added **Sniper Settings** (`Limits`) with max buyout budget (`10g` default), minimum gold reserve, and max quantity per purchase (`200` default).
  - Added manual item entry (by name, ID, drag-and-drop, `Shift+Click`, or `/tf snipe`).
- **Profit Log (Craft & Cash Modes):**
  - Added **Craft** and **Cash** modes tracking actual AH purchases, vendor reagent purchases, trainer fees, vendor sales, and AH mail payouts (including disenchanted materials).
  - Moved **Clear Profit Log** into the Settings window.
- **Enchanting & Favorites:**
  - Added automatic and drag-and-drop target item selection for Enchanting with `Spacebar` confirmation for replacing enchants.
  - Added right-click recipe **Favorites** synced with the Blizzard Professions UI.

---

## v1.0.8
- Исправлено закрытие сессии профессии при первом открытии окна после `/reload` или смены языка.
- Исправлена работа со стандартной общей вкладкой профессий Blizzard и профессиями вне TradeFlow (например, Рыбалкой).
- Кнопка возврата в TradeFlow из окна Blizzard теперь появляется с самого первого открытия по клавише `K`.
- Исправлена иконка Горного дела в шапке окна при открытии «Выплавки металлов».

## v1.0.7
- Добавлена вкладка **«Заработок»**: сканер прибыльных рецептов (по персонажу и альтам), **Снайпер** дешёвых реагентов на аукционе и **Лог** заработка.
- Добавлено отображение времени крафта для каждого шага и общего времени очереди.
- Безопасное переключение профессий из очереди без блокировок интерфейса.
- Учёт материалов в банке при расчёте списка покупок и автоматический забор нужных реагентов при открытии банка.
- Улучшен поиск маршрута в калькуляторе прокачки и добавлено окно диагностики `/tf log`.

## v1.0.6
- Добавлен переключатель **«Приоритет: Скорость / Прибыль»** в калькуляторе прокачки.
- Добавлена опция **«Учитывать кол-во лотов на аукционе»** в настройках (учёт глубины рынка по ценовым уровням).
- Исправлено появление плашки забора материалов при открытии банка до открытия окна профессии.

## v1.0.5
- Добавлен расчёт **Распыления (Disenchant)** в деталях рецепта, списке рецептов и калькуляторе прокачки (таблицы шансов, количество пыли/субстанций/осколков и средняя выручка с учётом комиссии аукциона `-5%`).
- Добавлено окно **«Настройки»** в шапке аддона.

## v1.0.4
- Добавлено отображение источников получения для неизученных рецептов (торговцы, задания, дроп, цена свитка на аукционе) и интеграция с **TomTom**.
- Добавлена группировка рецептов по **Категориям** и меню выбора сортировки.
- Галка **«Продажа торговцу»** вынесена в шапку окна.
- Добавлена кнопка возврата **«TradeFlow»** в стандартном окне профессий Blizzard.

## v1.0.3
- Очистка статических таблиц, исправление локализации банковских реагентов и настройка автосборки для CurseForge.


