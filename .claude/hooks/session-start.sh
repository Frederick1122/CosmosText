#!/bin/bash
# SessionStart-хук для Claude Code on the web: ставит headless Godot 4.7
# для смоук-теста. validate_content.py требует только Python 3 (уже есть).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
	exit 0
fi

GODOT_VERSION="4.7.2-stable"
GODOT_DIR="$HOME/.local/godot"
GODOT_BIN="$GODOT_DIR/Godot_v${GODOT_VERSION}_linux.x86_64"

if [ ! -x "$GODOT_BIN" ]; then
	mkdir -p "$GODOT_DIR"
	tmp_zip="$(mktemp --suffix=.zip)"
	curl -fsSL --retry 4 -o "$tmp_zip" \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
	unzip -oq "$tmp_zip" -d "$GODOT_DIR"
	rm -f "$tmp_zip"
	chmod +x "$GODOT_BIN"
fi

mkdir -p "$HOME/.local/bin"
ln -sf "$GODOT_BIN" "$HOME/.local/bin/godot"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
	echo "export PATH=\"$HOME/.local/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
	echo "export GODOT=\"$GODOT_BIN\"" >> "$CLAUDE_ENV_FILE"
	echo "export PYTHONIOENCODING=utf-8" >> "$CLAUDE_ENV_FILE"
fi

# Первичный импорт проекта (.godot/ кэш), чтобы смоук-тест не падал на неимпортированных ресурсах.
cd "${CLAUDE_PROJECT_DIR:-$(pwd)}"
if [ ! -d .godot ]; then
	"$GODOT_BIN" --headless --import --path . >/dev/null 2>&1 || true
fi
