# corvus-regex-ecma262 for R

Regular expressions with the grammar and the answers of ECMA-262, the `RegExp` of JavaScript, for R: the
[corvus-regex-ecma262](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs) Rust crate as the R package
`corvusregexecma262`, for R 4.2 and later.

- Every flag: `d`, `g`, `i`, `m`, `s`, `u`, `v` and `y`, with the grammar of each. Without `u` or `v` a pattern is
  read by the Annex B grammar and matched by UTF-16 code unit, as ECMA-262 matches it; with them, by code point. The
  `v` flag has nested classes, the difference and the intersection of classes, strings in a class and the properties
  of strings.
- ECMAScript 2025: lookbehind, named groups (and a name shared between alternatives), modifier groups such as
  `(?i:...)`, and every Unicode property ECMA-262 lists, from Unicode 17 tables the crate carries.
- A pattern answers as it does in a browser or Node, which R's `regexpr` family and stringi do not: `^` and `$`, `.`,
  `\d`, `\w`, `\b`, case folding, `\p{...}` and the rest read as JavaScript reads them. A pattern from JavaScript code,
  a JSON Schema or an OpenAPI document means here what it means there.
- Every function works over a character vector, and takes a pattern compiled once or as a string. It works as well
  over texts an R string cannot hold: a raw vector of UTF-8, which may hold a NUL, and an `ecma_utf16` of UTF-16 code
  units, which may hold lone surrogates, as a JavaScript string can.
- A pattern without a backreference is matched in time proportional to its size times the text, and a pattern can be
  given a match timeout, as a `Regex` of .NET can, which every function honours and which caps the backtracking memory
  too, so with a timeout neither a pattern nor a text from outside can make a program hang.

**Compliance.** Over the [ECMA-262 test data](https://github.com/corvus-dotnet/ecma262-regex-test-data) (what V8 says
about its patterns and texts, test262's patterns and `exec` calls, the global search, `replace` and `split` among them,
and texts of bytes that are not UTF-8, which it refuses), through this package over R's strings, raw vectors and
`ecma_utf16` code units, it gives every answer the data asks right and none wrong, refuses no valid pattern, accepts no
invalid one and reaches no limit. CI runs the whole data. (A text with a NUL, which an R string cannot hold, is asked as
a raw vector, and the answers over UTF-16 as code units.)

## Install

From R-universe:

```r
install.packages("corvusregexecma262", repos = c("https://corvus-dotnet.r-universe.dev", "https://cloud.r-project.org"))
```

R-universe has binary packages for Windows and macOS. A source install builds the native code, and needs
[Rust](https://rustup.rs) 1.89 or later.

## Getting started

```r
library(corvusregexecma262)

# The flags are those of new RegExp(pattern, flags).
date <- ecma_regex("(?<year>\\d{4})-(?<month>\\d{2})", "g")

ecma_test(c("due 2026-10", "none"), date)                    # TRUE FALSE
ecma_match("due 2026-10", date)[, "year"]                    # "2026"
ecma_locate("due 2026-10", date)                             # start 5, end 11

# Every match of a global search, as matchAll makes it.
ecma_match_all("2026-10, 2027-01", date)[[1]][, 1]           # "2026-10" "2027-01"

# replace replaces every match with the g flag, and the first without it; a function may give each replacement.
ecma_replace("2026-10, 2027-01", date, "$<month>/$1")        # "10/2026, 01/2027"
ecma_replace("2026-10", date, function(m) m[["month"]])      # "10"

# split splices in what the groups captured; a group that did not take part is NA.
ecma_split("a ; b;c", "\\s*(;)\\s*")                         # list(c("a", ";", "b", ";", "c"))
```

## The API

| | |
|---|---|
| `ecma_regex(pattern, flags = "", timeout = NULL)` | Compiles a pattern as `new RegExp(pattern, flags)` does. `timeout` is the match timeout in seconds (0 for none; `NULL` for the default). |
| `ecma_set_default_timeout(seconds)`, `ecma_default_timeout()` | The timeout of every pattern compiled without one: `NULL` (no limit) unless set. |
| `ecma_valid(pattern, flags = "")` | Whether each pattern is valid, without compiling it. |
| `ecma_test(x, regex, start = 1L, timeout = NULL)` | `RegExp.prototype.test` for each string, with `lastIndex` at `start` (at `start` alone with `y`). |
| `ecma_match(x, regex, start = 1L, timeout = NULL)` | The first match in each string and what each group captured (`exec`): a character matrix. |
| `ecma_locate(x, regex, group = 0L, start = 1L, timeout = NULL)` | Where the first match, or one of its groups, starts and ends: an integer matrix. |
| `ecma_match_all(x, regex)` | Every match of a global search in each string (`matchAll`): a list of matrices. |
| `ecma_locate_all(x, regex, group = 0L)` | Where each match, or one of its groups, starts and ends: a list of matrices. |
| `ecma_count(x, regex)` | How many matches a global search finds, without making them. |
| `ecma_replace(x, regex, replacement)` | `String.prototype.replace`: the first match, or every match with `g`, by a template or a function. |
| `ecma_replace_all(x, regex, replacement)` | `String.prototype.replaceAll`: every match. |
| `ecma_split(x, regex, limit = NULL)` | `String.prototype.split`: a list of character vectors. |
| `ecma_utf16(x)` | The UTF-16 code units of a string or of a raw vector of UTF-8, or code units given as numbers: a text with JavaScript's code units, which every function takes. `as.character` and `as.raw` turn one back. |
| `ecma_version()` | The package's and the crate's versions. |

A match's row is the match, then each group, then one column for each group name (of the groups that share a name,
the one that took part); `NA` is a group that did not take part. There is `NA` (or `NULL` in a list) for an `NA`
string.

