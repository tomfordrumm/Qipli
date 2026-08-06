---
id: S002
title: Захват, хранение и удаление истории
status: planned
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

- Только внешнее изменение pasteboard с текстовым представлением создаёт запись.
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
- unsupported non-text pasteboard change — без записи и без пользовательской ошибки.

## Данные и контракты

- `HistoryEntry(id, text, capturedAt)` по контракту `TECHNICAL.md`.
- `capturedAt` задаётся один раз на capture boundary; retention использует контролируемые clock/date зависимости в тестах.
- Self-write registry связан с точным внутренним pasteboard change, а не с дедупликацией по тексту.
- Clear all не очищает system pasteboard и явно сообщает это в confirmation copy.

## Acceptance criteria

- [ ] Копирование обычного текста, ссылки, Unicode и многострочного кода из другого приложения создаёт по одной записи с точным строковым содержимым.
- [ ] Два последовательных копирования одинаковой строки создают две записи с разными ID и корректным хронологическим порядком.
- [ ] Изменение pasteboard без текстового представления не создаёт запись; внутреннее изменение Qipli также не создаёт запись.
- [ ] После перезапуска записи моложе 30 дней сохраняются и показываются newest-first; записи возрастом 30 дней и более не показываются и удаляются обслуживающей операцией.
- [ ] Пользователь может удалить отдельную запись; после перезапуска она не возвращается.
- [ ] «Очистить всю историю» требует подтверждения, удаляет все записи Qipli и sidecar store data согласно техническому контракту, но не обещает и не выполняет очистку текущего system pasteboard.
- [ ] Loading, empty и storage error различимы; при ошибке пользователь может повторить чтение/операцию без потери уже подтверждённых записей.
- [ ] Clipboard text и поисковые/preview данные отсутствуют в приложенческих и диагностических логах.

## Verification

- [ ] Unit tests на exact text, duplicates, unsupported type и self-write suppression.
- [ ] Repository tests на create/list/delete/delete-all с временным store.
- [ ] Тесты времени на 29d23h59m59s, ровно 30d и старше с injected clock.
- [ ] Перезапуск приложения с сохранённым store и повторная проверка списка.
- [ ] Ручная проверка копирований из TextEdit, браузера и редактора кода.
- [ ] Проверить отсутствие text payload в unified/debug logs тестовой сессии.

## Definition of Done

- [ ] Все acceptance criteria выполнены.
- [ ] Автоматические и ручные проверки пройдены.
- [ ] Приложение собирается без новой регрессии.
- [ ] `STATE.md` и frontmatter синхронно обновлены.
- [ ] Новые значимые решения записаны в `DECISIONS.md`.
- [ ] Implementation report заполнен.

## Implementation report

### Реализовано

Не начато.

### Изменённые файлы

Не начато.

### Выполненная проверка

Не начато.

### Отклонения от плана

Нет.

### Оставшиеся проблемы

Зависит от S001.
