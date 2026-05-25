import filepath
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import shellout
import simplifile
import tinyimg/scan.{type Candidate, type Format, Jpg, Png}
import tinyimg/tools.{type Tool, type Toolset, ModifyInPlace, WriteToFile}

pub type FileResult {
  Optimized(path: String, before: Int, after: Int)
  Skipped(path: String, size: Int)
  Failed(path: String, reason: String)
}

@external(erlang, "tinyimg_ffi", "unique_id")
fn unique_id() -> Int

/// Process one candidate. Always returns a FileResult — never raises.
pub fn process(candidate: Candidate, toolset: Toolset) -> FileResult {
  case tool_for(candidate.format, toolset) {
    None ->
      Failed(path: candidate.path, reason: "no tool configured for format")
    Some(tool) -> do_process(candidate, tool)
  }
}

fn tool_for(format: Format, toolset: Toolset) -> Option(Tool) {
  case format {
    Png -> toolset.png
    Jpg -> toolset.jpg
  }
}

fn do_process(candidate: Candidate, tool: Tool) -> FileResult {
  let src = candidate.path
  let tmp = make_tmp_path(src)

  let invocation = tools.invocation(tool, src, tmp)

  case prepare(invocation, src, tmp) {
    Error(reason) -> {
      let _ = simplifile.delete(tmp)
      Failed(path: src, reason:)
    }
    Ok(Nil) ->
      case run(invocation) {
        Error(reason) -> {
          let _ = simplifile.delete(tmp)
          Failed(path: src, reason:)
        }
        Ok(Nil) -> finalize(src, tmp, candidate.size)
      }
  }
}

fn prepare(
  inv: tools.Invocation,
  src: String,
  tmp: String,
) -> Result(Nil, String) {
  case inv {
    WriteToFile(_, _) -> Ok(Nil)
    ModifyInPlace(_, _) ->
      case simplifile.copy_file(at: src, to: tmp) {
        Ok(_) -> Ok(Nil)
        Error(e) -> Error("copy failed: " <> simplifile.describe_error(e))
      }
  }
}

fn run(inv: tools.Invocation) -> Result(Nil, String) {
  let #(executable, args) = case inv {
    WriteToFile(e, a) -> #(e, a)
    ModifyInPlace(e, a) -> #(e, a)
  }
  case shellout.command(run: executable, with: args, in: ".", opt: []) {
    Ok(_) -> Ok(Nil)
    Error(#(code, output)) ->
      Error(
        executable_basename(executable)
        <> " exited "
        <> int.to_string(code)
        <> case output {
          "" -> ""
          s -> ": " <> trim_one_line(s)
        },
      )
  }
}

fn finalize(src: String, tmp: String, before: Int) -> FileResult {
  case simplifile.file_info(tmp) {
    Error(_) -> {
      let _ = simplifile.delete(tmp)
      Failed(path: src, reason: "tool produced no output")
    }
    Ok(info) ->
      case info.size {
        0 -> {
          let _ = simplifile.delete(tmp)
          Failed(path: src, reason: "tool produced empty output")
        }
        after if after >= before -> {
          let _ = simplifile.delete(tmp)
          Skipped(path: src, size: before)
        }
        after ->
          case simplifile.rename(at: tmp, to: src) {
            Ok(_) -> Optimized(path: src, before:, after:)
            Error(e) -> {
              let _ = simplifile.delete(tmp)
              Failed(
                path: src,
                reason: "rename failed: " <> simplifile.describe_error(e),
              )
            }
          }
      }
  }
}

fn make_tmp_path(src: String) -> String {
  let dir = filepath.directory_name(src)
  let ext = result.unwrap(filepath.extension(src), "tmp")
  let suffix = int.to_string(unique_id())
  filepath.join(dir, ".tinyimg-" <> suffix <> "." <> ext)
}

fn executable_basename(path: String) -> String {
  filepath.base_name(path)
}

fn trim_one_line(s: String) -> String {
  let trimmed = string.trim(s)
  case string.split_once(trimmed, "\n") {
    Ok(#(first, _)) -> first
    Error(_) -> trimmed
  }
}
