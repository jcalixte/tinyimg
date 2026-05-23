import gleam/float
import gleam/int
import gleam/list
import gleam/string

pub fn bytes(n: Int) -> String {
  let nf = int.to_float(n)
  case n {
    n if n < 1024 -> int.to_string(n) <> " B"
    n if n < 1_048_576 -> one_decimal(nf /. 1024.0) <> " KB"
    n if n < 1_073_741_824 -> one_decimal(nf /. 1_048_576.0) <> " MB"
    _ -> one_decimal(nf /. 1_073_741_824.0) <> " GB"
  }
}

pub fn signed_percent(before: Int, after: Int) -> String {
  case before {
    0 -> "0%"
    _ -> {
      let delta = int.to_float(after - before) /. int.to_float(before) *. 100.0
      let rounded = float.round(delta) |> int.to_string
      case delta <. 0.0 {
        True -> rounded <> "%"
        False -> "+" <> rounded <> "%"
      }
    }
  }
}

pub fn duration_ms(ms: Int) -> String {
  case ms {
    n if n < 1000 -> int.to_string(n) <> " ms"
    n if n < 60_000 -> one_decimal(int.to_float(n) /. 1000.0) <> " s"
    _ -> {
      let mins = ms / 60_000
      let secs = { ms - mins * 60_000 } / 1000
      int.to_string(mins) <> "m " <> int.to_string(secs) <> "s"
    }
  }
}

fn one_decimal(f: Float) -> String {
  let scaled = float.round(f *. 10.0)
  let whole = scaled / 10
  let frac = case scaled < 0 {
    True -> { 0 - scaled } - whole * -10
    False -> scaled - whole * 10
  }
  int.to_string(whole) <> "." <> int.to_string(frac)
}

pub fn relative(root: String, path: String) -> String {
  case string.starts_with(path, root <> "/") {
    True -> string.drop_start(path, string.length(root) + 1)
    False -> path
  }
}

/// Contract `path` so its rendered width is at most `max` characters.
///
/// Strategy, in order of preference:
///   1. If the path already fits, return it unchanged.
///   2. Drop leading path segments and prepend ".../", keeping as many
///      trailing segments as fit. The trailing filename is never dropped.
///   3. If even ".../<filename>" exceeds `max`, middle-truncate the
///      filename with "..." in the middle.
///   4. If `max` is very small (<= 3), return the first `max` chars.
pub fn contract_path(path: String, max: Int) -> String {
  case max <= 0 {
    True -> ""
    False -> case string.length(path) <= max {
      True -> path
      False -> shrink(path, max)
    }
  }
}

fn shrink(path: String, max: Int) -> String {
  let segments = string.split(path, "/")
  case segments {
    [] -> path
    _ -> {
      let base = case list.last(segments) {
        Ok(s) -> s
        Error(_) -> path
      }
      let base_len = string.length(base)
      let ellipsis = ".../"
      let ellipsis_len = 4

      case base_len + ellipsis_len > max {
        // Even ".../<filename>" doesn't fit — middle-truncate the filename.
        True -> middle_truncate(base, max)
        False -> {
          // Try to keep as many trailing segments as fit, with ".../" prefix.
          let budget = max - ellipsis_len
          let tail = build_tail(segments |> list.reverse, budget, "", True)
          ellipsis <> tail
        }
      }
    }
  }
}

fn build_tail(
  rev_segments: List(String),
  budget: Int,
  acc: String,
  is_first: Bool,
) -> String {
  case rev_segments {
    [] -> acc
    [s, ..rest] -> {
      let candidate = case is_first {
        True -> s
        False -> s <> "/" <> acc
      }
      case string.length(candidate) <= budget {
        True -> build_tail(rest, budget, candidate, False)
        False -> acc
      }
    }
  }
}

fn middle_truncate(s: String, max: Int) -> String {
  let len = string.length(s)
  case len <= max {
    True -> s
    False -> case max <= 3 {
      True -> string.slice(s, 0, max)
      False -> {
        let ellipsis = "..."
        let keep = max - 3
        let left = keep / 2 + keep % 2
        let right = keep - left
        string.slice(s, 0, left) <> ellipsis <> string.slice(s, len - right, right)
      }
    }
  }
}
