---
id: S029
title: Избранное в Top Notch History
depends_on:
  - S023
  - S024
  - S025
  - S027
covers:
  - FR-002
  - FR-027
  - FR-035
  - BR-003
  - BR-023
  - BR-026
  - BR-027
  - NFR-016
  - NFR-025
  - NFR-027
  - NFR-028
---

# S029: Избранное в Top Notch History

Текущий статус находится в [STATE.md](../STATE.md). Решение [D-042](../DECISIONS.md#d-042-избранное-в-top-notch-с-защитой-от-автоматической-очистки) заменяет исторический вариант S029, зависевший от S028 и D-037.

## Пользовательский результат

Пользователь помечает часто используемую запись звездой и быстро находит её в той же History-панели. Избранное переживает перезапуск и автоматическую очистку независимо от возраста записи. Категорий и дополнительного окна нет.

## Подтверждённый scope

- Одна кнопка-звезда слева над Search: контурная в History, заполненная в Favorites. Повторный клик возвращает History.
- History включает все доступные записи, в том числе избранные; Favorites фильтрует только избранные. Search действует внутри выбранного режима.
- Звезда карточки видна при hover или keyboard selection; у избранной карточки заполненная звезда видна постоянно. Она добавляет/снимает marker без вставки или закрытия панели.
- Доступны все существующие типы History. Favorite принадлежит occurrence целиком, без копии payload. Reference-only файл остаётся ссылкой, а не резервной копией источника.
- Автоматическая очистка не удаляет избранную запись, её owned image/rich assets. Снятие звезды возвращает обычный срок хранения от существующего activityAt, не начинает новые 30 дней.
- Карточки, Enter/double-click paste, plain paste, focus restoration и hardware-safe placement сохраняют текущие контракты.

## Уточнения для реализации

Следующие детали выбраны при планировании в рамках существующего поведения:

- Каждое новое открытие панели начинается в History; режим не сохраняется между открытиями или relaunch. При переключении внутри панели query сохраняется, page cursor сбрасывается. Правила Search при новом открытии остаются прежними.
- Порядок без поиска остаётся activityAt DESC, id DESC; поиск сохраняет URL-first ranking. Favorite toggle не меняет activityAt и не переносит запись вверх. Успешная вставка сохраняет existing activity promotion.
- Selection сохраняется по ID, если он входит в новые результаты; иначе выбирается первая доступная карточка или empty state. При смене режима viewport начинает новую выдачу; изменение звезды в History не перезагружает всю ленту.
- Снятая звезда в Favorites убирает карточку из выдачи. Если её activity уже за cutoff, она подлежит обычному cleanup и может исчезнуть также из History сразу после обновления. Tooltip снятия объясняет возврат к обычному сроку хранения.
- Explicit Delete и Clear All удаляют также избранное по существующему delete contract. Текст подтверждения Clear All явно включает избранное. Unfavorite и Delete остаются разными действиями.
- Empty Favorites сообщает, что сюда попадают записи со звездой; непустой query без совпадений показывает состояние «Ничего не найдено».
- Кнопки имеют accessible names и pressed/value state, доступны через keyboard focus и VoiceOver. Новый глобальный shortcut не добавляется; Enter/Space на focused star выполняет только toggle, без card paste.
- Ошибка записи marker оставляет прежнее подтверждённое состояние и показывает retryable сообщение без содержимого буфера. Повторная команда setFavorite(id, desiredValue) идемпотентна; toggle удалённой occurrence не восстанавливает её.

## Вне scope

Категории, папки, теги, ручная сортировка, переименование записей, сохранённые Paste Stack, отдельное окно S028, sync, аккаунты, менеджер паролей и вставка изображения как файла. Избранное не добавляет защиту секретов, автозаполнение или шифрованное хранилище.

## Реализация и данные

Следовать разделу «Избранное S029» в [TECHNICAL.md](../TECHNICAL.md). Основные точки: HistoryEntry/descriptor, программная Core Data model и HistoryStore, HistoryService и его async adapter, HistoryViewModel, TopNotchHistoryShelf и card controls. Проверить все retention predicates, а не только removeExpired: fetchCurrent, pages, ranked search, selected payload resolution, asset cleanup и orphan reconciliation.

Добавление indexed favorite metadata требует совместимой migration существующей базы. Никакие text, URL, filenames или содержимое скриншота пользователя не используются в fixtures. Header star размещается в левой безопасной области над поиском, вне hardware notch. Звезда карточки читается поверх full-bleed image и не перекрывает основной paste hit target.

## Acceptance criteria

- [ ] Header star переключает единую панель History/Favorites; Search фильтрует выбранный режим; повторное открытие начинает History.
- [ ] Card star работает мышью, клавиатурой и VoiceOver, не запускает paste; favorite state сохраняется после relaunch для всех typed occurrences.
- [ ] Migration сохраняет UUID, activity, exact plain/rich payload и asset ownership; существующие записи получают false.
- [ ] Запись older-than-cutoff со звездой видна и находится в обоих режимах, включая deep search за первой страницей; её payload доступен для вставки.
- [ ] Автоматическая очистка сохраняет favorite image/rich assets, обычные expired записи удаляет. Снятие звезды не обновляет activity и возвращает запись под обычный cutoff.
- [ ] Delete/Clear All удаляют избранные metadata и owned assets, но не source files; quota overflow не вытесняет избранное.
- [ ] Paging остаётся ≤500 descriptors, без duplicates/gaps; mode/query/mutation generation отбрасывает устаревшие результаты, selection не указывает на исчезнувшую запись.
- [ ] Marker failure/retry и гонки toggle/delete/cleanup/paste не теряют payload, не воскрешают запись и не расходятся с UI.
- [ ] Installed-app matrix подтверждает focus, paste, keyboard/VoiceOver, empty/search states, Light/Dark, Increase Contrast, Reduce Transparency/Motion и notch/non-notch layout.
- [ ] Подписанное обновление с предыдущей публичной версии сохраняет существующую History, после обновления favorite survives relaunch. Release checks выполняются по существующему protected workflow.

## Verification

1. Focused store/service tests: old-store migration/reopen, default false, repeated set/unset, cutoff boundaries, old favorite plain/image/rich, unpin expired, explicit delete/Clear All, source-file preservation и quota accounting.
2. Query/view-model tests: mixed History/Favorites >500 synthetic records, ranked deep matches, rapid mode/query changes, in-flight page after mutation, selected-item removal, failure/retry, concurrent capture/promotion/cleanup.
3. Card/header tests: reuse обновляет marker, selection-only не вызывает full reload, star click/keyboard event не попадает в paste dispatcher.
4. Full SwiftPM и native Xcode checks, universal Release build и git diff --check. Проверка migration failure сохраняет исходную базу и retryable storage state.
5. Installed-app acceptance по критериям выше, затем signed update smoke с сохранением History. Automated evidence и ручные проверки записывать раздельно.

## Implementation report

Реализовано:

- Добавлен backward-compatible `isFavorite` в `HistoryEntry`, display descriptors и serialized metadata; старые metadata и legacy Core Data rows читаются как `false`.
- Core Data schema получила optional favorite marker с default `false`, query index и обновлённый model hash. Все create paths явно инициализируют marker.
- HistoryStore/HistoryService поддерживают mode-aware current/page/ranked-search queries. Favorites используют eligibility `isFavorite == YES`, обычная History — `isFavorite == YES OR capturedAt > cutoff`; cleanup и owned image/rich asset deletion не затрагивают favorites.
- `HistoryViewModel` добавил mode/query/paging generations, idempotent favorite mutation, retryable failure state, snapshot reconciliation, unfavorite removal из Favorites и сохранение marker при `markUsed`.
- Top Notch header и card controls получили accessible star actions; card marker обновляется точечно без полного collection reload. Existing paste, selection, focus и placement paths не менялись.

Automated evidence:

- `swift test --disable-sandbox --skip-update` — 249 tests, 0 failures, 5 skipped из-за недоступного pasteboard в test environment.
- Focused S029 suites покрывают migration/default false, retention и owned assets, deep paging/search >500, mode reset, failure/retry и card marker reconciliation.
- `xcodebuild -project Qipli.xcodeproj -scheme Qipli -configuration Release -destination 'platform=macOS' ... build` — BUILD SUCCEEDED; arm64+x86_64 universal Release app, Sparkle 2.9.6 resolved.
- `git diff --check` прошёл.

Остаточные gates:

- Статус остаётся `needs_verification`: не выполнены installed-app matrix (keyboard/VoiceOver, Light/Dark, Increase Contrast, Reduce Transparency/Motion, notch/non-notch) и signed update smoke с сохранением favorite через relaunch.
- Native build и universal Release подтверждены; automated/build evidence не заменяет installed-app и signed-update checks.
