import argv
import gleam/io
import gleam/list
import shellout
import simplifile
import tinyimg/gitignore
import tinyimg/plain
import tinyimg/scan.{type Candidate}
import tinyimg/tools
import tinyimg/tui

const version = "0.1.0"

pub type Action {
  Help
  Version
  Run(String)
  BadUsage(String)
}

@external(erlang, "tinyimg_ffi", "is_tty")
fn is_tty() -> Bool

pub fn main() -> Nil {
  let action = parse_args(argv.load().arguments)
  case action {
    Help -> {
      print_help()
      shellout.exit(0)
    }
    Version -> {
      io.println("tinyimg " <> version)
      shellout.exit(0)
    }
    BadUsage(msg) -> {
      io.println_error("tinyimg: " <> msg)
      shellout.exit(2)
    }
    Run(dir) -> case ensure_dir(dir) {
      Error(msg) -> {
        io.println_error("tinyimg: " <> msg)
        shellout.exit(2)
      }
      Ok(dir) -> dispatch(dir)
    }
  }
}

fn parse_args(args: List(String)) -> Action {
  case args {
    [] -> case simplifile.current_directory() {
      Ok(cwd) -> Run(cwd)
      Error(_) -> BadUsage("could not determine current working directory")
    }
    [arg] -> case arg {
      "-h" | "--help" -> Help
      "-V" | "--version" -> Version
      _ -> Run(arg)
    }
    _ -> BadUsage("too many arguments. Usage: tinyimg [DIR]")
  }
}

fn ensure_dir(dir: String) -> Result(String, String) {
  case simplifile.is_directory(dir) {
    Ok(True) -> Ok(dir)
    Ok(False) -> Error("not a directory: " <> dir)
    Error(_) -> Error("cannot read: " <> dir)
  }
}

fn dispatch(dir: String) -> Nil {
  let raw = scan.scan(dir)
  let outcome = gitignore.filter(dir, raw)
  let kept = case outcome {
    gitignore.Applied(kept:, ..) -> kept
    gitignore.NoRepo(kept) -> kept
    gitignore.NoGit(kept) -> kept
  }

  let formats =
    kept
    |> list.map(fn(c: Candidate) { c.format })
    |> list.unique

  case tools.probe(formats) {
    Error(tools.Missing(format)) -> {
      io.println_error("tinyimg: " <> tools.missing_hint(format))
      shellout.exit(3)
    }
    Ok(toolset) -> {
      let code = case is_tty() {
        True -> tui.run(dir, kept, toolset, outcome)
        False -> plain.run(dir, kept, toolset, outcome)
      }
      shellout.exit(code)
    }
  }
}

fn print_help() -> Nil {
  io.println(
    "tinyimg - losslessly optimize PNG and JPG images in a directory

USAGE
  tinyimg [DIR]

ARGS
  DIR    Directory to optimize. Defaults to the current working directory.

OPTIONS
  -h, --help     Print this help and exit
  -V, --version  Print version and exit

REQUIRED TOOLS (at least one per format you have)
  PNG:  oxipng (recommended) | optipng | pngcrush
  JPG:  jpegtran (recommended) | jpegoptim

BEHAVIOR
  Recursive walk under DIR. Entries beginning with '.' are skipped.
  Symlinks are not followed. If DIR is inside a git repo, files
  matched by .gitignore are skipped.

  Files are replaced atomically only if the optimized result is
  strictly smaller. Metadata (EXIF/ICC/XMP) is stripped.

EXIT CODES
  0  success (or cancelled with no failures)
  1  one or more files failed
  2  invalid usage or bad path
  3  required native tool missing",
  )
}
