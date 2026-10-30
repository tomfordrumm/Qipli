---
id: S039
title: Дизайн панелей и выбор края экрана
depends_on: [S010, S027, S033]
covers: [FR-056, BR-042, NFR-039]
---

# S039: Дизайн панелей и выбор края экрана

## Пользовательский результат

History и Paste Stack имеют согласованные отступы, контуры, карточки, управление и анимации. После пользовательского просмотра направление уточнено: чёрный жидкий остров вытекает из физического края экрана без внешнего зазора, включая промежуточные кадры. Одна настройка Settings → Appearance выбирает Top, Right, Bottom или Left для обеих панелей. Top остаётся default с текущей camera-safe привязкой. Боковые панели используют вертикальные карточки, нижняя горизонтальные. Finder Cut и correction feedback сохраняют свой верхний presentation.

## Контракт

FR-056, BR-042, NFR-039; D-059. Preference хранит только enum в UserDefaults, без payload и нового permission. Смена стороны применяется к открытым History/Stack без сброса session, query или selection. Ввод и typed paste остаются у существующих owners. Слева/справа History использует Up/Down, сверху/снизу Left/Right; Enter/Shift-Enter/Escape не меняются. Stack остаётся nonactivating, compact/expanded и accessibility hold сохраняются.

## Acceptance criteria

- [x] Общая настройка видна в Appearance, сохраняется после relaunch; отсутствующее/неизвестное значение означает Top.
- [x] Все четыре позиции соединены с physical screen edge, controls учитывают доступную область, Dock, camera band и ненулевые/отрицательные screen origins; compact и expanded controls доступны.
- [x] Открытые панели перемещаются без изменения History query/selection и Stack occurrences/state; stale transitions не возвращают прежний frame.
- [x] Боковые панели имеют вертикальный scroll и соответствующую keyboard navigation, остальные горизонтальные.
- [x] History search/filter/close не перекрываются; Stack Next/Used, reorder, direction, Reactivate и cancel остаются доступны.
- [x] Скругления, spacing и feedback согласованы; раскрытие начинается от выбранной стороны, выход короче входа. Пользователь принял итоговый дизайн и motion 2026-10-30.
- [ ] Отдельная installed Reduce Motion проверка подтверждает отключение пространственного morph.
- [x] Automated geometry/preferences/lifecycle regressions, full SwiftPM и unsigned build пройдены; synthetic renders проверены.
- [ ] Installed-app mouse/keyboard/VoiceOver/Reduce Motion/Increase Contrast, notch + external display/Dock/full-screen matrix выполнены отдельно; субъективная визуальная приёмка уже получена.

## Verification

Pure geometry на четырёх краях, Dock со всех сторон и нескольких origins; persistence defaults/relaunch; orientation и clipping. Existing focus/paste/Stack state machine tests. Native synthetic renders History/Stack/Settings, full suite и universal Debug/Release builds. Не читать реальный clipboard для визуальных fixtures. Release/signing/update не входят в этот этап.

## Implementation report

Реализовано локально 2026-10-29 в текущей feature-ветке вместе с уже существовавшим исправлением correction. Версия/build не менялись. Commit, push, установка и публикация не выполнялись. Operational status находится только в STATE.md.