**Timeouts.** A pattern has a match timeout, as a `Regex` of .NET has: `ecma_regex(pattern, flags, timeout = 1)`, or
for every pattern compiled after it `ecma_set_default_timeout(1)`. Every function that matches gives each of its
matches the timeout and raises `ecma_match_limit` at it; the single searches take a `timeout` of their own in its
place. Without a timeout (the default) a match has no limit of time or of memory, so a program that matches a pattern
or a text it did not write should set one.

**Positions.** Positions are in characters from 1, as `nchar` counts them, an end inclusive, as `regexpr` gives them;
an empty match ends one character before it starts. Without `u` or `v` a match can take half of a character beyond the
Basic Multilingual Plane: its text then holds that half as U+FFFD, and its positions are the whole character's.

**Texts that are not strings.** `x` may also be a raw vector (one text of UTF-8 bytes, which may hold a NUL),
an `ecma_utf16` (one text of UTF-16 code units, which may hold lone surrogates), or a list of them, `NULL` for a
missing text. Positions are then in bytes or in code units, and the texts of a match, a replacement and a split's
pieces come back in the form of the text (a match's row is a list matrix). A raw vector that is not UTF-8 is refused
with `ecma_encoding_error`, never read in part. A pattern may be a raw vector too, so that it can hold a NUL.

```r
ecma_locate(ecma_utf16(c(0x61, 0xD800, 0x62)), "\\uD800")        # start 2, end 2
ecma_replace(as.raw(c(0x61, 0x00, 0x62)), "\\0", "-")             # as.raw(c(0x61, 0x2d, 0x62))
```

**Strings.** A string marked as UTF-8, or in the native encoding of a UTF-8 session, is read in place (after a check
that it is UTF-8, which a long string has once while it is matched again and again); one in another encoding is
translated. A string marked as bytes is refused.

**Conditions.** `ecma_invalid_pattern`, `ecma_invalid_flags`, `ecma_pattern_too_large`, `ecma_match_limit` (a match
that reached its timeout or its cap on backtracking memory), `ecma_encoding_error` and `ecma_argument_error`, each an
`ecma_regex_error`.

## Benchmarks

The Industry workloads of dotnet/performance, this package against base R's `gregexpr` (PCRE2 and TRE), stringi (ICU)
and V8, are on the central page,
[corvus-oss.org/corvus-regex-ecma262-benchmarks](https://corvus-oss.org/corvus-regex-ecma262-benchmarks/), measured
nightly on one runner with the engines of every other source.

## Repository

- `R/`: the R API; `src/rust`: the native code (the crate, over R's C API); `man/`: the help; `tests/`: the tests.
- `tools/dataset.R`: the test-data runner (`Rscript tools/dataset.R <data> wrong.tsv`).
- `tools/bench`: the benchmark harness and the script the image runs; `Dockerfile`: the image the central page runs.

## Releasing

A release is a GitHub release tagged `v<version>`, the `Version` in `DESCRIPTION` (and the `version` in
`src/rust/Cargo.toml`). R-universe builds the latest release (its registry entry names the branch `*release`), and
the release publishes the harness image with the release's tag.

## Licence

Apache-2.0. See [LICENSE](LICENSE).
