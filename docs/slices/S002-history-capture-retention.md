---
id: S002
title: Захват, хранение и удаление истории
status: done
depends_on:
  - S001
covers:
  - FR-001
  - FR-002
  - FR-006
  - BR-001
  - BR-002
  - BR-003
  - BR-008
  - BR-009
  - NFR-002
  - NFR-003
  - NFR-008
---

# S002 — Захват, хранение и удаление истории

## Пользовательский результат

Пока Qipli запущен, пользователь видит в базовой панели истории каждое недавнее текстовое копирование и может удалить одну запись или очистить всю локальную историю.

## В scope

- PasteboardMonitor на основе `changeCount`;
- Core Data model/store для `HistoryEntry`;
- exact-text capture, одинаковые события и self-write suppression;
- latest-first базовый список без поиска и Enter-вставки;
- автоматический 30-дневный retention;
- delete one и destructive clear all с подтверждением;
- состояния storage loading/error/empty.

## Вне scope

- поиск, keyboard selection и вставка из истории;
- source-app metadata, изображения, файлы и rich-text хранение;
- отдельная persistence модель Paste Stack;
- secure erase накопителя.

## Предусловия

- S001 завершён; permission и app shell contracts стабильны.
- D-006 перепроверен и принят либо заменён до начала реализации.

## Ожидаемое поведение

- Только внешнее изменение pasteboard с текстовым представлением и хотя бы одним непробельным символом создаёт запись; пустое и whitespace-only содержимое игнорируется.
- Одинаковые строки при разных событиях остаются разными записями.
- Базовая история доступна из status menu/`⌘⇧V`, новая запись показывается первой.
- Записи на retention boundary скрываются до завершения физической cleanup operation.
- Ошибка хранения видна и не создаёт элемент только в UI.

## Состояния интерфейса

- store loading;
- empty history;
- list latest-first;
- delete confirmation для clear all;
- read/write/delete error с retry;
- unsupported non-text или whitespace-only pasteboard change — без записи и без пользовательской ошибки.

## Данные и контракты

- `HistoryEntry(id, text, activityAt)` по текущему контракту `TECHNICAL.md`; Core Data/SQLite key остаётся legacy `capturedAt` для совместимости user stores.
- `activityAt` initially задаётся на capture boundary, а S003 обновляет его только после successful history paste; retention использует контролируемые clock/date зависимости в тестах.
- Self-write registry связан с точным внутренним pasteboard change, а не с дедупликацией по тексту.
- Clear all не очищает system pasteboard и явно сообщает это в confirmation copy.

## Acceptance criteria

- [x] Копирование обычного текста, ссылки, Unicode и многострочного кода из другого приложения создаёт по одной записи с точным строковым содержимым.
- [x] Пустое и whitespace-only содержимое не создаёт запись; ранее сохранённые пустые записи не показываются.
- [x] Два последовательных копирования одинаковой строки создают две записи с разными ID и корректным хронологическим порядком.
- [x] Изменение pasteboard без текстового представления не создаёт запись; внутреннее изменение Qipli также не создаёт запись.
- [x] После перезапуска записи моложе 30 дней сохраняются и показываются newest-first; записи возрастом 30 дней и более не показываются и удаляются обслуживающей операцией.
- [x] Пользователь может удалить отдельную запись; после перезапуска она не возвращается.
- [x] «Очистить всю историю» требует подтверждения, удаляет все записи Qipli и sidecar store data согласно техническому контракту, но не обещает и не выполняет очистку текущего system pasteboard.
- [x] Loading, empty и storage error различимы; при ошибке пользователь может повторить чтение/операцию без потери уже подтверждённых записей.
- [x] Clipboard text и поисковые/preview данные отсутствуют в приложенческих и диагностических логах.

## Verification

- [x] Unit tests на exact text, duplicates, whitespace-only text, unsupported type и self-write suppression.
- [x] Repository tests на create/list/delete/delete-all с временным store.
- [x] Тесты времени на 29d23h59m59s, ровно 30d и старше с injected clock.
- [x] Перезапуск приложения с сохранённым store и повторная проверка списка.
- [x] Ручная проверка копирований из TextEdit, браузера и редактора кода.
- [x] Проверить отсутствие text payload в unified/debug logs тестовой сессии.

## Definition of Done

- [x] Все acceptance criteria выполнены.
- [x] Автоматические и ручные проверки пройдены.
- [x] Приложение собирается без новой регрессии.
- [x] `STATE.md` и frontmatter синхронно обновлены.
- [x] Новые значимые решения записаны в `DECISIONS.md`.
- [x] Implementation report заполнен.

## Implementation report

### Реализовано

- `PasteboardMonitor` polling по `NSPasteboard.changeCount`; принимается только строковое представление, одинаковые события не дедуплицируются, а self-write suppression привязан к точному `changeCount`.
- `HistoryService` с injected clock и 30-day boundary, `CoreDataHistoryStore` с локальным SQLite в Application Support, индексом `capturedAt`, retention cleanup, durable delete и destructive clear-all без обращения к system pasteboard.
- Базовая History UI: loading, empty, list newest-first, delete, clear-all confirmation и error/retry. Ошибка первоначального открытия store повторяется на Retry; runtime retention запускается ежечасно.

### Изменённые файлы

- `Sources/Qipli/Clipboard/PasteboardMonitor.swift`
- `Sources/Qipli/History/HistoryEntry.swift`
- `Sources/Qipli/History/HistoryStore.swift`
- `Sources/Qipli/History/HistoryService.swift`
- `Sources/Qipli/History/HistoryViewModel.swift`
- `Sources/Qipli/App/ApplicationShell.swift`, `Sources/Qipli/UI/PanelController.swift`, `Sources/Qipli/UI/PlaceholderViews.swift`
- `Qipli.xcodeproj/project.pbxproj`
- `Tests/QipliTests/PasteboardMonitorTests.swift`, `Tests/QipliTests/HistoryStoreTests.swift`

### Выполненная проверка

- `swift test` — 20 XCTest passed.
- `xcodebuild -project Qipli.xcodeproj -scheme Qipli -configuration Debug -derivedDataPath /tmp/qipli-s002-build test CODE_SIGNING_ALLOWED=NO` — 20 XCTest passed.
- Xcode Release universal build (`arm64`, `x86_64`) с deployment target macOS 14 и `CODE_SIGNING_ALLOWED=NO` — успешно.
- `plutil -lint Qipli.xcodeproj/project.pbxproj` и `git diff --check` passed.
- Статический privacy scan подтвердил отсутствие app logging и network API; тест launch boundary подтверждает, что содержимое pasteboard до запуска monitor не импортируется.

### Отклонения от плана

- Core Data model создаётся программно вместо отдельного `.xcdatamodeld`; это сохраняет минимальный проект и тот же SQLite/Core Data контракт.
- Пользователь вручную подтвердил clipboard capture, UI, restart persistence, delete/clear и log privacy matrix.

### Оставшиеся проблемы

- Нет блокирующих проблем в границах S002. Следующий срез — S003.
