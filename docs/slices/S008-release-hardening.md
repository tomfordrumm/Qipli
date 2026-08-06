---
id: S008
title: Приватность и релиз через GitHub
status: planned
depends_on:
  - S003
  - S007
covers:
  - FR-006
  - NFR-001
  - NFR-002
  - NFR-003
  - NFR-004
  - NFR-007
---

# S008 — Приватность и релиз через GitHub

## Пользовательский результат

Пользователь загружает с GitHub подписанный и notarized Qipli, устанавливает его на чистую macOS 14, понимает разрешения и локальное хранение и завершает оба основных сценария без внешней передачи содержимого.

## В scope

- финальный privacy/entitlements/logging audit;
- release configuration, Developer ID signing, Hardened Runtime;
- archive, notarization, stapling, packaging и checksum;
- clean-machine install/upgrade/uninstall notes;
- GitHub release notes с системными требованиями и Accessibility onboarding;
- проверка delete-one/delete-all, retention и отсутствия продуктовой сети;
- подтверждение архитектур бинарника и supported matrix.

## Вне scope

- Mac App Store, auto-update service и installer daemon;
- telemetry/remote crash reports;
- launch at login;
- новые функции истории или Paste Stack.

## Предусловия

- S003 и S007 завершены, все MVP flows доступны.
- Есть Apple Developer Program membership, Developer ID Application certificate и notarization credentials. Если нет — срез остаётся `planned`/становится `blocked`, но локальная разработка не откатывается.
- Apple platform sources из `TECHNICAL.md` перепроверены на дату релиза.

## Ожидаемое поведение

- Gatekeeper принимает artifact без обходных инструкций.
- Первый запуск до чтения чувствительного текста показывает понятное локальное privacy explanation и permission path.
- Приложение не делает runtime network requests и не имеет неиспользуемых entitlements.
- Обновление не теряет допустимую history и корректно перепроверяет Accessibility после изменения подписи/пути.

## Состояния интерфейса

- first run privacy notice;
- permission not granted/granted;
- normal upgrade with existing store;
- incompatible/corrupt store error with безопасным recovery;
- release about/version information.

## Данные и контракты

- Public artifact содержит только необходимые executable/resources.
- Signing secrets не хранятся в repository, artifact или logs.
- Checksum и версия однозначно соответствуют release artifact.
- Uninstall notes честно описывают расположение локальных данных и способ их удаления; приложение не удаляет данные без user action.

## Acceptance criteria

- [ ] Release build использует deployment target macOS 14, Hardened Runtime, ожидаемые architectures и минимальный набор entitlements; App Sandbox и network client/server entitlement отсутствуют.
- [ ] Все executables внутри artifact подписаны Developer ID, archive успешно проходит Apple notarization, ticket stapled, а Gatekeeper проверка проходит на загруженной копии.
- [ ] На чистом профиле macOS 14 пользователь устанавливает приложение, понимает локальное хранение/риск секретов, выдаёт или отклоняет Accessibility и видит честное degraded state при отказе.
- [ ] На чистой системе выполняются PJ-001 и PJ-002; отказ разрешения, повторная выдача, sleep/wake и повторный запуск не приводят к потере управляемости.
- [ ] Network inspection основной сессии не показывает runtime requests Qipli; clipboard text, search queries и previews отсутствуют в logs и release diagnostics.
- [ ] Delete one, clear all и auto-retention сохраняются после перезапуска; clear-all удаляет управляемый store/sidecars, но UI/docs не обещают secure erase и не заявляют очистку system pasteboard.
- [ ] Upgrade поверх предыдущей test build сохраняет записи моложе 30 дней или выполняет документированное безопасное migration/recovery без молчаливой частичной потери.
- [ ] GitHub Release содержит artifact, checksum, системные требования, changelog, инструкции установки/Accessibility, privacy summary и ссылку на исходный код/license; signing credentials нигде не опубликованы.

## Verification

- [ ] Полный automated test suite и чистые Debug/Release builds.
- [ ] Проверка entitlements/signatures всех executables, Gatekeeper assessment и notarization log без warnings, требующих исключений.
- [ ] Clean-machine/manual matrix из `TECHNICAL.md`, включая macOS 14 и доступные более новые версии.
- [ ] Network/log audit во время capture, history paste, stack paste и delete flows.
- [ ] Install → data capture → upgrade → verify → delete-all → restart сценарий.
- [ ] Скачать опубликованный artifact заново, проверить checksum и запуск, а не тестировать только локальный archive.

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

Зависит от S003 и S007; перед началом нужны signing/notarization credentials.
