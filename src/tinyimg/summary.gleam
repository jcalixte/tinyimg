import gleam/int
import gleam/io
import gleam/list
import gleam/string
import tinyimg/format
import tinyimg/worker.{type FileResult, Failed, Optimized, Skipped}

// Use \r\n so the line resets to column 0 even when the terminal was left
// in raw input mode by the shore TUI (its restore step does not revert
// cooked mode). Cooked mode also handles \r\n correctly, so this is safe
// in both plain and TUI exit paths.
fn outln(s: String) -> Nil {
  io.print(s <> "\r\n")
}

pub type Summary {
  Summary(
    root: String,
    total: Int,
    optimized: Int,
    skipped: Int,
    failed: Int,
    saved: Int,
    original: Int,
    failures: List(#(String, String)),
    cancelled: Bool,
    elapsed_ms: Int,
  )
}

pub fn empty(root: String) -> Summary {
  Summary(
    root:,
    total: 0,
    optimized: 0,
    skipped: 0,
    failed: 0,
    saved: 0,
    original: 0,
    failures: [],
    cancelled: False,
    elapsed_ms: 0,
  )
}

pub fn add(s: Summary, r: FileResult) -> Summary {
  case r {
    Optimized(_, before, after) ->
      Summary(
        ..s,
        total: s.total + 1,
        optimized: s.optimized + 1,
        saved: s.saved + before - after,
        original: s.original + before,
      )
    Skipped(_, size) ->
      Summary(
        ..s,
        total: s.total + 1,
        skipped: s.skipped + 1,
        original: s.original + size,
      )
    Failed(path, reason) ->
      Summary(
        ..s,
        total: s.total + 1,
        failed: s.failed + 1,
        failures: [#(path, reason), ..s.failures],
      )
  }
}

pub fn set_cancelled(s: Summary) -> Summary { Summary(..s, cancelled: True) }
pub fn set_elapsed(s: Summary, ms: Int) -> Summary { Summary(..s, elapsed_ms: ms) }

/// Print a multi-line summary block to stdout. Suitable both as the
/// post-TUI summary and as the end-of-stream block in plain mode.
pub fn print(s: Summary, planned_total: Int) -> Nil {
  outln("")
  case s.cancelled {
    True ->
      outln(
        "cancelled after "
        <> int.to_string(s.total)
        <> " of "
        <> int.to_string(planned_total)
        <> " files",
      )
    False -> outln(int.to_string(s.total) <> " files processed")
  }

  outln(
    "  optimized: "
    <> int.to_string(s.optimized)
    <> "   skipped: "
    <> int.to_string(s.skipped)
    <> "   failed: "
    <> int.to_string(s.failed),
  )

  case s.original {
    0 -> Nil
    _ ->
      outln(
        "  saved: "
        <> format.bytes(s.saved)
        <> " of "
        <> format.bytes(s.original)
        <> "  ("
        <> format.signed_percent(s.original, s.original - s.saved)
        <> ")",
      )
  }

  outln("  time:  " <> format.duration_ms(s.elapsed_ms))

  case s.failures {
    [] -> Nil
    failures -> {
      outln("")
      outln("failures:")
      list.reverse(failures)
      |> list.each(fn(f) {
        let #(path, reason) = f
        outln("  " <> format.relative(s.root, path) <> "  " <> reason)
      })
    }
  }
}

pub fn exit_code(s: Summary) -> Int {
  case s.failed > 0 || s.cancelled {
    True -> 1
    False -> 0
  }
}

/// Strip trailing newlines for one-line presentations.
pub fn one_line(text: String) -> String { string.trim(text) }
