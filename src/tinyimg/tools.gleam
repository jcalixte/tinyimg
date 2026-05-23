import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import shellout
import tinyimg/scan.{type Format, Jpg, Png}

pub type ToolName {
  Oxipng
  Optipng
  Pngcrush
  Jpegtran
  Jpegoptim
}

pub type Tool {
  Tool(name: ToolName, executable: String)
}

/// Resolved tools for the formats encountered in a scan.
pub type Toolset {
  Toolset(png: Option(Tool), jpg: Option(Tool))
}

pub type ProbeError {
  Missing(format: Format)
}

/// How a tool produces its output, given a source file `src` and a
/// pre-allocated temporary destination path `tmp`.
pub type Invocation {
  /// The tool reads `src` and writes the optimized bytes to `tmp`.
  /// Worker just runs the command, checks exit, compares sizes.
  WriteToFile(executable: String, args: List(String))
  /// The tool modifies its argument in place. Worker must first copy
  /// `src` to `tmp`, then run the tool on `tmp`.
  ModifyInPlace(executable: String, args: List(String))
}

const png_preference: List(ToolName) = [Oxipng, Optipng, Pngcrush]
const jpg_preference: List(ToolName) = [Jpegtran, Jpegoptim]

/// Probes PATH for the best available tool for each format present in the scan.
/// Returns an error if a format is encountered but no tool is available for it.
pub fn probe(needed: List(Format)) -> Result(Toolset, ProbeError) {
  let need_png = list.contains(needed, Png)
  let need_jpg = list.contains(needed, Jpg)

  use png <- result.try(resolve(need_png, png_preference, Png))
  use jpg <- result.try(resolve(need_jpg, jpg_preference, Jpg))

  Ok(Toolset(png:, jpg:))
}

fn resolve(
  needed: Bool,
  prefs: List(ToolName),
  format: Format,
) -> Result(Option(Tool), ProbeError) {
  case needed {
    False -> Ok(None)
    True -> case find_first(prefs) {
      Some(t) -> Ok(Some(t))
      None -> Error(Missing(format:))
    }
  }
}

fn find_first(prefs: List(ToolName)) -> Option(Tool) {
  case prefs {
    [] -> None
    [name, ..rest] -> case shellout.which(executable_name(name)) {
      Ok(path) -> Some(Tool(name:, executable: path))
      Error(_) -> find_first(rest)
    }
  }
}

pub fn executable_name(name: ToolName) -> String {
  case name {
    Oxipng -> "oxipng"
    Optipng -> "optipng"
    Pngcrush -> "pngcrush"
    Jpegtran -> "jpegtran"
    Jpegoptim -> "jpegoptim"
  }
}

pub fn missing_hint(format: Format) -> String {
  case format {
    Png -> "no PNG optimizer found on PATH. Install one of:\n  brew install oxipng  (recommended)\n  brew install optipng\n  brew install pngcrush"
    Jpg -> "no JPG optimizer found on PATH. Install one of:\n  brew install jpeg-turbo  (provides jpegtran, recommended)\n  brew install jpegoptim"
  }
}

/// Returns the appropriate Invocation strategy for a tool.
pub fn invocation(tool: Tool, src: String, tmp: String) -> Invocation {
  case tool.name {
    Oxipng -> WriteToFile(
      tool.executable,
      ["-o", "2", "--strip", "safe", "-t", "1", "--force", "--out", tmp, "--", src],
    )
    Optipng -> WriteToFile(
      tool.executable,
      ["-quiet", "-o2", "-strip", "all", "-out", tmp, "--", src],
    )
    Pngcrush -> WriteToFile(
      tool.executable,
      ["-q", "-rem", "alla", "-brute", "-new", src, tmp],
    )
    Jpegtran -> WriteToFile(
      tool.executable,
      ["-copy", "none", "-optimize", "-progressive", "-outfile", tmp, src],
    )
    // jpegoptim modifies in place — worker copies src → tmp first, then runs.
    Jpegoptim -> ModifyInPlace(
      tool.executable,
      ["--strip-all", "--all-progressive", "--quiet", tmp],
    )
  }
}
