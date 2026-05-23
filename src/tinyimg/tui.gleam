import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import shore
import shore/key
import shore/layout
import shore/style
import shore/ui
import tinyimg/format
import tinyimg/gitignore
import tinyimg/pool.{type Control}
import tinyimg/scan.{type Candidate}
import tinyimg/summary.{type Summary}
import tinyimg/tools.{type Toolset}
import tinyimg/worker.{type FileResult, Failed, Optimized, Skipped}

const recent_cap = 5

@external(erlang, "tinyimg_ffi", "system_cpus")
fn system_cpus() -> Int

@external(erlang, "tinyimg_ffi", "monotonic_ms")
fn monotonic_ms() -> Int

@external(erlang, "tinyimg_ffi", "terminal_columns")
fn terminal_columns() -> Int

/// Width budget for path text inside the box. Recomputed on every render so
/// the layout adapts when the terminal is resized.
///   - box outer width: 95% of terminal columns
///   - 2 cols for the box border
///   - 2 cols for the inner indent
///   - 22 cols reserved for "  <before> -> <after>  <pct>" (e.g. "1023 KB -> 999 KB  -2%")
fn path_budget() -> Int {
  let cols = terminal_columns()
  let inner = cols * 95 / 100 - 4 - 22
  case inner < 12 {
    True -> 12
    False -> inner
  }
}

pub type Msg {
  Boot(Subject(shore.Event(Msg)))
  WorkerFinished(FileResult)
  WorkersDrained
  QuitPressed
}

pub type QuitStage {
  Running
  Draining
  ForceQuitting
}

pub type Model {
  Model(
    root: String,
    planned_total: Int,
    started_at: Int,
    summary: Summary,
    recent: List(FileResult),
    stage: QuitStage,
    notice: String,
    control: Subject(Control),
    outer: Option(Subject(shore.Event(Msg))),
    outcome: Subject(Summary),
  )
}

pub fn run(
  root: String,
  candidates: List(Candidate),
  toolset: Toolset,
  outcome: gitignore.Outcome,
) -> Int {
  let total = list.length(candidates)
  case total {
    0 -> {
      summary.print(summary.empty(root), 0)
      0
    }
    _ -> run_tui(root, candidates, toolset, outcome, total)
  }
}

fn run_tui(
  root: String,
  candidates: List(Candidate),
  toolset: Toolset,
  outcome: gitignore.Outcome,
  total: Int,
) -> Int {
  let outcome_subject: Subject(Summary) = process.new_subject()
  let shore_exit: Subject(Nil) = process.new_subject()
  let notice = notice_text(outcome)

  let spec =
    shore.spec_with_subject(
      init: fn(self) {
        let control =
          pool.start(
            candidates:,
            toolset:,
            workers: system_cpus(),
            target: self,
            on_result: fn(r) { WorkerFinished(r) },
            on_drained: fn() { WorkersDrained },
          )
        let model =
          Model(
            root:,
            planned_total: total,
            started_at: monotonic_ms(),
            summary: summary.empty(root),
            recent: [],
            stage: Running,
            notice:,
            control:,
            outer: None,
            outcome: outcome_subject,
          )
        #(model, [])
      },
      view: view,
      update: update,
      exit: shore_exit,
      keybinds: shore.default_keybinds(),
      redraw: shore.on_timer(100),
    )

  case shore.start(spec) {
    Error(_) -> 2
    Ok(outer) -> {
      // Late-bind the outer subject into the model so update can trigger
      // shore.exit when work is done.
      process.send(outer, shore.send(Boot(outer)))

      // Wait for the shore actor to exit (Drained, q twice, or ctrl+x).
      let _ = process.receive_forever(shore_exit)

      // Read the final summary the actor sent to outcome_subject.
      let final = case process.receive(outcome_subject, 200) {
        Ok(s) -> s
        Error(_) -> summary.set_cancelled(summary.empty(root))
      }
      summary.print(final, total)
      summary.exit_code(final)
    }
  }
}

fn update(model: Model, msg: Msg) -> #(Model, List(fn() -> Msg)) {
  case msg {
    Boot(outer) -> #(Model(..model, outer: Some(outer)), [])

    WorkerFinished(r) -> {
      let recent = [r, ..take_first(model.recent, recent_cap - 1)]
      #(Model(..model, summary: summary.add(model.summary, r), recent:), [])
    }

    WorkersDrained -> {
      let final = finalize(model)
      process.send(model.outcome, final)
      schedule_exit(model.outer)
      #(model, [])
    }

    QuitPressed -> case model.stage {
      Running -> {
        process.send(model.control, pool.Cancel)
        #(Model(..model, stage: Draining), [])
      }
      Draining -> {
        let final = finalize(model) |> summary.set_cancelled
        process.send(model.outcome, final)
        schedule_exit(model.outer)
        #(Model(..model, stage: ForceQuitting), [])
      }
      ForceQuitting -> #(model, [])
    }
  }
}

