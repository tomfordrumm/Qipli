---
id: S003
title: Поиск и повторная вставка из истории
status: done
depends_on:
  - S002
covers:
  - FR-003
  - FR-004
  - FR-005
  - FR-006
  - FR-016
  - BR-007
  - BR-008
  - BR-010
  - NFR-005
  - NFR-006
  - NFR-008
---

# S003 — Поиск и повторная вставка из истории

## Пользовательский результат

Пользователь открывает историю из любого обычного приложения, быстро находит запись с клавиатуры и вставляет точный текст в ранее активное поле по `Enter`.

## В scope

- завершённый history panel и сохранение prior frontmost app;
- autofocus поиска, регистронезависимый substring search;
- arrows/selection/Enter/Esc;
- history paste flow через internal pasteboard write и synthetic `⌘V`;
- delete one/clear all из полного и фильтрованного списка;
- permission denied и target activation failure.

## Вне scope

- fuzzy search, source-app filters и pin/favorites;
- восстановление прежнего system pasteboard после вставки;
- гарантированная вставка в secure, read-only или custom fields;
- Paste Stack.

## Предусловия

- S002 завершён и history repository contract стабилен.
- S001 подтвердил permission, event и focus подход на macOS 14.

## Ожидаемое поведение

- До показа панели запоминается приложение назначения.
- Поиск не изменяет сохранённый текст и обновляет selection предсказуемо.
- `Enter` доступен только при выбранном результате и готовом Accessibility.
- После отправки paste выбранное значение остаётся current system pasteboard.
- Успешно отправленная history paste-команда поднимает exact selected occurrence в начало списка без duplicate; selection, internal clipboard write и failures не меняют recency.
- Каждый свежий hotkey/menu show после reload выбирает first entry и non-animated возвращает reusable list viewport к нему с top anchor; paste-failure reopen сохраняет выбранную retry row и её viewport context.
- `Esc` закрывает history panel без выбора и без изменения pasteboard.
- Текст entries read-only: один click выбирает запись, double-click выбирает эту же запись и запускает тот же paste flow, что и `Enter`; Delete остаётся отдельным действием без paste.

## Состояния интерфейса

- initial list;
- active query + results;
- no results;
- selected row;
- permission missing: list/search/delete доступны, paste disabled;
- target unavailable/paste dispatch error;
- empty history.

## Данные и контракты

- Поиск выполняется по исходному `text`, регистронезависимо и с системными locale rules.
- View model хранит ID selection, а не позицию; после удаления выбирается ближайшая видимая запись.
- PasteExecutor получает immutable text snapshot и target identity; точный final `changeCount` помечается сразу после успешной pasteboard write и до того, как monitor может её обработать.
- Domain `activityAt` initially равен capture time и обновляется только после successfully dispatched tagged `⌘V`; existing SQLite attribute key `capturedAt` остаётся compatibility storage key. Запись сохраняет ID и text, не дублируется, а 30-day retention считается от activity.

## Acceptance criteria

- [x] `⌘⇧V` из другого приложения открывает одну history panel поверх него, принудительно активирует Qipli и фокусирует пустую строку поиска без дополнительного клика; target app не исполняет собственный `⌘⇧V` до открытия панели.
- [x] Ввод запроса фильтрует записи по регистронезависимому вхождению подстроки; пустой запрос показывает latest-first список, отсутствие совпадений — отдельное состояние.
- [x] Up/Down перемещают явный selection в границах результатов и без animation прокручивают long list ровно настолько, чтобы selected row была видима; после изменения запроса selection становится первым результатом либо отсутствует.
- [x] Каждый свежий `⌘⇧V`/menu show после reload возвращает reusable history list к first selected row с top anchor; этот presentation reset не выполняется при reopen после paste failure.
- [x] Entry text нельзя выделить или изменить; single-click выбирает ровно эту строку, double-click выбирает её и запускает тот же flow, что `Enter`, а Delete не выбирает и не вставляет запись.
- [x] `Enter` при выбранной записи закрывает панель, активирует прежнее приложение и отправляет точный Unicode/многострочный текст через стандартную paste-команду.
- [x] Только successful tagged `⌘V` поднимает exact selected occurrence на top и durably обновляет её activity timestamp; ID/text не меняются, duplicate не создаётся, а selected text становится current system pasteboard. Selection, internal write, target activation failure и dispatch failure не меняют recency.
- [x] `Esc` закрывает панель и возвращает фокус без pasteboard write; повторное открытие показывает актуальную историю.
- [x] При отсутствии Accessibility вставка недоступна с понятным действием настройки, но поиск и удаление продолжают работать.
- [x] Если target закрылся/не активируется или dispatch завершается ошибкой, Qipli показывает ошибку, не удаляет запись и позволяет повторить действие.

## Verification

- [x] Unit tests search semantics, selection transitions и delete in filtered results.
- [x] Integration tests history-paste flow с fake pasteboard/application/event adapters.
- [x] Ручная UI-проверка autofocus, arrows, Enter, Esc, no-results и permission denied.
- [x] Ручная вставка в TextEdit, браузер и редактор кода, включая Unicode и переводы строк.
- [x] Ручная проверка read-only/secure field и закрывшегося target без ложного подтверждения.
- [x] Проверка, что prior app получает фокус и history panel не остаётся key window.

## Definition of Done

