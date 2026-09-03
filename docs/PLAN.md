# Qipli — план поставки и развития продукта

Статус: core MVP подтверждён; signed public release опубликован; typed History и S027 завершены; S030 реализован и ждёт manual verification

Дата: 2026-09-02

Источник оперативных статусов: [`STATE.md`](STATE.md)

## Принцип поставки

Каждый срез заканчивается наблюдаемым результатом и включает UI, доменную логику, системные адаптеры и тесты, необходимые именно для этого результата. Отдельные «сделать БД», «сделать UI» или «подключить API» не считаются срезами.

## Milestone M1 — Рабочая локальная история

После milestone Qipli запускается как нативная утилита, честно управляет разрешением, сохраняет 30-дневную текстовую историю, позволяет искать, удалять и повторно вставлять значения.

1. [`S001 — Скелет приложения и системное разрешение`](slices/S001-foundation-permissions.md) — первый завершённый срез.
2. [`S002 — Захват, хранение и удаление истории`](slices/S002-history-capture-retention.md) — зависит от S001.
3. [`S003 — Поиск и повторная вставка из истории`](slices/S003-history-search-paste.md) — зависит от S002.

## Milestone M2 — Paste Stack

После milestone пользователь может собрать, упорядочить, последовательно вставить и восстановить серию значений.

4. [`S004 — Сбор и визуальная панель Paste Stack`](slices/S004-stack-collection.md) — зависит от S002.
5. [`S005 — Порядок и направление обхода`](slices/S005-stack-order-direction.md) — зависит от S004.
6. [`S006 — Последовательная вставка и прогресс`](slices/S006-stack-sequential-paste.md) — зависит от S001 и S005.
7. [`S007 — Повторная активация и отмена`](slices/S007-stack-recovery-cancel.md) — зависит от S006.

## Milestone M3 — Визуальный polish и product setup

9. [`S009 — Адаптивные стеклянные панели`](slices/S009-adaptive-glass-panels.md) — зависит от S001, S003 и S007; может выполняться до S008, пока release credentials недоступны.
10. [`S010 — Settings, пользовательские сочетания и запуск при входе`](slices/S010-settings-shortcuts-login.md) — зависит от S001, S007 и S009; завершён.
11. [`S011 — Опциональный first-run onboarding`](slices/S011-first-run-onboarding.md) — зависит от S010; завершён после пользовательской ручной проверки на двух машинах.
12. [`S012 — Edge-to-edge Paste Stack с кастомным header`](slices/S012-borderless-paste-stack-panel.md) — зависит от S007 и S009; завершён после пользовательской visual/interaction matrix на двух машинах.
16. [`S016 — Надёжная навигация и закрытие History`](slices/S016-history-interaction-reliability.md) — зависит от S003; завершён после пользовательской ручной macOS проверки на двух машинах.

Результат: визуально цельный Qipli имеет единое Settings window, пользовательские shortcuts, явный launch-at-login control и опциональный first-run onboarding до начала clipboard capture.

## Milestone M4 — Публичная поставка и безопасные обновления

13. [`S013 — Версии и безопасный public CI`](slices/S013-versioning-public-ci.md) — завершён; локальные, push-to-main, обычный PR и fork-style runs прошли без release secrets и write permissions.
14. [`S014 — Публичный репозиторий и подписанные GitHub-релизы`](slices/S014-public-signed-github-releases.md) — protected `v1.0.5` run опубликовал Developer ID-signed/notarized DMG, stable latest alias и Sparkle ZIP; clean-machine install/launch подтверждены. Статус `needs_verification` до immutable rerun proof.
15. [`S015 — Безопасные обновления через Sparkle`](slices/S015-sparkle-secure-updates.md) — завершён после ручной update/failure/accessibility matrix; broken `v1.0.1` сохраняется immutable, `v1.0.2` является runtime-linking hotfix, production feed указывает на `v1.0.5`.

Результат: публичный репозиторий проверяет вклад без signing secrets, версионный tag создаёт проверенный DMG для ручной установки и immutable ZIP для Sparkle, а установленный Qipli может безопасно перейти на следующую подписанную версию.

## Milestone M5 — Публичный MVP

8. [`S008 — Приватность и первый стабильный релиз через GitHub`](slices/S008-release-hardening.md) — финальный release gate; зависит от S003, S007, S010–S012 и S014–S016 и остаётся заблокированным до operational proof immutable rerun опубликованного release tag.

Результат: подписанный notarized артефакт для macOS 14+, заново скачанный и проверенный на чистой системе вместе с onboarding, Settings, permission, custom-shortcut и launch-at-login flows.

## Milestone M6 — Performance hardening

После milestone локальные History и Paste Stack сохраняют подтверждённое поведение при росте данных, persistent I/O не блокирует main actor, а performance regressions обнаруживаются воспроизводимыми payload-free checks.

