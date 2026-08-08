---
id: S007
title: Повторная активация и отмена
status: done
depends_on:
  - S006
covers:
  - FR-013
  - FR-015
  - BR-004
  - BR-006
  - NFR-005
  - NFR-006
  - NFR-008
---

# S007 — Повторная активация и отмена

## Пользовательский результат

Если значение было вставлено не туда, пользователь делает любой used-элемент следующим и повторяет его, либо безопасно отменяет незавершённый стек, не теряя историю.

## В scope

- действие Reactivate на любом used occurrence;
- exact `⌘⇧Z` Reactivate Previous для последнего successfully dispatched occurrence;
- одноразовый приоритет reactivated occurrence и возврат к прежнему traversal;
- повторные reactivation/paste циклы;
- `Esc` и close control на collecting/partially-used/reactivated session;
- cleanup event interception и сохранность общей истории.

## Вне scope

- undo в приложении назначения;
- автоматическое определение неправильного поля;
- восстановление завершённого/закрытого стека;
- сохранённые stack templates.

## Предусловия

- S006 завершён; used-state означает отправленную команду по D-011.

## Ожидаемое поведение

- Reactivation меняет только выбранный occurrence и next priority; остальные used/pending состояния не сбрасываются.
- Exact untagged `⌘⇧Z` не вставляет сразу: он идемпотентно выбирает только последний successfully dispatched occurrence, а следующий ordinary `⌘V` выполняет повторную вставку. До first dispatch/вне active Stack shortcut остаётся system Redo.
- После повторной вставки traversal продолжает тот элемент, который был next до reactivation.
- Можно реактивировать один и тот же элемент повторно, пока session открыта.
- Cancel немедленно прекращает stack-controlled paste, но не меняет history records.

## Состояния интерфейса

- used item with Reactivate action;
- reactivated-next marker;
- reactivated item processing/used again;
- immediate cancel без confirmation dialog;
- canceled/closed.

## Данные и контракты

- State machine хранит не более одного `reactivationPriority` одновременно.
- State machine хранит exact UUID last successfully dispatched occurrence только для Reactivate Previous; успешная reactivation paste обновляет этот UUID как обычная успешная отправка.
- Выбор другого used occurrence заменяет приоритет, не переводя предыдущий used в pending.
- После успешного повторного dispatch приоритет очищается; базовый traversal cursor не перескакивает.
- Cancel идемпотентен: повторный Esc/close после завершения ничего не меняет.

## Acceptance criteria

- [x] Каждый used occurrence в открытой панели имеет доступное действие Reactivate; pending occurrence не предлагает это действие.
- [x] Reactivate делает выбранный occurrence следующим и визуально отличает его, не изменяя состояния остальных used/pending элементов.
- [x] Следующий `⌘V` отправляет reactivated text ровно один раз; после этого occurrence снова used, а прежний next pending снова становится следующим.
- [x] Другой used occurrence можно выбрать до paste; он заменяет одноразовый приоритет без появления двух next items.
- [x] Один и тот же occurrence можно повторно активировать несколько раз в рамках открытой session без создания новых history records.
- [x] Exact `⌘⇧Z` при active Stack/reactivation eligibility назначает последний successfully dispatched occurrence следующим, не dispatch-ит paste, заменяет manual priority и повторяется идемпотентно; во всех иных состояниях проходит как system Redo.
- [x] Глобальный `Esc` из приложения-источника/назначения и close control завершают пустую, collecting, partially-used или reactivated session, скрывают panel и полностью отключают stack interception.
- [x] После cancel обычный `⌘V` снова системный, а все внешние копирования из отменённого стека доступны в общей истории с исходными text/date.
- [x] После auto-finish из S006 прежний стек нельзя реактивировать; повторное значение берётся через общую историю, новый `⌘⇧C` начинает пустую session.

## Verification

- [x] Unit tests reactivation priority, replacement, direct/reverse cursor resume, repeated reactivation и reactivation rollback/retry.
- [x] Unit tests Reactivate Previous admission, exact modifiers/marker/keyUp pass-through, idempotency/replacement и last-successful update.
- [x] Unit tests cancel из empty/collecting/partial/priority/processing states, idempotency и stale deferred production.
- [x] Integration test: reactivated paste uses exact self-write suppression and does not add history/Stack duplicate.
- [x] UI intent tests Reactivate used-only UUID/deferred seam, priority marker/accessibility strings и no redundant priority publication.
- [x] Ручной сценарий «два значения попали в одно поле»: reactivate первого/второго и продолжить traversal.
- [x] После cancel/auto-finish проверить системный `⌘V` и history recovery.

## Definition of Done

- [x] Все acceptance criteria выполнены.
- [x] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения записаны в `DECISIONS.md`.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

Добавлены UUID reactivation priority и reservation origin. Успешная tagged dispatch возвращает reactivated occurrence в used, clears only its still-current priority and resumes unchanged traversal cursor; failure returns traversal work to pending but reactivation to used with retryable priority. Auto-finish now requires no priority, so a reactivation in its deferred boundary retains the open session. Cancel remains immediate/idempotent and invalidates stale executor work.

Exact untagged `⌘⇧Z` теперь называется Reactivate Previous: active Stack с successful dispatch synchronously assigns the last dispatched UUID one-shot priority, posts no paste, then publishes through the existing common-run-loop boundary. It is passed through as system Redo for inactive/pre-success/tagged/keyUp/other-modifier inputs. It does not activate Qipli or the target app.

### Изменённые файлы

`Sources/Qipli/PasteStack/StackSession.swift`; `Sources/Qipli/Input/GlobalInput.swift`; `Sources/Qipli/Input/CGEventTapAdapter.swift`; `Sources/Qipli/App/ApplicationShell.swift`; `Sources/Qipli/UI/PlaceholderViews.swift`; `Tests/QipliTests/PasteStackTests.swift`; `Tests/QipliTests/InputCoordinatorTests.swift`; `docs/PRODUCT.md`; `docs/TECHNICAL.md`; `docs/DECISIONS.md`; `docs/STATE.md`.

### Выполненная проверка

2026-08-08: SwiftPM `swift test` — 91 tests, 0 failures. Xcode Debug XCTest — 91 tests, 0 failures. Universal Release `arm64+x86_64` build and `lipo -info` passed. `Info.plist` lint and `git diff --check` passed. Production-source scan found no logging, network client/endpoint or telemetry APIs; the only URL match is an existing synthetic test fixture and plist DTD.

### Отклонения от плана

`⌘⇧Z` was added after the original slice plan at user request. It is explicitly limited to reactivation priority rather than immediate paste or target-app undo (D-015).

### Оставшиеся проблемы

Нет. Пользователь подтвердил полную manual macOS matrix: real Accessibility event tap, source-app focus, Reactivate/Reactivate Previous marker and normal system Redo pass-through, direct/reverse cursor recovery, failure retry, Escape/red-close/Cancel/menu cancellation, post-cancel ordinary `⌘V`, auto-finish boundary and clean console без List layout recursion.
