import argv
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import shellout
import simplifile
import tinyimg/gitignore
import tinyimg/plain
import tinyimg/scan.{type Candidate}
import tinyimg/tools
import tinyimg/tui

const version = "1.2.0"

pub type Action {
  Help
  Version
  Run(dir: String, report: Bool)
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
    Run(dir, report) ->
      case ensure_dir(dir) {
        Error(msg) -> {
          io.println_error("tinyimg: " <> msg)
          shellout.exit(2)
        }
        Ok(dir) -> dispatch(dir, report)
      }
  }
}

fn parse_args(args: List(String)) -> Action {
  parse_args_loop(args, None, False)
}

fn parse_args_loop(
  args: List(String),
  dir: Option(String),
  report: Bool,
) -> Action {
  case args {
    [] -> finalize_run(dir, report)
    ["-h", ..] | ["--help", ..] -> Help
    ["-V", ..] | ["--version", ..] -> Version
    ["--report", ..rest] | ["-r", ..rest] ->
      parse_args_loop(rest, dir, True)
    [arg, ..rest] ->
      case dir {
        Some(_) -> BadUsage("too many arguments. Usage: tinyimg [-r] [DIR]")
        None -> parse_args_loop(rest, Some(arg), report)
      }
  }
}

fn finalize_run(dir: Option(String), report: Bool) -> Action {
  case dir {
    Some(d) -> Run(d, report)
    None ->
      case simplifile.current_directory() {
        Ok(cwd) -> Run(cwd, report)
        Error(_) -> BadUsage("could not determine current working directory")
      }
  }
}

fn ensure_dir(dir: String) -> Result(String, String) {
  case simplifile.is_directory(dir) {
    Ok(True) -> Ok(dir)
    Ok(False) -> Error("not a directory: " <> dir)
    Error(_) -> Error("cannot read: " <> dir)
  }
}

fn dispatch(dir: String, report: Bool) -> Nil {
  // Phase markers print one line per step so the user sees feedback even on
  // large trees where scan + gitignore each take a few seconds. These lines
  // live on the normal screen — the alt-screen TUI hides them while running
  // and they re-appear (above the final summary) on exit.
  io.println("tinyimg  " <> dir)

  io.println("  scanning...")
  let raw = scan.scan(dir)
  io.println("    found " <> int.to_string(list.length(raw)) <> " image(s)")

  io.println("  applying gitignore...")
  let outcome = gitignore.filter(dir, raw)
  let kept = case outcome {
    gitignore.Applied(kept:, ..) -> kept
    gitignore.NoRepo(kept) -> kept
    gitignore.NoGit(kept) -> kept
  }
  case outcome {
    gitignore.Applied(_, dropped) ->
      io.println("    dropped " <> int.to_string(dropped) <> " path(s)")
    gitignore.NoRepo(_) -> io.println("    skipped (not inside a git repo)")
    gitignore.NoGit(_) -> io.println("    skipped (git not on PATH)")
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
      io.println("  " <> int.to_string(list.length(kept)) <> " candidate(s)")
      let code = case is_tty() {
        True -> tui.run(dir, kept, toolset, outcome, report)
        False -> plain.run(dir, kept, toolset, outcome, report)
      }
      shellout.exit(code)
    }
  }
}

fn print_help() -> Nil {
  io.println(
    "tinyimg - losslessly optimize PNG and JPG images in a directory

USAGE
  tinyimg [-r] [DIR]

ARGS
  DIR    Directory to optimize. Defaults to the current working directory.

OPTIONS
  -r, --report   Print the full per-file report after the run
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