17. [`S017 — Performance baselines и instrumentation`](slices/S017-performance-baselines.md) — завершён; безопасные fixtures, измеряемые seams и исходные baselines зафиксированы до оптимизаций.
18. [`S018 — Эффективное History storage`](slices/S018-history-storage-efficiency.md) — завершён; UUID/composite order indices, batch retention и migration/query-plan verification реализованы.
19. [`S019 — Асинхронный History pipeline`](slices/S019-async-history-pipeline.md) — завершён; background persistence, строгий порядок capture, отсутствие unconditional show reload и manual immediate-show smoke подтверждены.
20. [`S020 — Отзывчивый поиск и ограниченные previews`](slices/S020-responsive-history-search.md) — завершён; cancellable stale-safe off-main search, bounded UI text traversal и manual rapid-typing smoke подтверждены.
21. [`S021 — Масштабируемый Paste Stack`](slices/S021-paste-stack-scaling.md) — завершён; single-pass next traversal, один подготовленный next ID и manual Stack smoke подтверждены.
22. [`S022 — Энергоэффективный pasteboard polling`](slices/S022-pasteboard-polling-energy.md) — завершён; tolerance-aware scheduler, direct main-actor poll, idle observation и manual clipboard/sleep-wake smoke подтверждены.

Результат: приложение имеет измеряемые performance contracts и focused regression coverage для storage, capture, search, preview, Stack и polling без изменения privacy или пользовательских сценариев.

## Milestone M7 — Bounded typed History

После milestone History работает как ограниченный metadata-каталог: первая и последующие страницы содержат не более 500 descriptors, поиск выполняется в persistence по всему 30-дневному окну, а text, URL, inline images и file/video references восстанавливаются через typed pasteboard contract без загрузки media payload в UI snapshot.

23. [`S023 — Bounded typed History foundation`](slices/S023-paginated-typed-history-foundation.md) — `done`; bounded schema/query boundary, migration, search parity и native History contract реализованы и проверены.
24. [`S024 — Managed image History`](slices/S024-managed-image-history.md) — `done`; manual native/browser matrix, optimized universal Release и scoped security diff scan подтверждены.
25. [`S025 — Referenced URL, file and video History`](slices/S025-referenced-url-file-video-history.md) — `done`; implementation, automated gates и manual browser/Finder matrix подтверждены.
26. [`S026 — Typed History migration and release hardening`](slices/S026-typed-history-release-hardening.md) — `done`; migration fault-injection, privacy/cleanup audit, signed/notarized `v1.0.6 (7)` и update/clean-machine typed History smoke подтверждены.

Результат: media расширяет History без роста initial working set, скрытого auto-eviction или копирования source file/video bytes. Paste Stack остаётся text-only до отдельного будущего решения.

## Milestone M8 — Top Notch History

После milestone default `⌘⇧V` открывает верхнюю карточную панель с поиском, type-aware cards и прежним exact paste/focus contract.

27. [`S027 — Top Notch History shelf`](slices/S027-top-notch-history-shelf.md) — `done`; implementation, focused automated gates и ручная geometry/focus/paste/accessibility matrix верхней transient-панели подтверждены.

Результат: быстрый transient History path остаётся keyboard-first. S028 и S029 выведены из активного плана в BL-004/BL-005 решением D-038; отдельное окно, Favorites и альтернативное положение остаются backlog.

## Milestone M9 — Paste Stack в Top Notch

После milestone `⌘⇧C` и status menu показывают Paste Stack в той же hardware-safe верхней форме, что History, но Stack сохраняет отдельный nonactivating lifecycle и весь подтверждённый sequence/recovery contract.

30. [`S030 — Paste Stack в Top Notch`](slices/S030-top-notch-paste-stack.md) — `needs_verification`; implementation и focused automated checks прошли, manual matrix остаётся открытой; зависит от завершённых S007/S012/S021/S027 и заменяет отдельное перемещаемое Stack window единым верхним presentation.

Результат: History и Paste Stack используют одну визуальную Top Notch оболочку. History принимает Search focus и закрывается по своим transient rules; Stack не активирует Qipli, остаётся видимым во время работы во внешнем приложении и схлопывается только после Cancel/Escape/auto-finish.

## Граф зависимостей

```text
S001 -> S002 -> S003
S002 -> S004 -> S005 -> S006 -> S007
S001 + S003 + S007 -> S009
S007 + S009 -> S012
S001 + S007 + S009 -> S010 -> S011
S003 -> S016
S013 -> S014 -> S015
S003 + S007 + S010 + S011 + S012 + S014 + S015 + S016 -> S008
S017 -> S018 -> S019 -> S020 -> S021 -> S022
S018 + S019 + S020 -> S023 -> S024 -> S025
S014 + S015 + S024 + S025 -> S026
S016 + S024 -> S027
S007 + S012 + S021 + S027 -> S030
```

