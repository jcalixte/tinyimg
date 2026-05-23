import gleam/float
import gleam/int
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
