#!/usr/bin/env bash
#
# Собирает готовое Keyly.app и кладёт его в /Applications.
#
# ЗАЧЕМ СКРИПТ, А НЕ Xcode → Product → Archive: из Xcode собрать НЕЛЬЗЯ, и это не лень.
#
# При сборке «для любого Mac» берётся ARCHS_STANDARD = arm64 + x86_64, а FluidAudio под
# x86_64 не компилируется вовсе — Swift не даёт там `Float16` («Value of type 'Float16' has
# no member 'bitPattern'»). Прибить архитектуру настройкой проекта НЕДОСТАТОЧНО: `ARCHS` из
# pbxproj действует только на таргет Keyly, а SPM-зависимости — отдельные проекты, и до них
# он не доходит. Проверено прогоном: `xcodebuild archive` без аргументов → ARCHIVE FAILED с
# теми же четырьмя ошибками, притом что x86_64-сборок самого таргета в логе ноль.
#
# Ограничивает архитектуру ТОЛЬКО запрос сборки — то есть аргументы ниже. Поэтому путь к
# .app один: этот скрипт.
#
# Запуск:  ./scripts/build-app.sh          → /Applications/Keyly.app
#          ./scripts/build-app.sh ~/Desktop → положить в другое место
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-/Applications}"
DERIVED="$ROOT/build-rel"

cd "$ROOT"

echo "▶ Сборка Release (arm64)…"
# ARCHS/ONLY_ACTIVE_ARCH — аргументами командной строки, а не из проекта: только так они
# доходят до SPM-пакетов. `-destination generic/platform=macOS` — тот же запрос, что делает
# Xcode при Archive, то есть проверяем именно тот путь, на котором владелец и споткнулся.
xcodebuild -project Keyly.xcodeproj \
           -scheme Keyly \
           -configuration Release \
           -destination 'generic/platform=macOS' \
           -derivedDataPath "$DERIVED" \
           ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
           build 2>&1 | tail -3

APP="$DERIVED/Build/Products/Release/Keyly.app"
if [ ! -d "$APP" ]; then
  echo "✗ Сборка не дала .app — смотри вывод выше"
  exit 1
fi

# Проверяем то, ЧТО ПОЛУЧИЛОСЬ, а не то, что заказывали: универсальный бинарь означал бы,
# что настройка архитектуры где-то перебита, и следующая сборка снова упрётся в FluidAudio.
ARCHS_OUT="$(lipo -archs "$APP/Contents/MacOS/Keyly")"
if [ "$ARCHS_OUT" != "arm64" ]; then
  echo "✗ Бинарь собран под «${ARCHS_OUT}», а ожидался только arm64."
  echo "  Проверь ARCHS в настройках проекта — x86_64 ломает FluidAudio."
  exit 1
fi

# Закрываем ВСЕ копии Keyly, а не только целевую.
#
# Раньше здесь стоял pkill по одному пути — и это стоило владельцу часа диагностики: у него
# параллельно жила сборка из DerivedData с тем же bundle id, она перехватывала те же
# глобальные хоткеи, и «микрофон вырубается через 10 секунд» происходило в НЕЙ, а не в том
# .app, который мы только что собрали. Логи это доказали: PID 2225 — DerivedData, PID 6081 —
# /Applications, и записи в них шли по-разному.
if pgrep -f "Keyly.app/Contents/MacOS/Keyly" >/dev/null 2>&1; then
  echo "▶ Закрываю запущенные копии Keyly:"
  pgrep -af "Keyly.app/Contents/MacOS/Keyly" | sed 's|^|    |' | cut -c1-100
  pkill -f "Keyly.app/Contents/MacOS/Keyly" || true
  sleep 1
fi

echo "▶ Кладу в ${DEST}…"
rm -rf "$DEST/Keyly.app"
cp -R "$APP" "$DEST/Keyly.app"

echo
echo "✓ Готово: $DEST/Keyly.app ($ARCHS_OUT)"
codesign -dv "$DEST/Keyly.app" 2>&1 | grep -E "^Identifier|^TeamIdentifier" | sed 's/^/  /'
echo
# Про права говорим ровно то, что можем проверить. Раньше здесь стояло утверждение
# «доступ ОБЯЗАТЕЛЬНО надо выдать заново» — а прочитать TCC.db нельзя (её защищает SIP), то
# есть утверждение было недоказуемым и, судя по неизменной записи гранта, ещё и неверным.
echo "  Если хоткеи не срабатывают — Keyly сама покажет экран «дайте доступ»: она проверяет"
echo "  право раз в секунду. Тогда переоткрой Системные настройки → Конфиденциальность и"
echo "  безопасность → Универсальный доступ и включи Keyly заново."
