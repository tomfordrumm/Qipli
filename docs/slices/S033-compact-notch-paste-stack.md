---
id: S033
title: Компактный Paste Stack по центру
depends_on:
  - S030
covers:
  - FR-045
  - FR-046
  - BR-034
  - NFR-033
---

# S033: Компактный Paste Stack по центру

## Уточнение layout от 2026-09-14

После просмотра реализации пользователь заменил две боковые области одним центральным блоком. Это уточнение отменяет ниже прежние требования двух раздельных поверхностей и размещения ниже camera band. Остальные lifecycle, session и accessibility criteria сохраняются.

Актуальный layout: одна поверхность адаптивного размера от верхнего края экрана на всю высоту чёлки или строки меню, без центрального разрыва. На notchless display блок находится у верхнего края. Квадратные карточки стопкой слева вне физического выреза, общее число скопированных элементов справа. Окно и единая область наведения совпадают с блоком.

Уточнение визуального вида: обратные верхние скругления как у полной панели, квадратная стопка с коротким текстовым превью до двух строк слева, общее количество скопированных элементов справа. Направление остаётся в раскрытой панели.

Актуальная проверка геометрии требует центрирования, bounded frame и одной hit region. Визуальная приёмка на устройстве подтверждена пользователем 2026-09-15.

## Пользовательский результат

Во время сбора и вставки Stack занимает только полосу высотой с camera housing. Слева от чёлки видны компактные карточки, справа счётчик и направление вставки. Вкладки браузера ниже этой полосы доступны. Наведение раскрывает вниз полную панель для проверки порядка, перестановки и повторной активации.

Требования и границы: FR-045/FR-046, BR-034, NFR-033 в [PRODUCT.md](../PRODUCT.md). Технический контракт: раздел S033 в [TECHNICAL.md](../TECHNICAL.md). Решение: D-043. Статус хранится только в [STATE.md](../STATE.md).

## В scope

- Start из меню и Start/Collect по существующему shortcut открывают новую session компактно. Repeated Collect сохраняет текущую session и presentation state; новый capture сам не раскрывает панель.
- Слева bounded previews последних добавленных occurrences, в исходном порядке. При дефиците ширины сокращается число previews и длина текста, а не увеличивается высота. Пустая session показывает краткое состояние сбора.
- Справа число pending occurrences, отдельный Processing/error marker и текущее направление. При reactivation priority доступно явное обозначение повторной вставки; счётчик не выдаёт used item за pending.
- Hover над видимым левым или правым участком раскрывает полную панель. Click и accessibility action дают явный способ раскрытия без ожидания hover.
- Expanded state сохраняет существующие cards, Next/Processing/Used, direction/reorder lock, Reactivate, Cancel и ошибки. После ухода pointer за обе компактные области и expanded panel панель сворачивается без задержки.
- Drag, нажатая кнопка и открытое меню удерживают expanded state. Для VoiceOver явное раскрытие удерживается до действия «Свернуть», чтобы pointer не определял доступность элементов.
- Cancel/Escape/auto-finish заканчивают session из любого presentation state и полностью убирают поверхности и hit areas.
- Notchless display использует узкую верхнюю центральную полосу с теми же данными без искусственного выреза. Она может занимать часть рабочей области; обещание нулевого перекрытия по вертикали относится только к camera-housing layout.

## Вне scope

Rich text и images, изменение capture/paste/session semantics, сохранение stack после relaunch, перестановка compact previews, настройка размеров и таймингов в Settings, movable window, ручной выбор позиции, History redesign и переключение между History и активным Stack.

## Состояния и переходы

`hidden → compact → expanding → expanded → collapsing → compact`; Cancel/finish допускаются из любого active state и ведут в `dismissing → hidden`. Session и presentation имеют разные состояния.

- Переход начинается только после фактического входа pointer. Открытие под неподвижной мышью само не разворачивает новую session.
- Уход до начала перехода отменяет раскрытие. Возврат во время collapse transition разворачивает панель обратно без промежуточного compact state. Перемещение между compact и expanded content не вызывает мерцание.
- Новый Start, Cancel, finish, смена экрана и teardown инвалидируют старые callbacks. Новые captures обновляют данные без сброса таймеров или анимации.
- Ошибка видима и в compact state; она не раскрывает панель самовольно. Подробность и retry остаются в expanded state.
- После screen disconnect геометрия и tracking пересчитываются во всех фазах, включая expanding/collapsing/dismissing. Невидимая потерянная panel не должна оставлять пользователя с активным Stack без доступного управления.

Уточнение пользователя: задержки hover/collapse убраны; переход начинается на следующем проходе main queue. Контур раскрывается за 220 мс и сворачивается за 180 мс, Reduce Motion оставляет короткий fade. Ширина боковых областей и число previews определяются в runtime probe по читаемости и перекрытию меню, затем фиксируются в implementation report. Уменьшать шрифт до нечитаемого размера ради большего числа карточек нельзя.

## Первый этап: runtime geometry probe

На MacBook с чёлкой проверить два небольших участка вплотную к camera gap, их рисование и hit testing в полосе `safeAreaInsets.top`. Проверить browser tabs, длинное меню приложения, системные status items, auto-hide menu bar и full-screen. Auxiliary rectangles описывают видимую геометрию, но не свободное от меню место.

