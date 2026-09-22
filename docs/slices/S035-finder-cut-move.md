---
id: S035
title: Вырезание файлов в Finder с индикацией в чёлке
depends_on:
  - S033
  - S025
covers:
  - FR-049
  - FR-050
  - BR-037
  - NFR-035
---

# S035: Вырезание файлов в Finder с индикацией в чёлке

## Пользовательский результат

Выделить файлы, нажать ⌘X, увидеть подготовленное перемещение в компактном окне у чёлки, перейти в другую папку и нажать ⌘V. Файлы остаются на исходном месте до вставки.

Пользователь подтвердил намерение добавить ⌘X для файлов и индикацию в мини-окне. Finder-only, ⌘V для назначения и правила ниже являются предложением планирования; вопрос о границе приложений задан пользователю. Статус находится только в [STATE.md](../STATE.md). Контракты: FR-049/FR-050/BR-037/NFR-035, технический раздел S035, D-046.

## Предлагаемая граница

- Первый вариант работает с одним или несколькими локальными файлами в Finder. Поддержку папок/packages, Desktop, сетевых и облачных locations определяет отдельная проверка до расширения scope.
- ⌘X создаёт одну временную Cut session для текущего выделения. Следующий подтверждённый ⌘X заменяет набор целиком; это не накопление Paste Stack.
- Подтверждено пользователем 2026-09-22: только compact presentation, без большого окна и раскрытия по hover/клику/VoiceOver. Слева значок вырезания или состояния, справа крестик отмены. Снизу bounded имя первого файла и количество остальных; ошибка или передача команды Finder заменяет имя коротким сообщением. Полная подсказка доступна через tooltip/VoiceOver. Панель не забирает фокус Finder.
- До вставки отображается «Готовы к перемещению». Во время подготовки допускается неопределённый индикатор. Проценты, «Перемещено» и успешное завершение требуют наблюдаемого подтверждения реальной файловой операции.
- Перемещение предлагается делегировать штатной команде Finder ⌥⌘V. Конфликты имён, права доступа, ошибка и отмена остаются в Finder. Qipli не выполняет собственное copy/delete и не обещает отмену уже отправленного перемещения.
- Cancel в панели снимает Cut intent, оставляя source files на месте. Escape отменяет только при взаимодействии с панелью, не забирает Escape у диалогов Finder. Закрытие приложения снимает intent, после relaunch session не восстанавливается.
- Новая внешняя запись в clipboard, History paste или запуск Paste Stack инвалидируют Cut intent до другой вставки. При активном Stack новый Cut не запускается, панель предлагает сначала завершить или отменить Stack. Два режима не владеют ⌘V одновременно.
- В других приложениях и в текстовых полях Finder ⌘X/⌘V сохраняют обычное поведение. Неопределённый focus/selection не даёт права подменять сочетания.
- После однократной отправки move command intent считается переданным Finder. Повторы не отправляют второе перемещение. UI может сообщить «Команда передана Finder», но не «Файлы перемещены». Если такой уровень индикации не отвечает запросу, реализация блокируется до выбора наблюдаемого progress API.

## Вне scope

Другие файловые менеджеры, файловая очередь Stack, drag-and-drop, собственный файловый движок, восстановление незавершённого перемещения после crash, сетевые операции Qipli, новые permissions без решения, показ фиктивного transfer progress.

## Обязательный platform probe до реализации

На synthetic временных файлах проверить, можно ли существующим Accessibility/event tap определить Finder file selection и отличить его от rename/search/location text field. Проверить tagged ⌘C для подготовки native Finder clipboard и tagged ⌥⌘V для назначения без переписывания private representations. Нельзя брать старые file URLs из clipboard как доказательство нового выделения.

Проверить freshness clipboard, смену focus между проверкой и dispatch, repeats, задержки Finder и invalidation. Подготовительная запись должна получить exact self-write changeCount до History poll, несмотря на то, что clipboard пишет Finder в ответ на Qipli. При неоднозначной корреляции session не создаётся; произвольные внешние copies не подавляются. Не читать clipboard внутри event-tap callback.

Отдельно проверить, что выбранный способ подтверждения результата различает успешное перемещение, пользовательскую отмену, частичный результат и ошибку. Если доступен только dispatch, сохранить честный dispatch-only UI и согласовать его границу. Наличие Apple shortcut не доказывает работу автоматизации или наблюдаемость прогресса.

## Acceptance criteria

