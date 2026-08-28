# Qipli — план поставки MVP и первого публичного релиза

Статус: core MVP подтверждён; первый signed public release опубликован, verification и secure updates активны

Дата: 2026-08-28

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
11. [`S011 — Опциональный first-run onboarding`](slices/S011-first-run-onboarding.md) — зависит от S010; реализован и ожидает ручной проверки.
12. [`S012 — Edge-to-edge Paste Stack с кастомным header`](slices/S012-borderless-paste-stack-panel.md) — зависит от S007 и S009; реализован и ожидает ручной visual/interaction matrix.
16. [`S016 — Надёжная навигация и закрытие History`](slices/S016-history-interaction-reliability.md) — зависит от S003; keyboard focus, single paste transaction, fresh capture и History-only passive click-away реализованы и ожидают ручной macOS проверки.

Результат: визуально цельный Qipli имеет единое Settings window, пользовательские shortcuts, явный launch-at-login control и опциональный first-run onboarding до начала clipboard capture.

## Milestone M4 — Публичная поставка и безопасные обновления

13. [`S013 — Версии и безопасный public CI`](slices/S013-versioning-public-ci.md) — завершён; локальные, push-to-main, обычный PR и fork-style runs прошли без release secrets и write permissions.
14. [`S014 — Публичный репозиторий и подписанные GitHub-релизы`](slices/S014-public-signed-github-releases.md) — repository public, protected tag run опубликовал Developer ID-signed/notarized `v1.0.0`; статус `needs_verification` до immutable rerun proof и clean-machine macOS 14 launch.
15. [`S015 — Безопасные обновления через Sparkle`](slices/S015-sparkle-secure-updates.md) — `in_progress` параллельно manual gates S014; broken `v1.0.1` сохраняется immutable, `v1.0.2` является ручным runtime-linking hotfix, а `v1.0.3` должен доказать реальный upgrade.

Результат: публичный репозиторий проверяет вклад без signing secrets, версионный tag создаёт один проверенный release artifact, а установленный Qipli может безопасно перейти на следующую подписанную версию.

## Milestone M5 — Публичный MVP

8. [`S008 — Приватность и первый стабильный релиз через GitHub`](slices/S008-release-hardening.md) — финальный release gate; зависит от S003, S007, S010–S012 и S014–S016 и остаётся заблокированным до завершения manual/clean-machine matrix.

Результат: подписанный notarized артефакт для macOS 14+, заново скачанный и проверенный на чистой системе вместе с onboarding, Settings, permission, custom-shortcut и launch-at-login flows.

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
```

Граф ацикличен. S013 завершён после локальных и hosted main/PR/fork CI runs. S014 опубликовал реальный `v1.0.0` и остаётся `needs_verification` до immutable rerun и clean-machine proof. Пользователь разрешил начать S015 параллельно, потому что implementation/credential blocker снят; `v1.0.1` добавил Sparkle, но не запускался из-за missing runtime search path, поэтому `v1.0.2` исправляет launch вручную, а `v1.0.3` доказывает update. S011, S012 и S016 реализованы и требуют ручной проверки. S008 остаётся финальным gate. Изменения pasteboard/input, permission, ServiceManagement, network, dependency, signing или update contracts должны сначала согласовываться в `TECHNICAL.md` и `DECISIONS.md`.

## Покрытие требований

| Требование | Срезы |
|---|---|
| FR-001 | S002 |
| FR-002 | S002 |
| FR-003 | S003 |
| FR-004 | S003 |
| FR-005 | S003 |
| FR-006 | S002, S003, S008 |
| FR-007 | S004 |
| FR-008 | S004 |
| FR-009 | S005 |
| FR-010 | S005 |
| FR-011 | S006 |
| FR-012 | S006 |
| FR-013 | S007 |
| FR-014 | S006 |
| FR-015 | S004, S007 |
| FR-016 | S001, S003, S006 |
| FR-017 | S009, S012 |
| FR-018 | S010, S008 |
| FR-019 | S010, S008 |
| FR-020 | S010, S008 |
| FR-021 | S011, S008 |
| FR-022 | S014 |
| FR-023 | S014, S008 |
| FR-024–FR-025 | S015, S008 |
| FR-026 | S016, S008 |
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
| NFR-001 | S001, S008 |
| NFR-002–NFR-003 | S002, S008, S015 |
| NFR-004 | S001, S006, S010, S008 |
| NFR-005–NFR-006 | S003, S004, S006, S007, S009, S012, S016 |
| NFR-007 | S008 |
| NFR-008 | S001–S007, S009–S016 |
| NFR-009 | S009, S012 |
| NFR-010–NFR-011 | S010, S011 |
| NFR-012–NFR-013 | S013, S014 |
| NFR-014 | S014, S015, S008 |
| NFR-015 | S015, S008 |

Каждое must-have требование покрыто хотя бы одним срезом. Детальные acceptance criteria и verification находятся только в соответствующих slice-файлах.

## Правила изменения плана

- Статус меняется только в [`STATE.md`](STATE.md); frontmatter среза синхронизируется в той же правке.
- `planned` срез должен быть перепроверен на зависимости и переведён в `ready` непосредственно перед реализацией.
- Значимое отклонение от продукта или архитектуры сначала записывается в [`DECISIONS.md`](DECISIONS.md).
- Срез нельзя пометить `done`, пока заполнен не только чек-лист, но и Implementation report.
- Новая функция MVP или первого публичного релиза должна получить `FR/BR/NFR` ID и покрытие срезом; функция «на потом» не должна незаметно попадать в acceptance criteria.
