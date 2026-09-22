---
id: S036
title: Пять последних записей History в меню
depends_on:
  - S023
  - S024
  - S025
  - S031
covers:
  - FR-051
  - FR-052
  - BR-038
  - NFR-036
---

# S036: Пять последних записей History в меню

## Пользовательский результат

Кликнуть по иконке Qipli в строке меню, увидеть пять последних записей сразу под History и выбрать одну для вставки в исходное приложение. Отдельно открывать панель History для этого не требуется.

Запрос и действие по клику подтверждены пользователем 2026-09-21. Правила отображения и ограничение при active Stack ниже являются уточнениями планирования. Контракты: FR-051/FR-052/BR-038/NFR-036 в [PRODUCT.md](../PRODUCT.md), раздел S036 в [TECHNICAL.md](../TECHNICAL.md), D-047 в [DECISIONS.md](../DECISIONS.md). Статус находится только в [STATE.md](../STATE.md).

## Состав меню

```text
History
<последняя запись>
<вторая запись>
<третья запись>
<четвёртая запись>
<пятая запись>
────────────
Start Paste Stack / Cancel Paste Stack
────────────
Check for Updates…
Settings…
────────────
Quit Qipli
```

- Показывать до пяти первых renderable occurrences общей History в порядке activityAt DESC, id DESC. Повторное использование продвигает запись по обычному History contract. Search/Favorites панели не меняют набор. Избранное не закрепляется вверху отдельно.
- При 1–4 записях показывать фактическое число. При пустой History не добавлять пустые строки и дополнительный separator. Loading и ошибка чтения не изображают пустой store.
- Каждый пункт имеет bounded single-line preview и локальный значок типа. Rich text показывает plain preview, image и reference types используют локальное название/тип/количество. Переносы и обрезка не меняют payload. Несколько items одной occurrence остаются одним пунктом.
- History открывает прежнюю панель. Paste Stack, update/settings/quit и их enabled state сохраняются.

## Вставка и состояния

- Один клик или клавиатурный выбор вставляет полное сохранённое содержимое через текущий typed History path. Default rich paste сохраняет форматирование. URL, image, file/video reference следуют существующей поддержке History.
- Target фиксируется при открытии меню до потери исходного контекста. Native menu закрывается перед handoff. Нет промежуточного показа History на успешном пути.
- Один выбор создаёт не более одной transaction. Закрытие меню без выбора не пишет clipboard, не меняет activity и не вставляет данные.
- Невалидный target, отсутствие Accessibility, missing/deleted/corrupt payload дают понятное сообщение без отправки в случайное приложение. Неуспех не продвигает запись. Повтор требует явного действия пользователя.
- Меню сохраняет UUID выбранной строки при фоновых изменениях. Следующее открытие отражает завершённые capture, paste promotion, delete, clear и retention; pending capture обновляет projection после drain без подмены выбранного пункта.
- При active Stack предложено оставлять previews видимыми, отключать их выбор и пояснять необходимость завершить Stack. Не отменять Stack автоматически и не расходовать его очередь. Это ограничение первой поставки, а не подтверждённое пользователем отдельное требование.

## Вне scope

Настройка числа пунктов, подменю, большие карточки/миниатюры, поиск в меню, управление избранным/удалением, новые shortcuts, plain-only modifier action, новые форматы capture, миграция storage и изменение обычного ⌘V. S035 и отдельное окно S028 не требуются.

## Acceptance criteria

- [ ] Для 0, 1, 4, 5 и 6+ записей верны число, порядок, место блока и separators; остальные команды сохраняют действие и состояние.
- [x] Поиск, Favorites и scroll панели не меняют последние пять общей History. Совпадающие previews сохраняют разные UUID.
- [ ] Capture, promotion, delete, clear и retention обновляют следующий snapshot. Async completion старого открытия не меняет новое меню; выбор не перескакивает на другой UUID.
- [ ] Text, multiline/long text, rich text, URL, image и file/video reference вставляются в исходное приложение через существующий typed путь без показа History при успехе.
- [ ] Payload остаётся полным; rich formatting и ordered multi-item occurrence сохраняются. Нет новых History/Stack duplicates от self-write.
- [ ] Menu dismiss без выбора ничего не вставляет. Rapid/repeated selection не создаёт второй dispatch. Missing target, permission и payload дают безопасный отказ и видимое сообщение.
- [ ] Active Stack не меняет order, used-state или clipboard из-за выбора disabled строки. Обычный ⌘V вне Stack сохраняется.
- [ ] Native keyboard navigation и VoiceOver позволяют различить пункты, типы и unavailable state; длинные previews не вытесняют остальные команды за пределы доступного меню.
- [x] Открытие не materialize-ит image/rich payload и не читает весь store на main actor; пользовательские содержимое, URL и пути отсутствуют в logs и fixtures.

