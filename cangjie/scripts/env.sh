#!/usr/bin/env bash
# Source this before any cjpm/build/run command in cangjie/.
# Works from bash and zsh; run it from cangjie/ or any directory below it.
if [ -n "${BASH_VERSION:-}" ]; then
  set -euo pipefail
fi

_textura_dir="$PWD"
while [ "$_textura_dir" != "/" ] && [ ! -f "$_textura_dir/cjpm.toml" ]; do
  _textura_dir="$(dirname "$_textura_dir")"
done
if [ ! -f "$_textura_dir/cjpm.toml" ]; then
  echo "env.sh: run from cangjie/ (no cjpm.toml found above $PWD)" >&2
  return 1 2>/dev/null || exit 1
fi
TEXTURA_CANGJIE_ROOT="$_textura_dir"
export TEXTURA_CANGJIE_ROOT

CJ_HOME="${CJ_HOME:-$HOME/.cjv}"
export PATH="$CJ_HOME/bin:$PATH"

# Puts the Cangjie runtime (libcangjie-runtime.so) and toolchain on PATH/LD_LIBRARY_PATH.
eval "$("$CJ_HOME/bin/cjv" envsetup)"

export LD_LIBRARY_PATH="$TEXTURA_CANGJIE_ROOT/third_party/cangjie-sdl/.sdl3:${LD_LIBRARY_PATH:-}"

# Host SDL must use X11. An inherited WAYLAND_DISPLAY makes SDL3 pick Wayland
# even under Xvfb; GTK/libdecor then loads libglycin and segfaults on window.show().
unset WAYLAND_DISPLAY
export SDL_VIDEODRIVER="${SDL_VIDEODRIVER:-x11}"
export TEXTURA_FONT="${TEXTURA_FONT:-Noto Sans CJK SC}"
