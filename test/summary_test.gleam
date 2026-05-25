import tinyimg/summary
import tinyimg/worker.{Failed, Optimized, Skipped}

pub fn empty_summary_test() {
  let s = summary.empty("/root")
  assert s.root == "/root"
  assert s.total == 0
  assert s.optimized == 0
  assert s.skipped == 0
  assert s.failed == 0
  assert s.saved == 0
  assert s.details == []
  assert s.cancelled == False
}

pub fn details_track_results_in_reverse_order_test() {
  let r1 = Optimized(path: "a", before: 100, after: 80)
  let r2 = Skipped(path: "b", size: 50)
  let r3 = Failed(path: "c", reason: "boom")
  let s =
    summary.empty("/r")
    |> summary.add(r1)
    |> summary.add(r2)
    |> summary.add(r3)
  assert s.details == [r3, r2, r1]
}

pub fn add_optimized_test() {
  let s =
    summary.empty("/r")
    |> summary.add(Optimized(path: "a.png", before: 1000, after: 800))
  assert s.total == 1
  assert s.optimized == 1
  assert s.saved == 200
  assert s.original == 1000
}

pub fn add_skipped_test() {
  let s =
    summary.empty("/r")
    |> summary.add(Skipped(path: "a.png", size: 500))
  assert s.total == 1
  assert s.skipped == 1
  assert s.saved == 0
  assert s.original == 500
}

pub fn add_failed_test() {
  let s =
    summary.empty("/r")
    |> summary.add(Failed(path: "bad.png", reason: "nope"))
  assert s.total == 1
  assert s.failed == 1
  assert s.failures == [#("bad.png", "nope")]
  // failures don't contribute to original or saved
  assert s.original == 0
}

pub fn mixed_summary_test() {
  let s =
    summary.empty("/r")
    |> summary.add(Optimized(path: "a", before: 1000, after: 700))
    |> summary.add(Skipped(path: "b", size: 200))
    |> summary.add(Failed(path: "c", reason: "boom"))
    |> summary.add(Optimized(path: "d", before: 500, after: 400))
  assert s.total == 4
  assert s.optimized == 2
  assert s.skipped == 1
  assert s.failed == 1
  assert s.saved == 400
  assert s.original == 1700
}

pub fn exit_code_clean_test() {
  let s = summary.empty("/r") |> summary.add(Optimized("a", 100, 80))
  assert summary.exit_code(s) == 0
}

pub fn exit_code_with_failures_test() {
  let s = summary.empty("/r") |> summary.add(Failed("a", "x"))
  assert summary.exit_code(s) == 1
}

pub fn exit_code_cancelled_test() {
  let s = summary.empty("/r") |> summary.set_cancelled
  assert summary.exit_code(s) == 1
}

pub fn set_elapsed_test() {
  let s = summary.empty("/r") |> summary.set_elapsed(1234)
  assert s.elapsed_ms == 1234
}
