import gleam/list
import gleam/set.{type Set}
import gleam/string
import shellout
import tinyimg/scan.{type Candidate}

pub type Outcome {
  Applied(kept: List(Candidate), dropped: Int)
  NoRepo(kept: List(Candidate))
  NoGit(kept: List(Candidate))
}

/// Drops candidates matched by gitignore. If `root` isn't inside a git work
/// tree (or `git` isn't on PATH), returns the candidates unchanged.
pub fn filter(root: String, candidates: List(Candidate)) -> Outcome {
  case shellout.which("git") {
    Error(_) -> NoGit(kept: candidates)
    Ok(_) -> case inside_work_tree(root) {
      False -> NoRepo(kept: candidates)
      True -> {
        let ignored = collect_ignored(root, list.map(candidates, fn(c) { c.path }))
        let kept = list.filter(candidates, fn(c) { !set.contains(ignored, c.path) })
        let dropped = list.length(candidates) - list.length(kept)
        Applied(kept:, dropped:)
      }
    }
  }
}

fn inside_work_tree(dir: String) -> Bool {
  case
    shellout.command(
      run: "git",
      with: ["rev-parse", "--is-inside-work-tree"],
      in: dir,
      opt: [],
    )
  {
    Ok(output) -> string.trim(output) == "true"
    Error(_) -> False
  }
}

fn collect_ignored(dir: String, paths: List(String)) -> Set(String) {
  paths
  |> chunks(400)
  |> list.fold(set.new(), fn(acc, chunk) {
    case run_check_ignore(dir, chunk) {
      [] -> acc
      ignored -> list.fold(ignored, acc, set.insert)
    }
  })
}

fn run_check_ignore(dir: String, batch: List(String)) -> List(String) {
  // git check-ignore exits 0 if any paths are ignored (lists them on stdout),
  // 1 if none are ignored, 128 on real error. We need exit codes 0 or 1.
  case
    shellout.command(
      run: "git",
      with: ["check-ignore", "--no-index", "--", ..batch],
      in: dir,
      opt: [],
    )
  {
    Ok(output) -> parse_output(output)
    // shellout returns Error for any non-zero exit; map 1 (none ignored) to []
    Error(#(1, _)) -> []
    Error(#(_, _)) -> []
  }
}

fn parse_output(s: String) -> List(String) {
  s
  |> string.split("\n")
  |> list.filter_map(fn(line) {
    case string.trim(line) {
      "" -> Error(Nil)
      trimmed -> Ok(trimmed)
    }
  })
}

fn chunks(items: List(a), size: Int) -> List(List(a)) {
  case items {
    [] -> []
    _ -> {
      let #(head, rest) = list.split(items, size)
      [head, ..chunks(rest, size)]
    }
  }
}
