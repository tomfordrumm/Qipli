---
id: S034
title: Rich text и изображения в Paste Stack
depends_on:
  - S033
  - S024
  - S031
covers:
  - FR-047
  - FR-048
  - BR-035
  - BR-036
  - NFR-034
---

# S034: Rich text и изображения в Paste Stack

## Пользовательский результат

Пользователь собирает одну последовательность из обычного текста, форматированного текста и inline images, проверяет её в Stack и вставляет через обычное Cmd+V. Текст сохраняет стандартные RTF/HTML representations, картинки вставляются как изображения. Compact и expanded presentation S033 показывают ту же последовательность.

Контракт: FR-047/FR-048, BR-035/BR-036, NFR-034 в [PRODUCT.md](../PRODUCT.md), технический раздел S034 в [TECHNICAL.md](../TECHNICAL.md), D-044. Статус только в [STATE.md](../STATE.md).

## В scope

- Поддержка существующих capture kinds `.text`, `.richText` и `.images`, включая несколько image items одной occurrence. Одно внешнее копирование создаёт один Stack occurrence; одинаковые copies остаются разными UUID.
- Plain text вставляется точно, rich text восстанавливает сохранённые standard string/RTF/HTML representations и исходный порядок items. Inline images используют существующие managed originals и typed writer History, без image-as-file conversion.
- Plain URL/string сохраняет прежний text path. File/video references и mixed image+reference остаются History-only с явным notice. Смешанный rich+image clipboard поддерживается лишь в пределах текущей нормализации History, новый arbitrary multi-type capture pipeline не входит в срез.
- Text/rich cards показывают bounded canonical plain preview без рендеринга markup; images показывают bounded local thumbnails, placeholder и unavailable state. Много изображений внутри одного copy обозначается числом, а preview показывает первое доступное. Compact previews не меняют order/traversal.
- Sequential paste, direction/reorder до traversal, Used, Reactivate, retry, Cancel/Escape и auto-finish одинаковы для поддерживаемых типов.
- Capture quotas/fallback History сохраняются. Если History принял formatted copy как plain-only, Stack получает именно этот сохранённый вариант с notice. Уже сохранённый rich/image payload при paste не деградирует молча.

## Вне scope

RTFD, WebArchive, произвольные/private types, загрузка внешних ресурсов, HTML renderer, OCR, file/video Stack, image-as-file, сохранение session после relaunch, templates, новые global shortcuts и отдельный plain-paste режим Stack. History Shift+Enter остаётся прежним.

## Данные, срок жизни и ошибки

В session хранятся immutable lightweight descriptors и opaque payload handles; rich/image bytes не копируются в массив карточек или в каждый occurrence. Raw payload материализуется вне main actor только для текущей reservation; thumbnails используют bounded cache.

При успешном History commit и совпадении session/watermark Stack получает occurrence и session lease на owned payload. Automatic expiry не удаляет leased assets до завершения session, в том числе для used items, доступных Reactivate. Lease не является favorite и не продлевает History activityAt; retained bytes учитываются существующими quotas. При Cancel/finish/restart процесса leases исчезают и разрешается cleanup. Не создавать отдельное неограниченное хранилище Stack.

Уточнение планирования для ручного удаления: explicit History Delete отзывает handle соответствующего активного Stack occurrence, включая plain snapshots, и очищает его preview. Карточка остаётся на месте как unavailable, без автоматического пропуска или вставки stale copy. Clear All отменяет активную session, инвалидирует отложенную вставку и очищает managed store. Это сохраняет смысл явного удаления; UI удаления должен сообщать о влиянии на активный Stack. Не требуется новый диалог подтверждения. Эти правила являются частью D-044, а не описанием текущего кода.

Missing/corrupt asset, revoked handle, permission/writer/dispatch failure оставляют reservation retryable без изменения порядка и used-state. У permanently deleted item восстановление невозможно: notice предлагает отменить Stack и собрать заново. Тихого перехода к следующему item нет. Для обычной ошибки доступен повтор Cmd+V после устранения причины.

Неудачный lease/admission не создаёт partial Stack occurrence, но уже сохранённый History остаётся. Отмена/новая session во время capture/materialization не публикует и не вставляет результат старой session.

## Acceptance criteria

