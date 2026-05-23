#!/usr/bin/env bash
# Install tinyimg globally on macOS / Linux.
#
# What this does:
#   1. Builds an Erlang shipment from the current checkout.
#   2. Copies it to ~/.local/share/tinyimg.
#   3. Drops a wrapper at ~/.local/bin/tinyimg.
#
# What this assumes:
#   - `gleam` and `erl` are on PATH at build time.
#   - `erl` will also be on PATH at runtime (so the wrapper can find it).
#     If your `erl` is in Homebrew's keg-only Cellar, either run
#     `brew link --force erlang` or add the Cellar bin to your shell rc.
#   - $HOME/.local/bin is on PATH at runtime (the script prints a warning
#     if it isn't).

set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly SHIP_SRC="$REPO_DIR/build/erlang-shipment"
readonly SHIP_DST="$HOME/.local/share/tinyimg"
readonly BIN_DST="$HOME/.local/bin/tinyimg"

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: '$1' not found on PATH" >&2
    exit 1
  fi
}

require gleam
require erl

echo "==> Building Erlang shipment"
cd "$REPO_DIR"
gleam export erlang-shipment >/dev/null

if [[ ! -d "$SHIP_SRC" ]]; then
  echo "error: expected shipment at $SHIP_SRC, not found" >&2
  exit 1
fi

echo "==> Installing shipment to $SHIP_DST"
mkdir -p "$(dirname "$SHIP_DST")"
rm -rf "$SHIP_DST"
cp -R "$SHIP_SRC" "$SHIP_DST"

echo "==> Writing wrapper to $BIN_DST"
mkdir -p "$(dirname "$BIN_DST")"
cat > "$BIN_DST" <<'EOF'
#!/usr/bin/env bash
exec "$HOME/.local/share/tinyimg/entrypoint.sh" run "$@"
EOF
chmod +x "$BIN_DST"

echo "==> Done"

if ! printf '%s' ":$PATH:" | grep -q ":$HOME/.local/bin:"; then
  echo
  echo "warning: $HOME/.local/bin is not on your PATH."
  echo "         Add to your shell rc:"
  echo "           export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo
echo "Try it:  tinyimg --version"