- `PanelPreferences` передаётся из ApplicationShell в Settings и PanelController. Appearance содержит общий segmented picker Top/Right/Bottom/Left и анимированную схему выбранного положения; default и invalid value fallback Top проверены isolated UserDefaults/relaunch tests.
- `PanelEdgeGeometry` привязывает shell к physical screen edge, учитывает screen origins и Dock через внутренний reserved inset. Side panels имеют 360 pt usable width с вертикальными карточками; bottom сохраняет горизонтальную shelf. Compact Stack имеет 196×60 pt usable area. Top сохраняет camera-safe band.
- Общие radii/spacing/motion tokens, 16 pt cards, единый вогнутый shell на всех краях, мягкое accent selection, единая 30 pt область controls и hover/press feedback. History title/filter/search/close находятся в общем layout, отдельная накладка Favorites устранена. Stack показывает pending count, направление и доступные действия; button hit areas принадлежат ButtonStyle.
- Reveal 560 ms, collapse 320 ms, dismiss 260 ms; spread опережает lightly underdamped depth, attachment overscan сохраняет непрерывный контур, native order animation отключён; Reduce Motion сохраняет существующий короткий fade. Generation guards удерживают lifecycle при relocation; History не возобновляет dismiss/paste. Selection остаётся видимой после смены layout axis. Top inset разрешается только для connected display. Нативная форма карточек исправлена для provisional zero-size SwiftUI layout.
- Проверки: 382 SwiftPM tests, 0 failures, 0 skips; восемь новых regression tests для defaults/relaunch, Dock/origins/compact endpoints, flipped mask, lifecycle/accessibility hold, zero-size/resize и реального PanelController relocation. Последний тест использует synthetic History, mocked I/O и подтверждает отсутствие paste/copy dispatch; это не live external-target paste smoke.
- Native synthetic render pass: History и Stack во всех четырёх позициях, compact states, Appearance Light/Dark. Первая проверка выявила zero-size collection layout и смещение Settings preview, исправления подтверждены второй. Временный screenshot runner удалён из test target; примеры и runner сохранены локально в `/private/tmp/qipli-design-final/`. Реальные clipboard items не использовались в visual fixtures.
- Unsigned universal Debug/Release builds для arm64/x86_64 прошли. Артефакты в `/private/tmp/qipli-panel-design-build/Build/Products/`; compiler/runtime tests отделены от installed Accessibility acceptance.

Остаются installed mouse/keyboard/paste/VoiceOver, Reduce Motion/Increase Contrast, camera-housing/external display/disconnect/full-screen matrix и авторская оценка motion. Срез не объявлен done. Signing/notarization/Sparkle и совместная публикация с S037/S038 выполняются отдельным этапом по RELEASING.

### Dev-запуск для пользовательской проверки, 2026-10-29

По запросу пользователя выполнена universal Debug сборка с настроенной Apple Development identity. `codesign --verify --deep --strict` PASS. Запущена `/private/tmp/qipli-panel-design-build/Build/Products/Debug/Qipli Dev.app`, процесс подтверждён; других запущенных экземпляров Qipli перед запуском не обнаружено. Установленная Release не заменялась. Accessibility, визуальная приёмка и live interaction matrix этим запуском не подтверждены.

### Уточнение после пользовательского просмотра, 2026-10-29

Пользователь нашёл status icon и проверил Dev. Общее направление понравилось, но floating margins и одновременный morph не соответствовали эффекту «жидкого острова». D-059 уточнён: все края physical, чёрный shell непрерывен, controls учитывают Dock внутри. Status icon первого Dev оказался в области аппаратного выреза переполненной строки меню; это отдельно от геометрии панелей.

Контур теперь расширяется вдоль края раньше, чем в глубину, и втягивается в обратном порядке. Непрерывность контакта, reversal из промежуточного path и Dock-safe compact controls покрыты regression tests. Новый прогон: 384 SwiftPM tests, 0 failures, 0 skips; Apple Development-signed universal Debug arm64/x86_64 и strict codesign PASS. Synthetic History/Stack/compact/Settings renders и contact sheet промежуточных path находятся в `/private/tmp/qipli-liquid-preview/`. Два ограниченных визуальных прохода выполнены, во втором подтверждён clip схемы Settings; временный runner удалён из test target и сохранён в `/private/tmp/qipli-liquid-preview-runner.swift`. Dev перезапущена из прежнего пути для повторной пользовательской оценки. Реальный clipboard не использовался в fixtures; живое субъективное восприятие и display/accessibility matrix остаются открытыми. Release для этой итерации не пересобиралась.

### Исправление native-window seam и упругий финал, 2026-10-30

