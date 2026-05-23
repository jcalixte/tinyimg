import gleam/int
import gleam/list
import gleam/string
import simplifile
import tinyimg/scan.{type Candidate, Jpg, Png}

@external(erlang, "tinyimg_ffi", "unique_id")
fn unique_id() -> Int

fn fixture_root() -> String {
  "/tmp/tinyimg-scan-test-" <> int.to_string(unique_id())
}

fn touch(path: String) -> Nil {
  let _ = simplifile.write(to: path, contents: "x")
  Nil
}

fn make_dir(path: String) -> Nil {
  let _ = simplifile.create_directory_all(path)
  Nil
}

fn cleanup(root: String) -> Nil {
  let _ = simplifile.delete(root)
  Nil
}

fn paths(cs: List(Candidate)) -> List(String) {
  cs |> list.map(fn(c) { c.path })
}

pub fn finds_image_extensions_test() {
  let root = fixture_root()
  make_dir(root)
  touch(root <> "/a.png")
  touch(root <> "/b.jpg")
  touch(root <> "/c.jpeg")
  touch(root <> "/d.txt")
  touch(root <> "/no-ext")

  let found = scan.scan(root)
  let names =
    found
    |> paths
    |> list.map(fn(p) {
      case string.split(p, "/") |> list.last {
        Ok(n) -> n
        Error(_) -> p
      }
    })
    |> list.sort(string.compare)

  assert names == ["a.png", "b.jpg", "c.jpeg"]
  cleanup(root)
}

pub fn case_insensitive_test() {
  let root = fixture_root()
  make_dir(root)
  touch(root <> "/upper.PNG")
  touch(root <> "/mixed.Jpg")

  let found = scan.scan(root)
  assert list.length(found) == 2
  cleanup(root)
}

pub fn skips_dot_entries_test() {
  let root = fixture_root()
  make_dir(root)
  touch(root <> "/visible.png")
  touch(root <> "/.hidden.png")
  make_dir(root <> "/.git")
  touch(root <> "/.git/inside.png")

  let found = scan.scan(root)
  assert list.length(found) == 1
  cleanup(root)
}

pub fn recursive_test() {
  let root = fixture_root()
  make_dir(root <> "/nested/deep")
  touch(root <> "/top.png")
  touch(root <> "/nested/mid.png")
  touch(root <> "/nested/deep/bottom.png")

  let found = scan.scan(root)
  assert list.length(found) == 3
  cleanup(root)
}

pub fn detects_formats_test() {
  let root = fixture_root()
  make_dir(root)
  touch(root <> "/a.png")
  touch(root <> "/b.jpg")
  touch(root <> "/c.jpeg")

  let found = scan.scan(root)
  let formats = list.map(found, fn(c) { c.format })
  assert list.contains(formats, Png)
  assert list.contains(formats, Jpg)
  // exactly one Png and two Jpgs (jpg + jpeg)
  let png_count = list.count(formats, fn(f) { f == Png })
  let jpg_count = list.count(formats, fn(f) { f == Jpg })
  assert png_count == 1
  assert jpg_count == 2
  cleanup(root)
}

pub fn empty_directory_test() {
  let root = fixture_root()
  make_dir(root)
  let found = scan.scan(root)
  assert found == []
  cleanup(root)
}

pub fn nonexistent_directory_test() {
  let found = scan.scan("/definitely/not/a/real/path/" <> int.to_string(unique_id()))
  assert found == []
}
