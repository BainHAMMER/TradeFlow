# Changelog / Список изменений

## v1.0.17
### RU
- **Исправлено переключение профессий и запуск крафта:** кнопки «Создать» / «Создать шаг» и переключение профессий в шапке больше не рассинхронизируются с клиентом после открытия аукциона или смены профессии; исправлено чтение рангов Кулинарии и Первой помощи.
- **Стабильность в бою:** устранены Lua-ошибки секретных значений клиента в кулдаунах, очереди крафта, логе распыления и проверке кастов; исправлено зависание кнопки смены профессии и клавиши `Пробел` после выхода из боя.
- **Снайпер и аукцион:** авто-скан теперь выключен по умолчанию и автоматически ставится на паузу при выставлении лотов (вкладка продажи Blizzard / Auctionator); исправлено сообщение отмены выкупа при росте средней цены; починена кнопка «Очистить лог заработка».
- **Торговец, банк и тренер:** большие закупки у торговца идут порциями с проверкой слота (без потерь и случайных покупок при смене торговца); устранены дубли при быстром повторном клике «Забрать материалы» из банка и ложные пометки выученных рецептов у тренера.

### EN
- **Fixed profession switching & crafting launch:** Craft / Craft Next buttons and header switches no longer desync after visiting the Auction House or switching professions; fixed Cooking and First Aid rank reading.
- **Combat stability:** guarded cooldowns, crafting queue casts, disenchant loot tracking, and cast checks against client secret values; fixed leftover secure proxy and Spacebar binding after combat ends.
- **Sniper & Auction House:** auto-scan is now off by default and automatically pauses while on Sell / Auctionator Selling tabs; fixed buyout cancellation price message; fixed Clear Profit Log button crash.
- **Vendor, Bank & Trainer:** large vendor purchases are paced with slot verification; prevented duplicate bank withdrawals on rapid double-click and false-positive learned marks at trainers.

---

## v1.0.16
### RU
- **Ускоренный Снайпер аукциона:** сканирование списка целей теперь занимает доли секунды и не блокирует вкладку покупок; добавлен автоматический опрос при открытом аукционе (интервал `1–15` сек в настройках + быстрая галка «Авто» на плашке).
- **Удобное управление целями Снайпера:**
  - Плашка Снайпера перенесена под нижние вкладки аукциона.
  - В списке Снайпера появились галки вкл/выкл на каждом предмете (пауза без удаления), поле для ручной фиксации точного порога цены и кнопка «Авто» для возврата к авто-подстройке.
  - Добавлена авто-подстройка порогов под текущий рынок и настраиваемый процент скидки (`5–80%`).
  - Для найденных хитов автоматически подгружается точное количество дешёвых штук до выкупа.
- **Удобство и исправления интерфейса:**
  - Окно TradeFlow теперь запоминает своё положение между перезапусками и `/reload` при любом масштабе.
  - Окно TradeFlow больше не становится некликабельным при открытии аукциона.
  - Перенесён таймер кулдауна в правый верхний угол деталей рецепта, упрощены тултипы и добавлены подсказки ко всем пунктам настроек.

### EN
- **Faster Auction House Sniper:** scanning sniper targets now takes a fraction of a second without blocking the Shopping tab; added periodic auto-scanning while the Auction House is open (configurable `1–15s` interval + quick `Auto` toggle on the bar).
- **Sniper Target Controls:**
  - Moved the Sniper bar below the bottom Auction House tabs.
  - Added per-item enable/pause checkboxes, an inline price input to pin exact thresholds, and an `Auto` button to unpin.
  - Added automatic price adjustment to current market prices with a configurable target discount (`5–80%`).
  - Automatically fetches exact cheap lot counts for spotted hits before buyout.
- **UI Improvements & Fixes:**
  - TradeFlow now remembers its window position across `/reload` and game sessions at any UI scale.
  - Fixed the TradeFlow window becoming unclickable when opening the Auction House.
  - Moved the recipe cooldown label to the top-right of Recipe Details, simplified tooltips, and added tooltips to all Settings options.

---

## v1.0.15
### RU
- Убраны просадки FPS после крафта из очереди (спасибо `frostmx`).
- Кулдаун рецептов виден ещё до крафта, а активные таймеры обновляются в реальном времени.
- Забор из банка теперь берёт ровно нужное количество материалов, аккуратно отделяя остаток из наименьшего стака.
- В «Доходе/ч» учитывается время на распыление; исправлена «Цена за +1 навык» при выключенной продаже торговцу; убраны лишние подписи `/шт.` у залогов в «Кассе».