- [ ] Серия text → rich text → image → duplicate text собирается в четыре occurrences и вставляется точно по одному на accepted Cmd+V в прямом и обратном порядке.
- [ ] Rich paste сохраняет plain fallback и все допущенные RTF/HTML representations; совместимый target получает форматирование, plain target получает canonical text. Qipli не обещает одинаковую визуальную интерпретацию сторонними редакторами.
- [ ] Inline image и multiple-image occurrence вставляются исходными supported representations в исходном item order. Thumbnail никогда не становится paste payload.
- [ ] Compact/expanded cards показывают правильный тип/preview, pending count, Next/Processing/Used и reactivation; reused card не сохраняет чужой thumbnail. UI не materialize-ит все originals.
- [ ] File/video и mixed image+reference не меняют Stack order/next и дают понятный notice; существующая History сохраняет свой typed path.
- [ ] Overflow/plain-only admission и failed commit/lease не создают partial occurrences, не удаляют старую History и показывают payload-free notice.
- [ ] Automatic expiry не ломает pending/used leased payload; Cancel/finish освобождают leases, startup cleanup после crash не оставляет бессрочных assets, quota accounting включает retained bytes.
- [ ] Delete отзывает exact Stack handle и preview без пропуска позиции; Clear All отменяет session и удаляет store. После отмены или отзыва in-flight materialization не dispatch-ит старый payload.
- [ ] Missing/corrupt payload, permission denial, write/dispatch failure и rapid repeats не пропускают item и не создают duplicate. Reactivation failure сохраняет прежний priority.
- [ ] После каждого Qipli write self-write suppression регистрирует exact final changeCount до monitor poll, включая случай отмены после записи; payload не возвращается в History/Stack.
- [ ] Обычный Cmd+V вне Stack, History rich/plain paste, source/target focus и S033 lifecycle не регрессируют. Нет новых permissions, runtime network, dependencies или payload logs.

## Verification

1. До изменений проверить существующие capture normalization, History materializer/writer, asset cleanup/quotas и Stack reservation seams. Использовать synthetic local fixtures.
2. Capture tests: поддерживаемые виды, multiple items/duplicates, History-first ordering, watermark, cancel/new session, plain fallback, History-only media, failed lease/admission.
3. Executor tests: async materialization, exact payload items/bytes, self-write count, rapid Cmd+V, cancellation/deletion перед write и dispatch, failure retry, reverse/reactivation и auto-finish.
4. Lifecycle tests с real temporary store: expiry while leased, manual Delete/Clear All, used-item reactivation, total quotas, release cleanup, crash/restart и corruption. Существующая metadata migration не должна менять UUID/activityAt; если схема изменена, добавить migration coverage.
5. UI tests: compact/expanded thumbnail reuse, bounded decode/cache, unavailable/processing и VoiceOver labels. Full SwiftPM suite, development-signed Debug и unsigned universal Release builds.
6. Installed-app matrix: TextEdit и browser contenteditable для rich/plain, Preview/browser image source и Notes или другой установленный image-compatible target; несколько image items, plain-only target, reorder/reverse, Reactivate, ошибки и cancel. Проверить сохранённые History rich/images после relaunch, не обещая восстановления Stack.
7. Перед публичной поставкой проверить signed update с прежними History assets по S024/S031 и текущему release plan. Не переобозначать открытые gates S031 как пройденные только из-за переиспользования кода.
8. Scoped privacy/log scan и `git diff --check`. Automated payload equality, пользовательская совместимость target apps и distribution фиксируются отдельно.

## Implementation report

Реализовано локально 2026-09-15; пользователь подтвердил завершение среза 2026-09-16 после smoke-теста и исправления compact image thumbnail.

- Capture теперь идёт History-first: `.text`, `.richText` и `.images` получают typed payload handles, а `.references`/`.mixed` остаются History-only с notice. Stack хранит descriptors и process-local session leases, которые защищают leased assets от expiry и отзываются при Delete/Clear All/Cancel/finish.
- Sequential paste материализует payload асинхронно через существующие History stores/writers, проверяет session/reservation/lease и exact pasteboard `changeCount`, а Used отмечается только после tagged dispatch. Unavailable card остаётся на месте и не пропускается молча.
- Compact/expanded UI показывает bounded rich/text previews, image thumbnails/placeholders и unavailable state; thumbnail не используется как paste payload. После image capture thumbnail запрашивается сразу, а `thumbnailUpdateRevisionsByEntryID` обновляет compact preview без повторного открытия панели.
- Проверено: focused S034 tests `4/4`; полный SwiftPM suite `259` tests, `0` failures, `5` skipped; unsigned universal Debug и Release builds; development-signed universal Debug build; version contract и embedded Sparkle runtime linking.
- Пользовательский smoke-тест выявил задержку thumbnail в compact view; исправление прошло focused thumbnail regression test и unsigned universal Debug build. Пользователь подтвердил закрытие среза 2026-09-16.

Отдельно открыты delivery gates: повторный installed-app thumbnail smoke и полная source/target matrix (TextEdit, browser, Preview/Notes), Accessibility/VoiceOver и rapid-interaction smoke, а также signed Sparkle update с сохранением прежних History assets по S031. Они не блокируют пользовательски закрытый implementation slice S034 и должны оставаться различимыми от его статуса.
