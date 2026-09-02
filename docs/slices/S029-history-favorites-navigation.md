---
id: S029
title: Favorites navigation
status: backlog
depends_on:
  - S028
covers:
  - FR-035
  - BR-026
  - BR-027
  - NFR-027
  - NFR-028
---

# S029: Favorites navigation

> 2026-09-02 срез выведен из активного плана в `BL-005` решением D-038. Спецификация ниже сохраняется как историческая проработка; presentation и retention semantics должны быть подтверждены заново до возвращения в план.

## Пользовательский результат

В полноценной History пользователь переключается между общей историей и Favorites, помечает важную occurrence и ищет внутри выбранного раздела. Favorite остаётся локальным свойством существующей occurrence и не создаёт копию payload.

## Предусловие перед `ready`

Пользователь подтверждает D-037: Favorite не продлевает 30-day retention. Если favorite должен быть бессрочным pin, PRODUCT/TECHNICAL/data migration/cleanup contracts и этот slice сначала пересматриваются.

## В scope

- navigation destinations `History` и `Favorites` в full History window;
- local favorite marker на occurrence и idempotent add/remove action;
- favorite action на full card и, если помещается без перегрузки, на Top Notch card через тот же intent;
- database-backed filter/search внутри выбранного destination;
- preservation destination/query/selection при refresh, paging и relaunch, кроме исчезнувшей occurrence;
- Delete, expiry и Clear All cleanup favorite marker вместе с occurrence;
- accessible labels, selected destination и empty Favorites state.

## Вне scope

- бессрочное хранение, отдельная копия payload или activity promotion только из-за favorite toggle;
- reorder Favorites, folders, tags, smart collections и дополнительные destinations;
- account, sync, share, telemetry или remote metadata;
- edge placement Settings.

## Данные и контракты

- Favorite хранится как локальная indexed metadata occurrence, а не в card view state. Toggle не читает exact payload.
- Favorite toggle не меняет `activityAt`; обычный successful history paste по-прежнему может продвинуть occurrence по существующему contract.
- Destination и query образуют единый query key. Stale async result другого destination/query не может заменить актуальный.
- Если selected occurrence удалена, expired или больше не входит в Favorites, selection выбирает первый доступный descriptor либо честное empty state.
- Favorite marker не попадает в clipboard, logs, update requests или filenames managed assets.

## Acceptance criteria

- [ ] Full History содержит ровно два подтверждённых destination: History и Favorites; переключение не создаёт второе окно.
- [ ] Favorite toggle сохраняется после relaunch, идемпотентен и не дублирует occurrence или payload.
- [ ] Favorites показывает только marked non-expired occurrences и поддерживает тот же bounded search/paging/card contract.
- [ ] Toggle не меняет activity order сам по себе и не продлевает retention.
- [ ] Delete, expiry и Clear All удаляют marker вместе с occurrence; expired favorite не остаётся orphan row.
- [ ] Selection, query and stale-result guards корректны при быстром переключении History/Favorites и toggle выбранной карточки.
- [ ] Empty Favorites, unavailable media, keyboard/VoiceOver navigation и appearance states понятны без hover-only controls.
- [ ] Никаких новых network requests, telemetry или sensitive logs не появляется.

## Verification

- repository migration/index/toggle/relaunch tests без real user payload fixtures;
- retention boundary tests: favorite before cutoff, expiry, delete and Clear All cleanup;
- destination/query generation tests на stale results, paging and selection fallback;
- UI keyboard/VoiceOver tests для navigation, toggle и empty Favorites;
- full SwiftPM/Xcode suite, universal Release build, privacy/network scan и `git diff --check`;
- manual History/Favorites/toggle/relaunch/search/paste/delete/expiry/Clear All matrix.

## Implementation report

Не начато.
