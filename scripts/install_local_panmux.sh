#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PANMUX_REPO=$(cd -- "$SCRIPT_DIR/.." && pwd)
SOURCE_DIR=${PANMUX_SOURCE_DIR:-$PANMUX_REPO}
INSTALL_ROOT=${PANMUX_INSTALL_ROOT:-$HOME/.local/opt/panmux}
BIN_DIR=${PANMUX_BIN_DIR:-$HOME/.local/bin}
APP_DIR=${PANMUX_APP_DIR:-$HOME/.local/share/applications}
ICON_DIR=${PANMUX_ICON_DIR:-$HOME/.local/share/icons}
APP_ID=io.github.forbidden_game.panmux

if [[ ! -d "$SOURCE_DIR/.git" ]]; then
  echo "error: source dir does not look like a git repo: $SOURCE_DIR" >&2
  exit 1
fi

if ! command -v zig >/dev/null 2>&1; then
  echo "error: zig not found in PATH" >&2
  exit 1
fi

revision=$(git -C "$SOURCE_DIR" rev-parse --short HEAD)
dirty=false
if [[ -n "$(git -C "$SOURCE_DIR" status --short)" ]]; then
  dirty=true
fi
if [[ "$dirty" == true ]]; then
  revision="${revision}-dirty"
fi
prefix="$INSTALL_ROOT/$revision"
current="$INSTALL_ROOT/current"
mkdir -p "$INSTALL_ROOT" "$BIN_DIR" "$APP_DIR" "$ICON_DIR"

if [[ "$dirty" == true || ! -x "$prefix/bin/ghostty" ]]; then
  echo "==> building panmux release into $prefix"
  (
    cd "$SOURCE_DIR"
    zig build -Doptimize=ReleaseFast --prefix "$prefix" install
  )
else
  echo "==> reusing existing build at $prefix"
fi

ln -sfn "$prefix" "$current"

cat > "$BIN_DIR/panmux" <<EOF
#!/usr/bin/env bash
set -euo pipefail
base="\${PANMUX_HOME:-$current}"
exe="\$base/bin/ghostty"
resources="\$base/share/ghostty"
if [[ ! -x "\$exe" ]]; then
  echo "error: panmux executable not found at \$exe" >&2
  exit 1
fi
for arg in "\$@"; do
  if [[ "\$arg" == --gtk-single-instance=* ]]; then
    exec env -u NO_COLOR GHOSTTY_RESOURCES_DIR="\$resources" "\$exe" "\$@"
  fi
done
exec env -u NO_COLOR GHOSTTY_RESOURCES_DIR="\$resources" "\$exe" --gtk-single-instance=false "\$@"
EOF
chmod +x "$BIN_DIR/panmux"

cat > "$BIN_DIR/panmuxctl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
base="\${PANMUX_HOME:-$current}"
exe="\$base/bin/panmuxctl"
if [[ ! -x "\$exe" ]]; then
  echo "error: panmuxctl not found at \$exe" >&2
  exit 1
fi
exec "\$exe" "\$@"
EOF
chmod +x "$BIN_DIR/panmuxctl"

cat > "$APP_DIR/panmux.desktop" <<EOF
[Desktop Entry]
Version=1.0
Name=panmux
Type=Application
Comment=Panmux terminal (Ghostty GTK fork)
TryExec=$BIN_DIR/panmux
Exec=$BIN_DIR/panmux
Icon=$APP_ID
Categories=System;TerminalEmulator;
Keywords=terminal;tty;pty;panmux;
StartupNotify=true
StartupWMClass=$APP_ID
Terminal=false
X-GNOME-UsesNotifications=true
EOF

if [[ -d "$current/share/icons" ]]; then
  mkdir -p "$ICON_DIR"
  cp -a "$current/share/icons/." "$ICON_DIR/"
fi

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -f -t "$ICON_DIR/hicolor" >/dev/null 2>&1 || true
fi

echo "==> installed panmux"
echo "source:   $SOURCE_DIR"
echo "revision: $revision"
echo "current:  $current"
echo "binary:   $BIN_DIR/panmux"
echo "ctl:      $BIN_DIR/panmuxctl"
echo "desktop:  $APP_DIR/panmux.desktop"
echo "icons:    $ICON_DIR"
