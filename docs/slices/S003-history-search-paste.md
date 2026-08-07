---
id: S003
title: Поиск и повторная вставка из истории
status: needs_verification
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
- Запись истории не удаляется и не меняет дату после вставки.

## Acceptance criteria

- [ ] `⌘⇧V` из другого приложения открывает одну history panel поверх него, принудительно активирует Qipli и фокусирует пустую строку поиска без дополнительного клика; target app не исполняет собственный `⌘⇧V` до открытия панели.
- [ ] Ввод запроса фильтрует записи по регистронезависимому вхождению подстроки; пустой запрос показывает latest-first список, отсутствие совпадений — отдельное состояние.
- [ ] Up/Down перемещают явный selection в границах результатов; после изменения запроса selection становится первым результатом либо отсутствует.
- [ ] Entry text нельзя выделить или изменить; single-click выбирает ровно эту строку, double-click выбирает её и запускает тот же flow, что `Enter`, а Delete не выбирает и не вставляет запись.
- [ ] `Enter` при выбранной записи закрывает панель, активирует прежнее приложение и отправляет точный Unicode/многострочный текст через стандартную paste-команду.
- [ ] Внутренняя запись выбранного текста не создаёт новую запись истории; вставленная запись остаётся с прежними ID и `capturedAt`, а выбранный текст становится current system pasteboard.
- [ ] `Esc` закрывает панель и возвращает фокус без pasteboard write; повторное открытие показывает актуальную историю.
- [ ] При отсутствии Accessibility вставка недоступна с понятным действием настройки, но поиск и удаление продолжают работать.
- [ ] Если target закрылся/не активируется или dispatch завершается ошибкой, Qipli показывает ошибку, не удаляет запись и позволяет повторить действие.

## Verification

- [x] Unit tests search semantics, selection transitions и delete in filtered results.
- [x] Integration tests history-paste flow с fake pasteboard/application/event adapters.
- [ ] UI tests autofocus, arrows, Enter, Esc, no-results и permission denied.
- [ ] Ручная вставка в TextEdit, браузер и редактор кода, включая Unicode и переводы строк.
- [ ] Ручная проверка read-only/secure field и закрывшегося target без ложного подтверждения.
- [ ] Проверка, что prior app получает фокус и history panel не остаётся key window.

## Definition of Done

- [ ] Все acceptance criteria выполнены.
- [ ] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения записаны в `DECISIONS.md`.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- History panel сохраняет prior frontmost target до показа и сразу order-front; явный `⌘⇧V`/menu action затем вызывает локализованную strong activation request, потому что cooperative `NSApp.activate()` не дал keyboard focus accessory app в ручной проверке. После подтверждённой activation panel повторно становится key и first-show/reuse autofocus ставит пустой search field без click; при исчерпании checks panel остаётся видимой и доступной по click.
- Search выполняется in-memory по исходному тексту через `localizedCaseInsensitiveContains`; selection хранится по `HistoryEntry.id`, стрелки ограничены видимыми результатами, а delete выбирает ближайшую запись.
- History entries отображаются read-only без text selection; single-click планирует ID selection, double-click планирует selection и тот же paste flow, что `Enter`. Delete — отдельная borderless button и не несёт select/paste gesture.
- `Enter` использует immutable text snapshot и отдельный `HistoryPasteExecutor`: final `NSPasteboard.changeCount` регистрируется как self-write сразу после успешной internal write, затем panel закрывается, target активируется и проверяется ограниченным числом main-run-loop turns, только после этого отправляется tagged `⌘V`.
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

- `swift test`: 40 tests, 0 failures.
- Xcode Debug XCTest (`CODE_SIGNING_ALLOWED=NO`): 40 tests, 0 failures.
- Xcode Debug и Release macOS builds (`CODE_SIGNING_ALLOWED=NO`): passed; both arm64 and x86_64 were built.
- `plutil -lint` passed for `Info.plist`, entitlements and `project.pbxproj`; `git diff --check` passed.
- Deterministic coverage includes localized search, selection transitions, filtered delete, exact self-write change registration, permission denial, terminated/unactivatable targets, delayed/exhausted activation, dispatch failure and `Esc` focus restoration seam.
- Active-filter coverage verifies only exact untagged history/stack hotkey keyDown events are consumed; ordinary `⌘V`, extra modifiers, keyUp and Qipli tagged synthetic input pass through.
- Keyboard scheduling change compiles in both build systems; clean console during manual Up/Down/Enter/Esc verification remains required because a dedicated XCUI target is intentionally absent.
- `PanelActivationPresenter` tests cover delayed activation before the active-only key/focus follow-up and prove bounded exhaustion still runs immediate panel presentation while skipping only that follow-up.
- Intent tests lock Up/Down/Enter/Esc routing plus separate single-select, double-click select-and-paste and Delete intents; activation fake expresses the strong user-initiated request.

### Отклонения от плана

- No dedicated XCUI target was added: keyboard and view-model behavior is isolated for deterministic unit/integration coverage. Real panel focus and cross-application paste remain explicit manual verification work.

### Оставшиеся проблемы

Автоматические проверки завершены. Для `done` потребуется ручная проверка, что `⌘⇧V` не выполняет action в target app до показа History, всегда force-activates Qipli и делает History key с autofocus без click после hotkey/reopen, Up/Down/Enter/Esc проходят без SwiftUI console warning `Publishing changes from within view updates`, read-only entries, single-click selection, double-click exact paste и Delete without selection/paste, реальной вставки (TextEdit, browser, code editor; Unicode and multiline), `Esc` focus return, permission-denied UI, read-only/secure field and closed/unactivatable target without false success.
