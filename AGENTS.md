<!-- BEGIN EASY PRD WORKFLOW -->
## Процесс работы с документацией проекта

### Карта документов

- `PROJECT_BRIEF.md` — неизменяемый снимок подтверждённого замысла и исходных продуктовых решений.
- `docs/PRODUCT.md` — источник истины для границы MVP, поведения, требований `FR/BR/NFR`, состояний и продуктовых предположений.
- `docs/TECHNICAL.md` — источник истины для архитектуры, системных контрактов macOS, данных, разрешений, безопасности, тестов и распространения.
- `docs/PLAN.md` — milestones, порядок срезов, зависимости и покрытие требований.
- `docs/STATE.md` — единственный источник истины для текущих статусов, блокеров, последней проверки и следующего действия.
- `docs/BACKLOG.md` — отложенные наблюдения и идеи, которые пока не входят в план и не назначены на срез.
- `docs/DECISIONS.md` — журнал подтверждённых решений, предложений и предположений.
- `docs/slices/S001-foundation-permissions.md` — walking skeleton и проверка Accessibility/event tap.
- `docs/slices/S002-history-capture-retention.md` — захват, хранение, retention и удаление истории.
- `docs/slices/S003-history-search-paste.md` — поиск и повторная вставка из истории.
- `docs/slices/S004-stack-collection.md` — сбор значений и панель Paste Stack.
- `docs/slices/S005-stack-order-direction.md` — ручной порядок и направление обхода.
- `docs/slices/S006-stack-sequential-paste.md` — последовательная вставка, used-state и auto-finish.
- `docs/slices/S007-stack-recovery-cancel.md` — reactivation и отмена стека.
- `docs/slices/S008-release-hardening.md` — privacy hardening и подписанный GitHub-релиз.
- `docs/slices/S009-adaptive-glass-panels.md` — адаптивные стеклянные панели для macOS 14+.
- `docs/slices/S010-settings-shortcuts-login.md` — Settings, configurable Qipli shortcuts и Launch at Login.
- `docs/slices/S011-first-run-onboarding.md` — опциональный onboarding до первого pasteboard capture.
- `docs/slices/S012-borderless-paste-stack-panel.md` — edge-to-edge Paste Stack с кастомным header.
- `docs/slices/S013-versioning-public-ci.md` — единый контракт версий и безопасный unsigned CI для публичной разработки.
- `docs/slices/S014-public-signed-github-releases.md` — публичный репозиторий и подписанные notarized GitHub-релизы по тегу.
- `docs/slices/S015-sparkle-secure-updates.md` — ручная и opt-in автоматическая проверка обновлений через Sparkle.
- `docs/slices/S016-history-interaction-reliability.md` — надёжная навигация, вставка и History-only click-away.
- `docs/slices/S017-performance-baselines.md` — воспроизводимые performance baselines, бюджеты и безопасная instrumentation.
- `docs/slices/S018-history-storage-efficiency.md` — индексы History, batch retention и проверка query plan.
- `docs/slices/S019-async-history-pipeline.md` — последовательный background persistence pipeline и устранение лишних reload.
- `docs/slices/S020-responsive-history-search.md` — отзывчивый поиск и ограниченные UI previews без потери полного текста.
- `docs/slices/S021-paste-stack-scaling.md` — линейная обработка больших Paste Stack без скрытого квадратичного рендеринга.
- `docs/slices/S022-pasteboard-polling-energy.md` — энергоэффективный pasteboard polling с прежней частотой и capture-контрактом.
- `docs/slices/S023-paginated-typed-history-foundation.md` — typed schema, keyset pagination и database-backed History search.
- `docs/slices/S024-managed-image-history.md` — managed inline images, quotas, thumbnails и typed pasteback.
- `docs/slices/S025-referenced-url-file-video-history.md` — URL и reference-only file/video History без копирования source bytes.
- `docs/slices/S026-typed-history-release-hardening.md` — migration, privacy, cleanup и signed update verification typed History.
- `docs/slices/S027-top-notch-history-shelf.md` — верхняя transient History с Search, карточками и hardware-safe placement.
- `docs/slices/S028-full-card-history-library.md` — отложенная в backlog историческая спецификация отдельного полноразмерного окна History.
- `docs/slices/S029-history-favorites-navigation.md` — отложенная в backlog историческая спецификация Favorites.
- `docs/slices/S030-top-notch-paste-stack.md` — перенос полного Paste Stack user path в nonactivating Top Notch presentation.
- `docs/slices/S031-formatted-text-history.md` — bounded RTF/HTML representations, rich paste и явная plain-text вставка из History.

### Подход к поставке

- Профиль: `production`, потому что публичная сборка обрабатывает чувствительные локальные данные и устанавливает исполняемые обновления.
- Timebox: не задан.
- Push и pull request используют только unsigned CI без release secrets. Полные signing, notarization, update и clean-machine gates выполняются на этапах, заданных в `docs/PLAN.md`.
- Для реализации существующего среза используйте `docs/STATE.md`, выбранный slice и только связанные требования. Повторно запускайте Easy PRD лишь при изменении продуктовой границы, интеграции или release-контракта.

### Выбор контекста по задаче

Не загружайте все документы автоматически.

- **Вопрос о коде:** прочитайте релевантный код и тесты. `docs/PRODUCT.md` нужен только при споре об ожидаемом поведении; `docs/STATE.md` необязателен.
- **Локальная визуальная, текстовая или техническая правка:** прочитайте затронутый код, UI и тесты. Документы не нужны, если поведение и контракты не меняются.
- **Продолжение плановой реализации:** прочитайте `docs/STATE.md`, выбранный slice-файл и только связанные с его `covers` требования в `docs/PRODUCT.md`/`docs/TECHNICAL.md`.
- **Новая функция:** прочитайте границу MVP в `docs/PRODUCT.md`, `docs/PLAN.md`, релевантные решения и срезы. До реализации создайте или обновите slice и coverage map.
- **Изменение данных, архитектуры, системного ввода, разрешений или релиза:** прочитайте `docs/TECHNICAL.md`, `docs/DECISIONS.md` и затронутые срезы. Перепроверьте Apple platform sources, если меняются минимальная macOS, Accessibility/event tap, sandbox, entitlements или distribution.
- **Незапланированное исправление:** можно работать вне активного среза. Обновляйте документацию только если меняются поведение, контракт, данные, архитектура, статус или план.

### Завершение среза

Не ставьте `done`, пока все acceptance criteria и verification steps не пройдены, Implementation report не заполнен, `docs/STATE.md` и frontmatter не синхронизированы, а новые значимые решения не записаны. Похожий код без проверки получает максимум `needs_verification`.

### Правила Qipli

- Никогда не добавляйте clipboard text, поисковые запросы, URL, filenames/paths, media metadata, thumbnails или previews в логи и test fixtures с реальными пользовательскими данными.
- Не меняйте обычный `⌘V`, когда Paste Stack не активен.
- Внутренние записи Qipli в system pasteboard не должны возвращаться как новые history/stack items.
- Не добавляйте сеть, telemetry, App Sandbox exceptions, helper process или стороннюю persistence dependency без решения в `docs/DECISIONS.md` и обновления технического контракта.
- `PROJECT_BRIEF.md` сохраняйте как источник исходного замысла; уточнения вносите в рабочие документы, не переписывая brief задним числом.

### Рост документации

Сначала добавляйте раздел в существующий документ. Выносите отдельный файл только для самостоятельного домена с собственным жизненным циклом. После выноса оставляйте одну точку истины, исправляйте ссылки и карту документов.
<!-- END EASY PRD WORKFLOW -->
