#!/usr/bin/env bash
# release.sh — bump version, tag, push, release, and update the Homebrew tap.
#
# Usage:
#   ./release.sh patch    # 1.1.0 → 1.1.1
#   ./release.sh minor    # 1.1.0 → 1.2.0
#   ./release.sh major    # 1.1.0 → 2.0.0
#
# Assumes:
#   - clean working tree on main
#   - `gh` authenticated; `origin` push URLs mirror to tangled + github
#   - tap cloned at ${TAP_DIR:-~/jclab/homebrew-tap}, clean main checkout
#
# On failure mid-flow: the script aborts. Bump+tag steps are reversible with
# `git tag -d vX.Y.Z && git push origin :refs/tags/vX.Y.Z && git reset --hard HEAD~1`.
# Once `gh release create` succeeds, recovery is `gh release delete vX.Y.Z`.

set -euo pipefail

bump="${1:-}"
case "$bump" in
  major|minor|patch) ;;
  *) echo "usage: $0 {major|minor|patch}" >&2; exit 2 ;;
esac

repo_dir="$(cd "$(dirname "$0")" && pwd)"
tap_dir="${TAP_DIR:-$HOME/jclab/homebrew-tap}"
formula="$tap_dir/Formula/tinyimg.rb"

for cmd in gleam gh git curl shasum; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "error: '$cmd' not on PATH" >&2; exit 1; }
done

cd "$repo_dir"
[[ -f gleam.toml ]] || { echo "error: gleam.toml missing in $repo_dir" >&2; exit 1; }
[[ -f "$formula" ]] || { echo "error: formula missing at $formula" >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "error: $repo_dir not clean" >&2; exit 1; }
[[ -z "$(git -C "$tap_dir" status --porcelain)" ]] || { echo "error: $tap_dir not clean" >&2; exit 1; }
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || { echo "error: not on main" >&2; exit 1; }
[[ "$(git -C "$tap_dir" rev-parse --abbrev-ref HEAD)" == "main" ]] || { echo "error: tap not on main" >&2; exit 1; }

current=$(grep -E '^version = ' gleam.toml | sed -E 's/version = "(.*)"/\1/')
IFS=. read -r major minor patch <<< "$current"
case "$bump" in
  major) major=$((major+1)); minor=0; patch=0 ;;
  minor) minor=$((minor+1)); patch=0 ;;
  patch) patch=$((patch+1)) ;;
esac
new="$major.$minor.$patch"
tag="v$new"

echo "==> $current → $new ($tag)"

sed -i.bak -E "s/^version = \".*\"/version = \"$new\"/" gleam.toml && rm gleam.toml.bak

echo "==> gleam build"
gleam build >/dev/null

git add gleam.toml
git commit -m "chore: bump version to $new"
git tag "$tag"

echo "==> git push origin main + $tag"
git push origin main
git push origin "$tag"

echo "==> gh release create $tag"
gh release create "$tag" --repo jcalixte/tinyimg --title "$tag" --generate-notes

echo "==> computing tarball sha256"
sha=$(curl -fsSL "https://github.com/jcalixte/tinyimg/archive/refs/tags/$tag.tar.gz" \
        | shasum -a 256 | awk '{print $1}')
echo "    sha256 = $sha"

echo "==> updating $formula"
sed -i.bak -E \
  -e "s|/v[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz|/$tag.tar.gz|" \
  -e "s/^  sha256 \"[^\"]*\"/  sha256 \"$sha\"/" \
  -e "s/\"[0-9]+\.[0-9]+\.[0-9]+\", shell_output/\"$new\", shell_output/" \
  "$formula"
rm "$formula.bak"

git -C "$tap_dir" add Formula/tinyimg.rb
git -C "$tap_dir" commit -m "tinyimg $new"
git -C "$tap_dir" push origin main

echo
echo "==> released $tag"
echo "    users can now run: brew update && brew upgrade tinyimg"