По предоставленной пользователем записи выполнен покадровый разбор начала раскрытия. Первая проверка только CGPath не покрывала автоматический compositor zoom AppKit. Воспроизведение на реальном NSPanel с synthetic black shell и magenta backdrop через ScreenCaptureKit подтвердило transient gap до 8 capture pixels при `.default` и 0 при `.none` на всех четырёх краях. После исправления повторная запись с production PanelWindowConfiguration подтвердила 0 во всех захваченных видимых кадрах. Захват ограничен тестовым приложением, пользовательские окна и clipboard в fixture не включены. Native probe и synthetic кадры сохранены в `/private/tmp/qipli-native-edge-probe/`, временный test runner удалён из target.

Общий PanelWindowConfiguration отключает системную orderFront/orderOut animation. Самостоятельный morph остаётся, depth теперь имеет около 1.23% extension и один мягкий возврат; 2% свободной глубины внутри окна предотвращают clipping. Reveal 560 ms, Reduce Motion сохраняет короткий fade. Regression checks фиксируют `.none` у обеих настоящих панелей, однократное ограниченное перерастяжение, отсутствие clipping и непрерывность attachment/reversal. Synthetic render matrix и промежуточные контуры проверены в `/private/tmp/qipli-elastic-preview/`.

Итог этой итерации: 385 SwiftPM tests, 0 failures, 0 skips; signed universal Debug arm64/x86_64 и strict codesign PASS. Dev пересобрана и перезапущена из прежнего локального пути. Версия/build остаются 1.0.17/18; Release не пересобиралась, публикация не выполнялась. Живая авторская оценка упругости и остальная accessibility/display matrix остаются открытыми.

### Пользовательская приёмка, 2026-10-30

Пользователь проверил финальную Dev после исправления native-window seam и настройки упругости: «теперь то, что надо». Визуальная приёмка дизайна и анимаций подтверждена. Запрошена локальная подготовка общего релиза с D-058. Это не подтверждает автоматически весь installed accessibility/display или correction matrix.

### Исправление карточек после смены стороны, 2026-10-30

Воспроизведён stale flow-layout cache при переключении существующей History между горизонтальным и вертикальным расположением: при viewport 320 pt рассчитанный itemSize уже составлял 316 pt, но layout attributes сохраняли ширину 1036 pt и x = −358 pt. Текст уходил за видимую область, изображения чрезмерно обрезались. Обновление itemSize вынесено из `prepare()` в resize/tile scroll view; перед синхронным resize задаются подходящие размеры, после него полностью инвалидируются flow metrics и attributes.

Новый regression test проверяет все 12 направленных переходов Top/Right/Bottom/Left на одном переиспользуемом collection для каждой исходной стороны: фактические attributes/frame, cross-axis bounds, текст, thumbnail frame и сохранение selection при неизменном snapshot. До исправления тест воспроизводил 66 assertion failures, после исправления проходит без invalid-size предупреждений AppKit. Полный SwiftPM suite вне sandbox: 386 tests, 0 failures, 0 skips. Нативные captures настоящей History с отдельной synthetic SQLite и загруженным искусственным изображением проверены для всех 12 переходов; runner, captures и contact sheet находятся в `/private/tmp/qipli-side-diagnosis/`. Пользовательская история и system clipboard в visual fixture не использовались. Исправление локальное, версия/build и установленное приложение не менялись; новый релиз не публиковался.

Для проверки пользователем пересобрана Apple Development-signed universal Debug arm64/x86_64 из текущих исходников с исправлением. `codesign --verify --deep --strict` PASS; bundle `com.qipli.app.dev`, локальная версия 1.0.17/build18. Запущена из прежнего `/private/tmp/qipli-panel-design-build/Build/Products/Debug/Qipli Dev.app`, процесс подтверждён после старта. Других работающих экземпляров Qipli перед запуском не было. Build log: `/private/tmp/qipli-side-diagnosis/dev-build.log`. Installed Release не заменялась; пользовательская проверка переключений ожидается.

Пользователь проверил эту Dev и подтвердил 2026-10-30, что переключения работают; разрешил публикацию исправления. Выбран следующий patch 1.0.19/build20 после проверки актуальных GitHub releases. Остальная accessibility/display matrix S039 остаётся открытой.