Граф ацикличен. Performance hardening S017–S022 завершён. Typed History начинается с bounded schema/query boundary в S023; managed images добавляются в S024; reference-only URL/file/video — в S025; migration/release proof — в S026. S023–S026 завершены. Top Notch S027 реализован и принят по manual geometry/focus/paste/accessibility matrix. Решением D-038 S028/S029 перенесены в backlog. S030 реализован и ждёт manual Stack matrix, без специального active-Stack-to-History flow. S013 завершён после локальных и hosted main/PR/fork CI runs. S014 опубликовал реальный `v1.0.5`, clean-machine proof подтверждён, остаётся immutable rerun. S015 завершён после ручной update/failure/accessibility matrix; production feed указывает на `v1.0.5`. S008 остаётся финальным gate только до operational rerun proof. Изменения pasteboard/input, permission, ServiceManagement, network, dependency, signing, update или performance contracts должны сначала согласовываться в `TECHNICAL.md` и `DECISIONS.md`.

## Покрытие требований

| Требование | Срезы |
|---|---|
| FR-001 | S002 |
| FR-002 | S002 |
| FR-003 | S003, S027 |
| FR-004 | S003, S027 |
| FR-005 | S003, S027 |
| FR-006 | S002, S003, S008, S026 |
| FR-007 | S004, S030 |
| FR-008 | S004, S030 |
| FR-009 | S005, S030 |
| FR-010 | S005, S030 |
| FR-011 | S006, S030 |
| FR-012 | S006, S030 |
| FR-013 | S007, S030 |
| FR-014 | S006, S030 |
| FR-015 | S004, S007, S030 |
| FR-016 | S001, S003, S006 |
| FR-017 | S009, S012, S027, S030 |
| FR-018 | S010, S008 |
| FR-019 | S010, S008 |
| FR-020 | S010, S008 |
| FR-021 | S011, S008 |
| FR-022 | S014 |
| FR-023 | S014, S008 |
| FR-024–FR-025 | S015, S008 |
| FR-026 | S016, S008, S027 |
| FR-027 | S023, S026 |
| FR-028 | S024, S025 |
| FR-029 | S024 |
| FR-030 | S025 |
| FR-031 | S024, S025 |
| FR-032 | S024, S026 |
| FR-033 | S027 |
| FR-036 | S030 |
| BR-001–BR-004 | S002, S004 |
| BR-005 | S005 |
| BR-006 | S007 |
| BR-007–BR-008 | S003, S006 |
| BR-009–BR-010 | S002, S003, S008 |
| BR-011–BR-012 | S010 |
| BR-013 | S010, S011 |
| BR-014 | S011 |
| BR-015–BR-016 | S013, S014 |
| BR-017 | S014, S015 |
| BR-018 | S015 |
| BR-019–BR-020 | S024, S025 |
| BR-021 | S024, S026 |
| BR-022 | S024, S025, S027 |
| BR-023 | S024, S025, S026 |
| BR-024 | S024, S025, S030 |
| BR-027 | S027, S030 |
| BR-028 | S030 |
| NFR-001 | S001, S008 |
| NFR-002–NFR-003 | S002, S008, S015 |
| NFR-004 | S001, S006, S010, S008, S030 |
| NFR-005 | S003, S004, S006, S007, S009, S012, S016, S027, S030 |
| NFR-006 | S003, S004, S006, S007, S009, S012, S016, S030 |
| NFR-007 | S008 |
| NFR-008 | S001–S007, S009–S016 |
| NFR-009 | S009, S012, S027, S030 |
| NFR-010–NFR-011 | S010, S011 |
| NFR-012–NFR-013 | S013, S014 |
| NFR-014 | S014, S015, S008 |
| NFR-015 | S015, S008 |
| NFR-016 | S018, S019 |
| NFR-017 | S019 |
| NFR-018–NFR-019 | S017, S020, S030 |
| NFR-020 | S017, S019, S022 |
| NFR-021 | S023, S027 |
| NFR-022 | S024, S025 |
| NFR-023–NFR-024 | S024, S025, S026 |
| NFR-025 | S023, S026 |
| NFR-026 | S027, S030 |
| NFR-027–NFR-029 | S027, S030 |

Каждое must-have требование покрыто хотя бы одним активным срезом. Отложенные FR-034/FR-035 и BR-025/BR-026 сохранены как evidence в BL-004/BL-005 и S028/S029, но не входят в coverage текущей поставки. Детальные acceptance criteria и verification находятся только в соответствующих slice-файлах.

## Правила изменения плана

- Статус меняется только в [`STATE.md`](STATE.md); frontmatter среза синхронизируется в той же правке.
- `planned` срез должен быть перепроверен на зависимости и переведён в `ready` непосредственно перед реализацией.
- `backlog` срез не входит в dependency graph, current coverage или очередь реализации; для возврата нужен подтверждённый пользовательский путь, новое accepted decision и повторная проверка требований.
- Значимое отклонение от продукта или архитектуры сначала записывается в [`DECISIONS.md`](DECISIONS.md).
- Срез нельзя пометить `done`, пока заполнен не только чек-лист, но и Implementation report.
- Новая функция MVP или первого публичного релиза должна получить `FR/BR/NFR` ID и покрытие срезом; функция «на потом» не должна незаметно попадать в acceptance criteria.
