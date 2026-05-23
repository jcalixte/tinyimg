import gleam/erlang/process.{type Subject}
import gleam/list
import tinyimg/scan.{type Candidate}
import tinyimg/tools.{type Toolset}
import tinyimg/worker.{type FileResult}

/// Control messages for the running pool.
pub type Control {
  /// Stop scheduling new files; let in-flight workers finish naturally.
  Cancel
}

/// Spawn a coordinator and `worker_count` workers to optimize `candidates`.
/// Each `FileResult` is wrapped via `on_result` and sent to `target`. When
/// all workers have exited (queue drained or cancelled), the coordinator
/// sends `on_drained()` to `target` and exits.
///
/// Returns a control Subject. Send `Cancel` to stop scheduling new files.
pub fn start(
  candidates candidates: List(Candidate),
  toolset toolset: Toolset,
  workers worker_count: Int,
  target target: Subject(target_msg),
  on_result on_result: fn(FileResult) -> target_msg,
  on_drained on_drained: fn() -> target_msg,
) -> Subject(Control) {
  let coord = process.new_subject()
  let control = process.new_subject()

  let _ = process.spawn(fn() {
    let total = list.length(candidates)
    case total {
      0 -> {
        process.send(target, on_drained())
        Nil
      }
      _ -> {
        // spawn workers
        let n = case worker_count < 1 {
          True -> 1
          False -> worker_count
        }
        let n = case n > total {
          True -> total
          False -> n
        }
        list.repeat(Nil, n) |> list.each(fn(_) {
          let _ = process.spawn(fn() {
            worker_loop(coord, toolset, target, on_result)
          })
          Nil
        })
        coordinator_loop(
          queue: candidates,
          live: n,
          cancelled: False,
          coord: coord,
          control: control,
          target: target,
          on_drained: on_drained,
        )
      }
    }
  })

  control
}

// ---------------------------------------------------------------------------
// Worker side
// ---------------------------------------------------------------------------

type WorkerCommand {
  Task(Candidate)
  Halt
}

fn worker_loop(
  coord: Subject(WorkerSignal),
  toolset: Toolset,
  target: Subject(target_msg),
  on_result: fn(FileResult) -> target_msg,
) -> Nil {
  let reply = process.new_subject()
  process.send(coord, Ready(reply))
  case process.receive(reply, 60_000) {
    Ok(Task(candidate)) -> {
      let result = worker.process(candidate, toolset)
      process.send(target, on_result(result))
      worker_loop(coord, toolset, target, on_result)
    }
    Ok(Halt) -> Nil
    Error(_) -> Nil
  }
}

// ---------------------------------------------------------------------------
// Coordinator side
// ---------------------------------------------------------------------------

type WorkerSignal {
  Ready(Subject(WorkerCommand))
}

fn coordinator_loop(
  queue queue: List(Candidate),
  live live: Int,
  cancelled cancelled: Bool,
  coord coord: Subject(WorkerSignal),
  control control: Subject(Control),
  target target: Subject(target_msg),
  on_drained on_drained: fn() -> target_msg,
) -> Nil {
  case live {
    0 -> {
      process.send(target, on_drained())
      Nil
    }
    _ -> {
      // Build a selector that watches both the coord (worker ready signals)
      // and the control channel (external cancel).
      let selector =
        process.new_selector()
        |> process.select_map(coord, fn(s) { WorkerSig(s) })
        |> process.select_map(control, fn(c) { ControlMsg(c) })

      case process.selector_receive(selector, 5000) {
        Error(_) -> {
          // Timeout — workers may be stuck on long-running tools. Just loop.
          coordinator_loop(
            queue:,
            live:,
            cancelled:,
            coord:,
            control:,
            target:,
            on_drained:,
          )
        }
        Ok(WorkerSig(Ready(reply))) -> case cancelled, queue {
          False, [first, ..rest] -> {
            process.send(reply, Task(first))
            coordinator_loop(
              queue: rest,
              live:,
              cancelled:,
              coord:,
              control:,
              target:,
              on_drained:,
            )
          }
          _, _ -> {
            process.send(reply, Halt)
            coordinator_loop(
              queue: [],
              live: live - 1,
              cancelled:,
              coord:,
              control:,
              target:,
              on_drained:,
            )
          }
        }
        Ok(ControlMsg(Cancel)) -> coordinator_loop(
          queue: queue,
          live:,
          cancelled: True,
          coord:,
          control:,
          target:,
          on_drained:,
        )
      }
    }
  }
}

type CoordEvent {
  WorkerSig(WorkerSignal)
  ControlMsg(Control)
}
