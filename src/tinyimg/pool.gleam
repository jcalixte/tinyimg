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

/// Spawns a coordinator and `worker_count` workers to optimize `candidates`.
/// Each `FileResult` is wrapped via `on_result` and sent to `target`. When
/// all workers have exited (queue drained or cancelled), the coordinator
/// sends `on_drained()` to `target` and exits.
///
/// Returns a control Subject. Send `Cancel` to stop scheduling new files.
///
/// The control subject is owned by the coordinator process. The caller may
/// send messages to it from anywhere.
pub fn start(
  candidates candidates: List(Candidate),
  toolset toolset: Toolset,
  workers worker_count: Int,
  target target: Subject(target_msg),
  on_result on_result: fn(FileResult) -> target_msg,
  on_drained on_drained: fn() -> target_msg,
) -> Subject(Control) {
  // The control subject must be owned by the coordinator process so it can
  // selector_receive on it. We create it ahead of time by exchanging through
  // a bootstrap subject: the coordinator creates control and sends it back.
  let bootstrap: Subject(Subject(Control)) = process.new_subject()

  let _ = process.spawn(fn() {
    let control: Subject(Control) = process.new_subject()
    let coord: Subject(WorkerSignal) = process.new_subject()
    process.send(bootstrap, control)

    let total = list.length(candidates)
    case total {
      0 -> {
        process.send(target, on_drained())
        Nil
      }
      _ -> {
        let n = clamp_workers(worker_count, total)
        list.repeat(Nil, n)
        |> list.each(fn(_) {
          let _ = process.spawn(fn() {
            worker_loop(coord, toolset, target, on_result)
          })
          Nil
        })
        coordinator_loop(
          queue: candidates,
          live: n,
          cancelled: False,
          coord:,
          control:,
          target:,
          on_drained:,
        )
      }
    }
  })

  // Block briefly for the coordinator to publish the control subject.
  case process.receive(bootstrap, 1000) {
    Ok(c) -> c
    Error(_) -> process.new_subject()
  }
}

fn clamp_workers(requested: Int, total: Int) -> Int {
  let at_least_one = case requested < 1 {
    True -> 1
    False -> requested
  }
  case at_least_one > total {
    True -> total
    False -> at_least_one
  }
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
  let reply: Subject(WorkerCommand) = process.new_subject()
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

type CoordEvent {
  WorkerSig(WorkerSignal)
  ControlMsg(Control)
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
      let selector =
        process.new_selector()
        |> process.select_map(coord, WorkerSig)
        |> process.select_map(control, ControlMsg)

      case process.selector_receive(selector, 5000) {
        Error(_) ->
          coordinator_loop(
            queue:,
            live:,
            cancelled:,
            coord:,
            control:,
            target:,
            on_drained:,
          )
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
        Ok(ControlMsg(Cancel)) ->
          coordinator_loop(
            queue:,
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