- [ ] Один и несколько файлов проходят Finder → ⌘X → компактное окно → другая папка → ⌘V; до вставки source files существуют, после успешного перемещения Finder набор находится в назначении.
- [ ] Rename, search и другие text fields Finder, другие приложения, отсутствие выделения, stale clipboard и неопределённый AX state не запускают Cut и сохраняют штатный ввод.
- [ ] Компактное окно показывает имя/количество либо ошибку, значок слева и крестик справа. Hover, click и VoiceOver не раскрывают окно. Крестик отменяет pending intent; после dispatch только закрывает notice. Сохраняются nonactivation и camera-safe geometry.
- [ ] Cancel до dispatch, relaunch и новая clipboard запись снимают intent без удаления source files. In-flight подготовка старой session не восстанавливает её.
- [ ] Rapid repeats, смена focus и повторная вставка не отправляют второе move действие. После передачи Finder нет автоматического retry.
- [ ] Stack/Cut arbitration и History paste проверены. Вне явно допущенной Cut session обычный ⌘V сохраняет прежний контракт.
- [ ] Native conflict, permission denied, missing source, same-folder destination и отмена Finder не выдаются за успех. Cross-volume move проверяется отдельно до заявления поддержки.
- [ ] В History/Stack не появляется подготовительная Qipli copy; нет payload logs, новых persistent source bytes или удаления исходников при History clear.

## Verification

1. Выполнить platform probe выше и записать реальные ограничения. До его прохождения срез не переводить в ready для основной реализации.
2. Unit/integration проверки state machine, selection admission, focus/freshness, exact self-write suppression, repeats, cancellation и арбитража через fake adapters.
3. Installed-app Finder matrix на synthetic временных файлах: single/multi, две папки, конфликт, отмена, denied/missing source, rename/search, смена приложения, внешнее copy, Stack и History. Проверять файловый результат отдельно от dispatch.
4. S033 notch/notchless, external screen, hover, VoiceOver, Reduce Motion и отсутствие потери focus. Focused tests, full SwiftPM suite и development-signed Debug build после реализации.
5. Privacy scan, diff check и действующие release gates перед публичной поставкой.

## Implementation report

Реализация выполнена локально 2026-09-21, но срез ещё не переводится в `done` до установленной Finder matrix.

- Platform probe на synthetic local files: прямой Finder ⌘X сам по себе не дал наблюдаемого native move; tagged ⌘C из Finder и tagged ⌥⌘V в другой папке переместили файл штатно. Исходник оставался на месте до dispatch. API для подтверждения результата, прогресса, отмены и частичного результата в probe не найден, поэтому UI остаётся dispatch-only и сообщает только передачу команды Finder.
- Реализованы Finder-only admission через Accessibility metadata, non-consuming наблюдение ⌘X, exact file-URL correlation с pasteboard `changeCount`, точечное подавление только подтверждённой подготовительной self-write, invalidation внешней записью и одноразовый tagged ⌥⌘V.
- Добавлен отдельный Cut panel в Top Notch. С 2026-09-22 оставлена только compact presentation. Stack имеет приоритет над Cut; Cut не выполняет собственный copy/delete и не восстанавливается после relaunch.
- После передачи команды Finder панель автоматически скрывается через 0,7 секунды. Это подтверждение dispatch, не результата перемещения; защита от повторной вставки сохраняется. Новый Cut отменяет отложенное скрытие предыдущей панели. В compact presentation значок вырезания/состояния слева и крестик справа размещены по бокам аппаратной чёлки с дополнительными внешними отступами. Под верхней полосой добавлена строка высотой 28 pt с именем файла на всю доступную ширину; длинное имя сокращается в середине, сохраняя расширение. Отдельного счётчика сверху нет; для нескольких файлов одного выделения рядом с первым именем показано число остальных. На экранах без чёлки расположение такое же.
- Automated coverage: 10 focused Finder Cut tests проходят; full SwiftPM suite и universal Xcode Debug build проходят. Same-URL provenance нельзя полностью доказать публичным pasteboard/Accessibility API, поэтому остаётся bounded correlation (1 s, exact next changeCount, current Finder selection, non-Finder fail-closed). Установленная Finder/accessibility/display matrix остаётся verification gate.

### Уточнение компактной панели, 2026-09-22

По запросу пользователя удалены expanded Finder Cut view, hover/click/accessibility expansion и соответствующие анимации. Compact state symbol перенесён в левую верхнюю область, крестик в правую. Нижняя строка полностью отдана имени/количеству или status/error message. Полное пояснение ошибки доступно в tooltip и VoiceOver. Lifecycle отделён от раскрываемого Paste Stack; системный Cut/Move input-контракт не изменён.

Проверки: полный SwiftPM suite — 282 tests, 0 failures, 5 environment skips для pasteboard. Добавлены 3 regression tests compact lifecycle, stale dismissal, смены display geometry и status projection. Development-signed universal Debug build прошёл. Offscreen SwiftUI render на synthetic данных проверен для подготовки и ошибки; крестик виден в обоих состояниях. Встроенный semantic primary в error branch делал крестик невидимым, поэтому его цвет явно задан для существующей чёрной поверхности. Runtime-взаимодействие этой сборки ещё не проверено. Ручной smoke новой панели: hover/click без раскрытия, крестик до dispatch, ошибки вместо имени, VoiceOver и notch/notchless placement.