## Verification

1. Unit tests projection: число/сортировка, filter independence, UUID identity, bounded preview для typed и multi-item данных, empty/loading/error.
2. Coordinator tests через fake adapters: исходный target, закрытие меню до dispatch, общий transaction guard, permission/unavailable/deleted IDs, self-write, activity promotion и active Stack. Проверить stale async completions и mutation при открытом меню.
3. Installed-app matrix на synthetic данных: TextEdit plain/rich, браузер, image-capable target, Finder file reference; выбор мышью и клавиатурой, Escape, смена/закрытие target, denied Accessibility, active Stack, VoiceOver, Light/Dark и длинные подписи. Факт принятия payload проверить в target отдельно от успешного dispatch.
4. Focused tests, полный SwiftPM suite, development-signed Debug build и diff check после реализации. Существующие signing/update gates остаются частью release delivery и не считаются пройденными этим планом.

## Implementation report

Реализация 2026-09-22:

- `HistoryService.recentDescriptors()` читает display metadata страницами по пять через существующий store. `HistoryViewModel.recentState` обновляется после capture, promotion, delete, clear, reload/retention и при открытии после capture drain. Search/Favorites не участвуют. Generation guard отбрасывает устаревшие refresh completions.
- `RecentHistoryMenuController` в `ApplicationShell.swift` фиксирует target и набор UUID на открытие. Завершение фонового refresh меняет следующий snapshot, не текущие строки. Loading/error имеют отдельные disabled строки; пустой snapshot не добавляет separator.
- Native rows используют локальные type symbols, single-line preview до 64 символов плюс ellipsis/количество, accessibility label и disabled Stack explanation. Payload и thumbnails при построении меню не читаются.
- Выбор резервируется один раз; `cancelTracking()` и следующий main-queue turn отделяют закрытие меню от вставки. `PanelController.pasteRecentHistoryEntry` использует прежние validation, typed executor, self-write registration, tagged dispatch, promotion и failure UI. Общая reservation сохраняется во время async entry lookup; отдельный request UUID отвергает completion отменённого запроса, даже при повторном выборе той же записи.
- S035 и остальные исходные незакоммиченные изменения сохранены. Схема, permissions и event tap в рамках S036 не менялись.

Проверки:

- Новые `RecentHistoryMenuTests`: 8/8. Количество/расположение/separators, bounded typed labels, одинаковые previews с разными UUID, immutable snapshot, повторный выбор, dismiss, late close/new opening, active/late-start Stack, loading/error/empty, filter independence, capture/promotion/delete/clear, retention и UUID tie-break.
- Полный SwiftPM suite: 279 tests, 0 failures, 0 skipped. Существующие executor tests покрывают typed payload, self-write, permission, target activation, dispatch failure и concurrent paste guard.
- Итоговый прогон выполнен на копии Sources/Tests/Package.swift в `/private/tmp/qipli-s036-verify` с отдельным scratch cache. Обычный checkout блокировался на чтении Git config, затем module cache; содержимое Swift inputs сверяется отдельно.
- Development-signed universal Debug build прошёл: arm64 + x86_64, `com.qipli.app.dev`, Apple Development. `codesign --verify --deep --strict` прошёл вне sandbox с доступом к trust services. 50 Swift/package/project/version inputs во временной копии совпадают с checkout по SHA-256. App: `/private/tmp/qipli-s036-final-build/Build/Products/Debug/Qipli Dev.app`.
- `git diff --check` прошёл через временную копию Git index с read-only доступом к исходным objects; исходный Git config не изменялся.

Осталось для приёмки: установленная matrix из Verification 3, включая факт принятия rich/image/reference payload целевыми приложениями, реальный порядок native menu close/handoff, VoiceOver, Light/Dark и permission denial. Unit tests моделируют menu delegate/action ordering; они не заменяют runtime acceptance. Статус остаётся `needs_verification`.
