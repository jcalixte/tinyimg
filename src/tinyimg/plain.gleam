import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/list
import tinyimg/format
import tinyimg/gitignore
import tinyimg/pool
import tinyimg/scan.{type Candidate}
import tinyimg/summary.{type Summary}
import tinyimg/tools.{type Toolset}
import tinyimg/worker.{type FileResult, Failed, Optimized, Skipped}

pub type Event {
  Result(FileResult)
  Drained
}

@external(erlang, "tinyimg_ffi", "system_cpus")
fn system_cpus() -> Int

@external(erlang, "tinyimg_ffi", "monotonic_ms")
fn monotonic_ms() -> Int

pub fn run(
  root: String,
  candidates: List(Candidate),
  toolset: Toolset,
  _gitignore_outcome: gitignore.Outcome,
) -> Int {
  // The pre-TUI status banner is printed by tinyimg.dispatch; we go straight
  // to the streaming per-file output.
  io.println("")

  let total = list.length(candidates)
  case total {
    0 -> {
      io.println("nothing to do.")
      0
    }
    _ -> run_loop(root, candidates, toolset, total)
  }
}

fn run_loop(
  root: String,
  candidates: List(Candidate),
  toolset: Toolset,
  total: Int,
) -> Int {
  let subject = process.new_subject()
  let start = monotonic_ms()

  let _control =
    pool.start(
      candidates:,
      toolset:,
      workers: system_cpus(),
      target: subject,
      on_result: Result,
      on_drained: fn() { Drained },
    )

  let final = drain(subject, summary.empty(root), root, total, 1)
  let final = summary.set_elapsed(final, monotonic_ms() - start)
  summary.print(final, total)
  summary.exit_code(final)
}

fn drain(
  subject: process.Subject(Event),
  acc: Summary,
  root: String,
  total: Int,
  index: Int,
) -> Summary {
  case process.receive_forever(subject) {
    Drained -> acc
    Result(r) -> {
      print_line(root, total, index, r)
      drain(subject, summary.add(acc, r), root, total, index + 1)
    }
  }
}

fn print_line(root: String, total: Int, index: Int, r: FileResult) -> Nil {
  let prefix =
    "["
    <> int.to_string(index)
    <> "/"
    <> int.to_string(total)
    <> "] "

  case r {
    Optimized(path, before, after) ->
      io.println(
        prefix
        <> format.relative(root, path)
        <> "  "
        <> format.bytes(before)
        <> " -> "
        <> format.bytes(after)
        <> "  "
        <> format.signed_percent(before, after),
      )
    Skipped(path, size) ->
      io.println(
        prefix
        <> format.relative(root, path)
        <> "  "
        <> format.bytes(size)
        <> "  skipped",
      )
    Failed(path, reason) ->
      io.println(
        prefix <> format.relative(root, path) <> "  FAIL  " <> reason,
      )
  }
}
