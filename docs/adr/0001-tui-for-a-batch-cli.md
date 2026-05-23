# ADR 0001 — Use a shore TUI for a batch CLI

**Status:** accepted

## Context

tinyimg is a batch image optimizer: point it at a directory, it optimizes every PNG/JPG inside. The natural shape for such a tool is a plain CLI that streams progress lines to stdout — that is what most batch tools (ffmpeg, imagemin, every CI optimizer) do.

We chose instead to build an interactive Elm-Architecture TUI on top of [`shore`](https://hex.pm/packages/shore), with a progress bar, a running savings counter, and a tail of recent results. This is a surprising choice for a batch tool and worth recording so future readers don't undo it.

## Decision

For interactive runs (stdout is a TTY) we render a live TUI. For non-interactive runs (stdout piped, CI, redirected to a file) we fall back to plain one-line-per-file streaming with the same final summary block.

The TUI's `Model` holds counters, a running total of saved bytes, and a bounded tail of the most recent `FileResult`s. Worker BEAM processes optimize files in parallel and send `WorkerFinished(FileResult)` messages into the shore actor's update loop.

## Alternatives considered

1. **Plain-text only.** Smallest possible CLI. Reject: no visibility into progress on large directories, no live "saved bytes so far" feedback. Users will run this on folders of hundreds of images and want to see motion.
2. **Spinner / single progress bar with no per-file output.** Less code than the TUI. Reject: when a file fails or is skipped, the user has no signal until the final summary; the most informative line — "which file is currently being processed and what's happening to it" — is missing.
3. **Make the TUI optional behind a flag.** Reject for v1: branching forces us to maintain two output paths anyway (one for TTY, one for piped), and adding a third (opt-in TUI) only multiplies surface area without changing the cases that matter.

## Consequences

- **+** Live progress, savings counter, and recent-results tail give the user a clear picture without dumping log lines to stdout. The alt-screen buffer means the user's shell scrollback isn't polluted.
- **+** Worker processes communicating via typed `Msg` variants is a natural fit for BEAM and lets us add features (cancellation, force-quit) without rearchitecting.
- **−** ~150 LoC of view code and an extra dependency (`shore`) we wouldn't need for a plain CLI.
- **−** Two output paths to maintain (TUI vs plain). Mitigated by the fact that both share the `Summary` accumulator and the same printing logic for the final block — the divergence is only in the live progress.
- **−** Shore writes terminal control sequences to stdout; if a user accidentally pipes our output without us detecting it, the result is garbage. Our `tinyimg_ffi:is_tty/0` check guards against this.

## Reversibility

Medium. Ripping out shore is mechanical (delete `src/tinyimg/tui.gleam` and the `shore` dep, route the TTY branch to `plain.run`), but every place we wired in a `Msg` variant or a model field gets touched. Don't undo this without a stronger reason than "TUI feels heavy."