fn finalize(model: Model) -> Summary {
  model.summary
  |> summary.set_elapsed(monotonic_ms() - model.started_at)
}

fn schedule_exit(outer: Option(Subject(shore.Event(Msg)))) -> Nil {
  case outer {
    Some(o) -> {
      let _ = process.spawn(fn() {
        process.sleep(80)
        process.send(o, shore.exit())
      })
      Nil
    }
    None -> Nil
  }
}

fn take_first(list: List(a), n: Int) -> List(a) {
  case n, list {
    n, _ if n <= 0 -> []
    _, [] -> []
    n, [first, ..rest] -> [first, ..take_first(rest, n - 1)]
  }
}

// ---------------------------------------------------------------------------
// View
// ---------------------------------------------------------------------------

fn view(model: Model) -> shore.Node(Msg) {
  let budget = path_budget()
  // Header gets a slightly bigger budget because it has no per-row sizes.
  let header_budget = budget + 18

  ui.box(
    [
      ui.text("tinyimg  " <> format.contract_path(model.root, header_budget)),
      case model.notice {
        "" -> ui.br()
        text -> ui.text_styled(text, Some(style.Cyan), None)
      },
      ui.br(),
      progress_row(model),
      ui.text(stats_line(model)),
      ui.br(),
      recent_section(model, budget),
      ui.br(),
      footer_row(model),
      ui.keybind(key.Char("q"), QuitPressed),
    ],
    None,
  )
  |> layout.center(style.Pct(95), style.Pct(90))
}

fn progress_row(model: Model) -> shore.Node(Msg) {
  let done = model.summary.total
  let bar = ui.progress(style.Pct(70), model.planned_total, done, style.Green)
  ui.row([
    bar,
    ui.text("  "),
    ui.text(int.to_string(done) <> " / " <> int.to_string(model.planned_total)),
  ])
}

fn stats_line(model: Model) -> String {
  "  optimized "
  <> int.to_string(model.summary.optimized)
  <> "  skipped "
  <> int.to_string(model.summary.skipped)
  <> "  failed "
  <> int.to_string(model.summary.failed)
  <> "  saved "
  <> format.bytes(model.summary.saved)
}

fn recent_section(model: Model, budget: Int) -> shore.Node(Msg) {
  case model.recent {
    [] -> ui.text("(waiting for first result...)")
    items -> ui.col([
      ui.text("recent"),
      ..list.map(items, fn(r) { recent_line(model.root, r, budget) })
    ])
  }
}

fn recent_line(root: String, r: FileResult, budget: Int) -> shore.Node(Msg) {
  let shown = fn(p) {
    format.contract_path(format.relative(root, p), budget)
  }
  case r {
    Optimized(path, before, after) ->
      ui.text(
        "  "
        <> shown(path)
        <> "   "
        <> format.bytes(before)
        <> " -> "
        <> format.bytes(after)
        <> "   "
        <> format.signed_percent(before, after),
      )
    Skipped(path, size) ->
      ui.text_styled(
        "  " <> shown(path) <> "   " <> format.bytes(size) <> "   skipped",
        Some(style.Yellow),
        None,
      )
    Failed(path, reason) ->
      ui.text_styled(
        "  " <> shown(path) <> "   FAIL  " <> reason,
        Some(style.Red),
        None,
      )
  }
}

fn footer_row(model: Model) -> shore.Node(Msg) {
  let stage_text = case model.stage {
    Running -> ""
    Draining -> "  draining... press q again to force exit"
    ForceQuitting -> "  exiting..."
  }
  ui.row([
    ui.text("q  quit"),
    ui.text_styled(stage_text, Some(style.Yellow), None),
  ])
}

fn notice_text(outcome: gitignore.Outcome) -> String {
  case outcome {
    gitignore.Applied(_, dropped) if dropped > 0 ->
      "gitignore: dropped " <> int.to_string(dropped) <> " path(s)"
    gitignore.NoRepo(_) -> "gitignore: skipped (not inside a git repo)"
    gitignore.NoGit(_) -> "gitignore: skipped (git not on PATH)"
    _ -> ""
  }
}
