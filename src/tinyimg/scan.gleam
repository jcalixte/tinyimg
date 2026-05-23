import filepath
import gleam/list
import gleam/string
import simplifile

pub type Format {
  Png
  Jpg
}

pub type Candidate {
  Candidate(path: String, format: Format, size: Int)
}

/// Recursively walks `root`, returning matching image files.
/// Skips dot-entries when descending. Does not follow symlinks.
pub fn scan(root: String) -> List(Candidate) {
  walk(root, [])
  |> list.reverse
}

fn walk(dir: String, acc: List(Candidate)) -> List(Candidate) {
  case simplifile.read_directory(dir) {
    Error(_) -> acc
    Ok(entries) -> list.fold(entries, acc, fn(acc, name) { visit(dir, name, acc) })
  }
}

fn visit(parent: String, name: String, acc: List(Candidate)) -> List(Candidate) {
  case string.starts_with(name, ".") {
    True -> acc
    False -> {
      let full = filepath.join(parent, name)
      case simplifile.link_info(full) {
        Error(_) -> acc
        Ok(info) -> case simplifile.file_info_type(info) {
          simplifile.Symlink -> acc
          simplifile.Directory -> walk(full, acc)
          simplifile.File -> case detect_format(name) {
            Error(_) -> acc
            Ok(format) -> [Candidate(path: full, format: format, size: info.size), ..acc]
          }
          simplifile.Other -> acc
        }
      }
    }
  }
}

fn detect_format(name: String) -> Result(Format, Nil) {
  let lower = string.lowercase(name)
  case
    string.ends_with(lower, ".png"),
    string.ends_with(lower, ".jpg"),
    string.ends_with(lower, ".jpeg")
  {
    True, _, _ -> Ok(Png)
    _, True, _ -> Ok(Jpg)
    _, _, True -> Ok(Jpg)
    _, _, _ -> Error(Nil)
  }
}