### EN
- Fixed FPS drops after crafting from the queue (thanks to `frostmx`).
- Recipe cooldowns are now visible before crafting, and active timers update live.
- Bank withdrawal now takes the exact needed amount, cleanly splitting the remainder from the smallest stack.
- Gold/hr now includes disenchant cast time; fixed Cost per +1 skill when Sell to vendor is unchecked; hid redundant `/ea` labels on AH deposits in Cash mode.

---

## v1.0.14
### RU
- Появилось отображение кулдаунов на крафты (список рецептов, детали, тултип и очередь).
- В «Кассе» теперь учитываются залоги при выставлении лотов на аукцион.
- Исправлено пропадание тултипов при наведении и работа кнопок переключения профессии.

### EN
- Added recipe cooldown display across the recipe list, details, tooltips, and queue.
- Cash mode now tracks Auction House posting deposits.
- Fixed tooltips disappearing on hover and improved profession switching buttons.

---

## v1.0.13
### RU
- Кнопки переключения профессии в очереди и шапке теперь срабатывают без необходимости уводить курсор.
- Крафтовые жезлы и вещи Наложения чар больше не считаются распыляемыми в расчёте прибыли.

### EN
- Profession switching buttons in the queue and header now work even without moving the cursor away.
- Crafted wands and Enchanting gear are no longer counted as disenchantable in profit calculations.

---

## v1.0.12
### RU
- Рядом с количеством доступных крафтов `[N]` добавлен остаток `(M)` за вычетом уже поставленного в очередь.
- Калькулятор прокачки теперь учитывает рыночную стоимость реагентов в сумках и банке, чтобы не предлагать невыгодные рецепты.

### EN
- Added a `(M)` badge next to `[N]` showing remaining craftable count after subtracting queued items.
- The Leveling Calculator now accounts for the market value of reagents already in your bags and bank.

---

## v1.0.11
### RU
- Окно TradeFlow теперь свободно открывается, закрывается (`X`, `Esc`, `/tf`), сворачивается и масштабируется прямо в бою.

### EN
- The TradeFlow window can now be opened, closed (`X`, `Esc`, `/tf`), minimized, and scaled freely during combat.

---

## v1.0.10
### RU
- Добавлены ползунок прокрутки списка рецептов, сворачивание списка (`>>`/`<<`), минимизация до очереди (`-`/`+`) и масштаб окна (`60%–140%`) в настройках.
- Исправлены добавление в избранное по ПКМ, работа в бою и разделение стаков при заборе из банка.

### EN
- Added a recipe list scrollbar, recipe pane collapse (`>>`/`<<`), compact queue mode (`-`/`+`), and window scale (`60%–140%`) in Settings.
- Fixed right-click favorites, combat errors, and bank stack splitting.

---

## v1.0.9
### RU
- Добавлены сортировка «Доход/ч», фильтры неизученных рецептов по источникам и учёт очереди в «В очередь все».
- В Снайпере появились быстрый выкуп на плашке, лимиты покупок и ручное добавление целей (`/tf snipe`).
- В логе заработка добавлены режимы «Крафт» и «Касса»; добавлены выбор цели для Наложения чар (`Пробел` для подтверждения) и Избранное по ПКМ.

### EN
- Added Gold/hr sorting, unlearned recipe source filters, and queue-aware Queue All.
- Added quick buyout on the Sniper bar, buyout limits, and manual target entry (`/tf snipe`).
- Added Craft & Cash log modes, Enchanting target selection (`Space` to confirm), and right-click Favorites.

---

## v1.0.8
- Исправлено закрытие окна профессии после `/reload` и смены языка, улучшена совместимость со стандартным окном Blizzard и исправлена иконка Горного дела.

## v1.0.7
- Добавлена вкладка «Заработок» (прибыльные рецепты, Снайпер и Лог), время крафта очереди и автозабор материалов из банка.

## v1.0.6
- Добавлены переключатель «Скорость / Прибыль» в калькуляторе прокачки и учёт наличия лотов на аукционе.

## v1.0.5
- Добавлен расчёт распыления и окно «Настройки».

## v1.0.4
- Добавлены источники неизученных рецептов, метки TomTom, категории, сортировки и кнопка возврата из окна Blizzard.

## v1.0.3
- Исправлена локализация банковских реагентов и настроена автосборка релизов.
