#!/usr/bin/env bash
# Сборка Android-APK без Gradle. Запускать из корня репозитория:
#   tools/build_android.sh            # debug APK (MCP-мост включён, порт 9501 открыт)
#   tools/build_android.sh release    # release APK (мост отключён)
#
# Требуется установленный тулчейн (см. docs/DEVELOPMENT.md, раздел «Экспорт»).
# Пути по умолчанию — D:/Repos/CosmoToolchain; переопределяются переменными:
#   GODOT       — путь к консольной сборке Godot 4.7.2
#   JAVA_HOME   — JDK 17
#   ANDROID_SDK — Android SDK (platform-tools, build-tools;34.0.0, platforms;android-34)
# Для release нужен ключ: GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD.
set -euo pipefail

TOOLCHAIN="${TOOLCHAIN:-D:/Repos/CosmoToolchain}"
export JAVA_HOME="${JAVA_HOME:-$TOOLCHAIN/jdk/jdk-17.0.20.1+1}"
ANDROID_SDK="${ANDROID_SDK:-$TOOLCHAIN/android-sdk}"
MODE="${1:-debug}"
GODOT="${GODOT:-D:/Repos/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
OUT_DIR="build"
mkdir -p "$OUT_DIR"

case "$MODE" in
	debug)
		OUT="$OUT_DIR/CosmoTextGame.apk"
		FLAG="--export-debug"
		;;
	release)
		OUT="$OUT_DIR/CosmoTextGame-release.apk"
		FLAG="--export-release"
		: "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?нужен путь к release-keystore}"
		: "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?нужен алиас ключа}"
		: "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?нужен пароль ключа}"
		;;
	*)
		echo "Использование: $0 [debug|release]" >&2
		exit 2
		;;
esac

python tools/validate_content.py
"$GODOT" --headless --path . "$FLAG" "Android" "$(pwd)/$OUT"

echo
echo "Готово: $OUT"
if [ -n "${ANDROID_SDK:-}" ]; then
	"$ANDROID_SDK/build-tools/34.0.0/aapt.exe" dump xmltree "$OUT" AndroidManifest.xml | grep -q "screenOrientation.*0x1" \
		&& echo "Ориентация проверена: portrait" \
		|| { echo "Ошибка: APK собран не в portrait-ориентации" >&2; exit 1; }
	"$ANDROID_SDK/build-tools/34.0.0/apksigner.bat" verify "$OUT" && echo "Подпись проверена"
fi