- [x] Все acceptance criteria выполнены.
- [x] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения записаны в `DECISIONS.md`.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- History panel сохраняет prior frontmost target до показа и сразу order-front; явный `⌘⇧V`/menu action затем вызывает локализованную strong activation request, потому что cooperative `NSApp.activate()` не дал keyboard focus accessory app в ручной проверке. После подтверждённой activation panel повторно становится key и first-show/reuse autofocus ставит пустой search field без click; при исчерпании checks panel остаётся видимой и доступной по click.
- Search выполняется in-memory по исходному тексту через `localizedCaseInsensitiveContains`; selection хранится по `HistoryEntry.id`, стрелки ограничены видимыми результатами, а delete выбирает ближайшую запись.
- List обёрнут в `ScrollViewReader`: stable entry UUID используются как scroll IDs, а любые ID-based selection transitions (arrows, query/reset, delete или row click) deferred non-animated `scrollTo` без fixed anchor, поэтому already-visible row не центрируется.
- Fresh `showHistory` после `makeKeyAndOrderFront` выдаёт отдельный presentation viewport-reset request. `ScrollViewReader` один раз принимает его на следующем main-run-loop turn и non-animated scrolls first visible entry to `.top`; это не связано с search-focus signal и не выполняется в paste-failure reopen.
- History entries отображаются read-only без text selection; single-click планирует ID selection, double-click планирует selection и тот же paste flow, что `Enter`. Delete — отдельная borderless button и не несёт select/paste gesture.
- `Enter` использует immutable text snapshot и отдельный `HistoryPasteExecutor`: final `NSPasteboard.changeCount` регистрируется как self-write сразу после successful internal write. Пока Qipli active, target activation/yield request принимается до `orderOut`; immediate rejection оставляет History visible с retryable error. Panel остаётся visible в течение injectable 1-second deadline с 50 ms main-run-loop retries; только active target закрывает panel непосредственно перед tagged `⌘V`. Exhausted activation оставляет error in place, а rejected dispatch возвращает History без повторной write/dispatch.
- В `.success` branch `PanelController` после successful tagged `⌘V` вызывает non-fatal `markUsed` только для selected ID: domain `activityAt` (legacy Core Data key `capturedAt`) обновляется и exact occurrence поднимается при следующем History reload. Ошибка promotion не отменяет уже отправленную paste-команду, не создаёт duplicate и не вызывает повторный dispatch.
- `Esc` закрывает History и пытается вернуть captured target без clipboard/event side effects. Permission missing, unavailable target, write и dispatch errors остаются видимыми и retryable; history entry не изменяется.
- Нормальный `⌘V` не менялся; synthetic event остаётся tagged и игнорируется global listener.
- Active event tap потребляет только exact untagged `⌘⇧V`/`⌘⇧C` keyDown, поэтому исходный hotkey не успевает выполнить действие target app.
- Up/Down/Enter/Esc подтверждаются синхронно, но их state/window effects переносятся на следующий main run-loop turn, чтобы `@Published` не публиковался внутри SwiftUI view update.

### Изменённые файлы

- `Sources/Qipli/Input/HistoryPasteExecutor.swift`
- `Sources/Qipli/History/HistoryViewModel.swift`
- `Sources/Qipli/UI/PanelController.swift`
- `Sources/Qipli/UI/PlaceholderViews.swift`
- `Sources/Qipli/App/ApplicationShell.swift`
- `Sources/Qipli/Input/CGEventTapAdapter.swift`
- `Tests/QipliTests/HistorySearchPasteTests.swift`
- `Qipli.xcodeproj/project.pbxproj`
- `docs/DECISIONS.md`
- `docs/STATE.md`
- `docs/slices/S003-history-search-paste.md`

### Выполненная проверка

- `swift test`: 45 tests, 0 failures.
- Xcode Debug XCTest (`CODE_SIGNING_ALLOWED=NO`): 45 tests, 0 failures.
- Xcode Debug и Release macOS builds (`CODE_SIGNING_ALLOWED=NO`): passed; both arm64 and x86_64 were built.
- `plutil -lint` passed for `Info.plist`, entitlements and `project.pbxproj`; `git diff --check` passed.
- Deterministic coverage includes localized search, selection transitions, filtered delete, exact self-write change registration, activation-before-close trace, immediate rejected activation without close, delayed/exhausted target activation without duplicate dispatch, durable exact-occurrence activity promotion/restart, capture-or-use retention and promotion-storage failure without false paste failure.
- Active-filter coverage verifies only exact untagged history/stack hotkey keyDown events are consumed; ordinary `⌘V`, extra modifiers, keyUp and Qipli tagged synthetic input pass through.
- Deterministic view-model coverage proves the fresh presentation viewport request is independent from search focus; real reusable viewport behavior remains manual because a dedicated XCUI target is intentionally absent.
- `PanelActivationPresenter` tests cover delayed activation before the active-only key/focus follow-up and prove bounded exhaustion still runs immediate panel presentation while skipping only that follow-up.
- Intent tests lock Up/Down/Enter/Esc routing plus separate single-select, double-click select-and-paste and Delete intents; activation fake expresses the strong user-initiated request.

### Отклонения от плана

- No dedicated XCUI target was added: keyboard and view-model behavior is isolated for deterministic unit/integration coverage. Real panel focus and cross-application paste remain explicit manual verification work.

### Оставшиеся проблемы

Нет известных проблем в границах S003. Пользователь подтвердил полную ручную матрицу реального UI, focus/paste, keyboard navigation, recency и reusable-list viewport 2026-08-08.
