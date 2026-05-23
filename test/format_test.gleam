import tinyimg/format

pub fn bytes_below_1k_test() {
  assert format.bytes(0) == "0 B"
  assert format.bytes(1) == "1 B"
  assert format.bytes(1023) == "1023 B"
}

pub fn bytes_kb_test() {
  assert format.bytes(1024) == "1.0 KB"
  assert format.bytes(1536) == "1.5 KB"
  assert format.bytes(1_048_575) == "1024.0 KB"
}

pub fn bytes_mb_test() {
  assert format.bytes(1_048_576) == "1.0 MB"
  assert format.bytes(1_572_864) == "1.5 MB"
}

pub fn bytes_gb_test() {
  assert format.bytes(1_073_741_824) == "1.0 GB"
  assert format.bytes(2_147_483_648) == "2.0 GB"
}

pub fn signed_percent_shrink_test() {
  // 1000 -> 750 is -25%
  assert format.signed_percent(1000, 750) == "-25%"
}

pub fn signed_percent_grow_test() {
  // 1000 -> 1200 is +20%
  assert format.signed_percent(1000, 1200) == "+20%"
}

pub fn signed_percent_zero_before_test() {
  assert format.signed_percent(0, 100) == "0%"
}

pub fn signed_percent_equal_test() {
  assert format.signed_percent(1000, 1000) == "+0%"
}

pub fn duration_ms_subsecond_test() {
  assert format.duration_ms(0) == "0 ms"
  assert format.duration_ms(750) == "750 ms"
}

pub fn duration_ms_seconds_test() {
  assert format.duration_ms(1000) == "1.0 s"
  assert format.duration_ms(2500) == "2.5 s"
}

pub fn duration_ms_minutes_test() {
  assert format.duration_ms(60_000) == "1m 0s"
  assert format.duration_ms(125_000) == "2m 5s"
}

pub fn relative_basic_test() {
  assert format.relative("/foo/bar", "/foo/bar/baz.png") == "baz.png"
}

pub fn relative_nested_test() {
  assert format.relative("/foo", "/foo/a/b/c.png") == "a/b/c.png"
}

pub fn relative_no_match_test() {
  // Path outside root: returned untouched.
  assert format.relative("/foo", "/other/x.png") == "/other/x.png"
}

pub fn relative_root_only_test() {
  // The root path itself returned as-is (no trailing slash to strip).
  assert format.relative("/foo", "/foo") == "/foo"
}

pub fn contract_path_fits_test() {
  // Short paths pass through.
  assert format.contract_path("a/b.png", 20) == "a/b.png"
}

pub fn contract_path_drops_leading_segments_test() {
  // Long path with a short basename: keep the trailing segments that fit
  // behind a "…/" prefix.
  let path = "assets/heroes/illustrations/big/banner.png"
  let out = format.contract_path(path, 28)
  assert out == "…/big/banner.png"
}

pub fn contract_path_keeps_filename_test() {
  // Even when only the basename fits, the filename is preserved.
  let path = "assets/heroes/big/banner.png"
  let out = format.contract_path(path, 14)
  assert out == "…/banner.png"
}

pub fn contract_path_middle_truncates_filename_test() {
  // If the filename alone exceeds the budget, middle-truncate it.
  let path = "very-long-image-name-that-is-too-wide.png"
  let out = format.contract_path(path, 20)
  // Length must be at most 20 (grapheme count) and contain the ellipsis.
  assert string_length(out) == 20
  assert contains(out, "…")
}

pub fn contract_path_zero_budget_test() {
  assert format.contract_path("a/b.png", 0) == ""
}

pub fn contract_path_tiny_budget_test() {
  // Budget of 1 char: just the first 1 grapheme of the basename.
  let out = format.contract_path("very-long-name.png", 1)
  assert string_length(out) == 1
}

@external(erlang, "string", "length")
fn string_length(s: String) -> Int

fn contains(haystack: String, needle: String) -> Bool {
  case erl_split(haystack, needle) {
    [_] -> False
    _ -> True
  }
}

@external(erlang, "string", "split")
fn erl_split(s: String, sep: String) -> List(String)
