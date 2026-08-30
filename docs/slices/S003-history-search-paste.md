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
- После успешной internal pasteboard write History исчезает визуально в том же main-run-loop turn; ожидание активации target не показывает reorder, progress state или другой промежуточный UI.
- После отправки paste выбранное значение остаётся current system pasteboard.
- Успешно отправленная history paste-команда обновляет recency exact selected occurrence без duplicate; новый порядок публикуется только при следующем fresh show, поэтому closing panel не перестраивается. Selection, internal clipboard write и failures не меняют recency.
- Каждый свежий hotkey/menu show выбирает first entry и native table синхронно возвращает reusable viewport к top anchor; paste-failure reopen сохраняет выбранную retry row и её viewport context.
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
- SwiftUI владеет shell/search/footer, а view-based `NSTableView` — строками, highlight и viewport. AppKit keyboard bridge применяет Up/Down selection и reveal в одном main-thread вызове.
- PasteExecutor получает immutable text snapshot и target identity; точный final `changeCount` помечается сразу после успешной pasteboard write и до того, как monitor может её обработать.
- Domain `activityAt` initially равен capture time и обновляется только после successfully dispatched tagged `⌘V`; existing SQLite attribute key `capturedAt` остаётся compatibility storage key. Запись сохраняет ID и text, не дублируется, а 30-day retention считается от activity.

## Acceptance criteria

- [x] `⌘⇧V` из другого приложения открывает одну history panel поверх него, принудительно активирует Qipli и фокусирует пустую строку поиска без дополнительного клика; target app не исполняет собственный `⌘⇧V` до открытия панели.
- [x] Ввод запроса фильтрует записи по регистронезависимому вхождению подстроки; пустой запрос показывает latest-first список, отсутствие совпадений — отдельное состояние.
- [x] Up/Down перемещают явный selection в границах результатов и без animation прокручивают long list ровно настолько, чтобы selected row была видима; после изменения запроса selection становится первым результатом либо отсутствует.
- [x] Каждый свежий `⌘⇧V`/menu show после reload возвращает reusable history list к first selected row с top anchor; этот presentation reset не выполняется при reopen после paste failure.
- [x] Entry text нельзя выделить или изменить; single-click выбирает ровно эту строку, double-click выбирает её и запускает тот же flow, что `Enter`, а Delete не выбирает и не вставляет запись.
- [x] `Enter` при выбранной записи сразу визуально скрывает панель, активирует прежнее приложение и отправляет точный Unicode/многострочный текст через стандартную paste-команду; пользователь не видит ожидание target activation или перестройку списка.
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
- View-based `NSTableView` переиспользует native row views по stable entry UUID. Up/Down через weak AppKit bridge в том же вызове меняют highlight и вызывают `scrollRowToVisible`, поэтому selection не может уйти за viewport в ожидании SwiftUI render.
- Fresh `showHistory` после `makeKeyAndOrderFront` выдаёт отдельный presentation viewport-reset request. Native table синхронно выбирает first visible entry и возвращает clip view к top; signal не связан с search focus и не выполняется в paste-failure reopen.
- History entries отображаются read-only без text selection; native single-click сразу выбирает ID, double-click выбирает exact row и запускает тот же paste flow, что `Enter`. Delete остаётся отдельной row button и не несёт select/paste gesture.
- `Enter` использует immutable text snapshot и отдельный `HistoryPasteExecutor`: final `NSPasteboard.changeCount` регистрируется как self-write сразу после successful internal write. Затем panel синхронно становится полностью прозрачной и игнорирует mouse events, но остаётся ordered/key для cooperative macOS 14 activation handoff. Injectable 1-second deadline с 50 ms main-run-loop retries теперь выполняется невидимо; active target вызывает `orderOut` непосредственно перед tagged `⌘V`. Immediate rejection, exhausted activation и rejected dispatch восстанавливают обычную presentation и показывают retryable error без повторной write/dispatch. Layout-changing `Pasting…` state удалён.
- В `.success` branch `PanelController` после successful tagged `⌘V` вызывает non-fatal `markUsed` только для selected ID: domain `activityAt` (legacy Core Data key `capturedAt`) и cached order обновляются сразу, но visible snapshot публикуется только при следующем fresh presentation. Closing panel вообще не получает reorder. Ошибка promotion не отменяет уже отправленную paste-команду, не создаёт duplicate и не вызывает повторный dispatch.
- `Esc` закрывает History и пытается вернуть captured target без clipboard/event side effects. Permission missing, unavailable target, write и dispatch errors остаются видимыми и retryable; history entry не изменяется.
- Нормальный `⌘V` не менялся; synthetic event остаётся tagged и игнорируется global listener.
- Active event tap потребляет только exact untagged `⌘⇧V`/`⌘⇧C` keyDown, поэтому исходный hotkey не успевает выполнить действие target app.
- Up/Down и Enter исполняют selection/reveal или paste start синхронно в AppKit key handler. Только Escape и delete сохраняют deferred boundary для безопасного изменения SwiftUI-owned window/state paths.

### Изменённые файлы

- `Sources/Qipli/Input/HistoryPasteExecutor.swift`
- `Sources/Qipli/History/HistoryViewModel.swift`
- `Sources/Qipli/UI/PanelController.swift`
- `Sources/Qipli/UI/PlaceholderViews.swift`
- `Sources/Qipli/UI/HistoryTableView.swift`
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
- Deterministic coverage includes localized search, selection transitions, filtered delete, exact self-write change registration, `write → conceal → activate → close → dispatch` order, no conceal before successful write, immediate rejected activation without close, delayed/exhausted target activation without duplicate dispatch, durable exact-occurrence activity promotion/restart, capture-or-use retention and promotion-storage failure without false paste failure.
- Active-filter coverage verifies only exact untagged history/stack hotkey keyDown events are consumed; ordinary `⌘V`, extra modifiers, keyUp and Qipli tagged synthetic input pass through.
- Deterministic view-model coverage proves the fresh presentation viewport request is independent from search focus; real reusable viewport behavior remains manual because a dedicated XCUI target is intentionally absent.
- `PanelActivationPresenter` tests cover delayed activation before the active-only key/focus follow-up and prove bounded exhaustion still runs immediate panel presentation while skipping only that follow-up.
- Intent tests lock Up/Down/Enter/Esc routing plus separate single-select, double-click select-and-paste and Delete intents; activation fake expresses the strong user-initiated request.

### Отклонения от плана

- No dedicated XCUI target was added: keyboard and view-model behavior is isolated for deterministic unit/integration coverage. Real panel focus and cross-application paste remain explicit manual verification work.

### Оставшиеся проблемы

Regression 2026-08-30 исправлен и принят в ручном Xcode smoke: History больше не показывает target-activation wait, `Pasting…` layout shift или selection jump; native table синхронно применяет highlight и viewport для rapid arrows. Временная payload-free trace после проверки полностью удалена.
