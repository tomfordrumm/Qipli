---
id: S003
title: Поиск и повторная вставка из истории
status: planned
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
- PasteExecutor получает immutable text snapshot и target identity; self-write помечается до pasteboard write.
- Запись истории не удаляется и не меняет дату после вставки.

## Acceptance criteria

- [ ] `⌘⇧V` из другого приложения открывает одну history panel поверх него и фокусирует пустую строку поиска без дополнительного клика.
- [ ] Ввод запроса фильтрует записи по регистронезависимому вхождению подстроки; пустой запрос показывает latest-first список, отсутствие совпадений — отдельное состояние.
- [ ] Up/Down перемещают явный selection в границах результатов; после изменения запроса selection становится первым результатом либо отсутствует.
- [ ] `Enter` при выбранной записи закрывает панель, активирует прежнее приложение и отправляет точный Unicode/многострочный текст через стандартную paste-команду.
- [ ] Внутренняя запись выбранного текста не создаёт новую запись истории; вставленная запись остаётся с прежними ID и `capturedAt`, а выбранный текст становится current system pasteboard.
- [ ] `Esc` закрывает панель и возвращает фокус без pasteboard write; повторное открытие показывает актуальную историю.
- [ ] При отсутствии Accessibility вставка недоступна с понятным действием настройки, но поиск и удаление продолжают работать.
- [ ] Если target закрылся/не активируется или dispatch завершается ошибкой, Qipli показывает ошибку, не удаляет запись и позволяет повторить действие.

## Verification

- [ ] Unit tests search semantics, selection transitions и delete in filtered results.
- [ ] Integration tests history-paste flow с fake pasteboard/application/event adapters.
- [ ] UI tests autofocus, arrows, Enter, Esc, no-results и permission denied.
- [ ] Ручная вставка в TextEdit, браузер и редактор кода, включая Unicode и переводы строк.
- [ ] Ручная проверка read-only/secure field и закрывшегося target без ложного подтверждения.
- [ ] Проверка, что prior app получает фокус и history panel не остаётся key window.

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

Зависит от S002.
