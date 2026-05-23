# tinyimg

Losslessly optimize PNG and JPG images in a directory, with a minimal terminal UI.

```sh
tinyimg [DIR]
```

If `DIR` is omitted, the current working directory is used. Pixels are preserved exactly; metadata (EXIF, ICC, XMP) is stripped. Files are replaced atomically only when the optimized result is strictly smaller.

## Behavior

- Recursive walk under `DIR`. Entries beginning with `.` are skipped during descent.
- Symlinks are not followed.
- If `DIR` is inside a git work tree, files matched by `.gitignore` are skipped (uses `git check-ignore`).
- One worker per logical CPU core; native tools forced single-threaded.
- Two-stage quit: `q` once stops scheduling and drains in-flight work; `q` again forces exit.
- TTY vs non-TTY: full TUI on a terminal, plain one-line-per-file streaming when piped.

## Requirements

Gleam (BEAM target) and at least one native optimizer per format you have:

- PNG: `oxipng` (recommended) | `optipng` | `pngcrush`
- JPG: `jpegtran` (recommended) | `jpegoptim`

On macOS with Homebrew:

```sh
brew install oxipng jpeg-turbo  # provides oxipng + jpegtran
# or
brew install optipng jpegoptim
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | success (or cancelled with no failures) |
| 1 | one or more files failed, or run was cancelled |
| 2 | invalid usage or bad path |
| 3 | required native tool missing |

## Build & install

```sh
gleam run -- ./assets    # try it from the checkout
gleam test               # run unit tests
gleam build              # compile

./install.sh             # install globally as `tinyimg`
                         # (~/.local/bin/tinyimg + ~/.local/share/tinyimg/)
```

See [`docs/adr/0001-tui-for-a-batch-cli.md`](docs/adr/0001-tui-for-a-batch-cli.md) for the design decision behind the TUI.