Результат этапа: записать фактические размеры, screen configuration, поведение меню и выбранные window/tracking boundaries. Если компактное размещение не работает на публичных API либо перекрытие делает меню недоступным, остановить основную реализацию и согласовать корректировку поведения. Не заменять утверждённый layout молча обычной панелью под чёлкой и не добавлять private API или permissions.

## Acceptance criteria

- [x] На MacBook compact content и interactive regions целиком находятся в полосе camera housing, по бокам физического выреза. Ни видимая поверхность, ни прозрачное окно не перехватывают вкладки браузера ниже полосы.
- [x] Новая session открывается compact из меню и shortcut. Tagged Copy получает прежнее активное приложение; свежая карточка и счётчик появляются без раскрытия.
- [x] Hover/click раскрывают панель вниз до полноценного рабочего размера History с hardware-safe bounds. Уход сворачивает её; быстрый проход к вкладкам не вызывает случайного раскрытия.
- [x] Compact previews, pending count, direction, Processing, reactivation и error отражают session без отдельной копии полного массива/payload.
- [x] Drag/menu/VoiceOver interaction не обрываются автосворачиванием. Cancel доступен в expanded state, global Escape работает в обоих состояниях.
- [x] Sequential paste, duplicates, reorder lock, Reactivate, retry и auto-finish работают в обоих состояниях. Обычный Cmd+V вне active Stack и self-write suppression не изменены.
- [x] Focus остаётся во внешнем приложении. History geometry, Search, keyboard routing и click-away не изменены.
- [x] Notchless, scaled resolution, second display/disconnect во всех фазах, full-screen и auto-hide menu bar имеют проверенный layout без off-screen controls и невидимых hit areas.
- [x] Reduce Motion, Reduce Transparency, Increase Contrast и VoiceOver проходят installed-app matrix. Нет payload в logs/fixtures.

## Verification

1. Выполнить runtime probe выше до основного UI refactor, только на синтетическом содержимом.
2. Pure geometry tests: asymmetrical auxiliary areas, nil/zero geometry, screen origins/scaling, clamp, compact hit regions, notchless fallback.
3. Deterministic lifecycle tests с управляемыми часами: enter/leave, initial pointer, drag/menu/accessibility hold, re-entry, capture update, cancel/restart/finish races и disconnect во всех фазах.
4. Focused S030/S027 и S004–S007/S021 regression suites; проверить отсутствие History lifecycle hooks в Stack.
5. Full SwiftPM suite, development-signed Debug и unsigned universal Release build. Это отдельное evidence от ручной проверки и release distribution.
6. Installed-app MacBook + external display matrix в браузере и текстовом редакторе: доступ к вкладкам, меню, Copy/Paste, порядок, ошибки, cancel/finish и accessibility. Пользователь подтверждает удобство размеров и задержек.
7. `git diff --check`, scoped privacy/log scan. Signing/notarization/Sparkle gates остаются в действующем release plan; этот срез не закрывает их автоматически.

## Implementation report

Статус: `done`.

- Реализованы compact/expanded presentation states для существующего Stack panel. Новая session начинается в compact, повторный Start/Collect не сбрасывает session или presentation state, а Cancel/finish скрывают panel из любого состояния.
- Compact layout получает `NSScreen.frame`, `visibleFrame`, `safeAreaInsets` и auxiliary top areas. На camera-housing display окно ограничено верхней полосой, а видимые hit regions имеют bounded width до 240 pt и привязаны к notch-facing edges left/right областей. На notchless display используется верхняя центральная полоса без искусственного notch gap.
- Добавлены bounded previews последних трёх occurrences, pending count без used items, Processing/error/reactivation markers и direction indicator. Expanded view переиспользует существующие cards, reorder, direction, retry, Reactivate и paste behavior.
- Hover и уход запускают переход на следующем проходе main queue без временной задержки. Click раскрывает сразу; accessibility action раскрывает и удерживает expanded state до явного Collapse. Возврат во время collapse reverses transition без промежуточного compact reopen. Mouse interaction hold удерживает expanded state до release; старые transitions инвалидируются generation token. Screen-parameter changes пересчитывают frame и tracking regions во всех active presentation phases и отменяют stale hover decisions.
- Изменения: `Sources/Qipli/UI/TopNotchHistoryShelf.swift`, `Sources/Qipli/UI/PlaceholderViews.swift`, `Sources/Qipli/UI/PanelController.swift`, `Tests/QipliTests/TopNotchHistoryShelfTests.swift`.
- Automated evidence: focused `TopNotchHistoryShelfTests` — 29 tests, 0 failures; полный SwiftPM suite — 255 tests, 0 failures, 5 skipped; unsigned universal Xcode Debug build (`arm64` + `x86_64`) succeeded; `git diff --check` passed. Покрыты camera/notchless geometry, bounded compact hit regions, presentation transitions, collapse re-entry, geometry/timer invalidation, mouse hold и accessibility hold. Финальный read-only subagent review: actionable findings отсутствуют.
- 2026-09-15 пользователь подтвердил полную ручную приёмку S033 и сообщил, что использует эту возможность несколько дней без проблем. Подтверждение относится к установленному приложению, runtime/display/accessibility matrix и полному пользовательскому пути. Это user-reported acceptance, а не новый автоматический прогон.
- S033 закрыт. Открытых verification gates по срезу не осталось; S034 разблокирован. Signing, notarization и Sparkle остаются отдельными release gates.
