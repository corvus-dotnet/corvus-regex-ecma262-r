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
- Every function works over a character vector, and takes a pattern compiled once or as a string.
- A pattern without a backreference is matched in time proportional to its size times the text, and the single
  searches take a timeout, so neither a pattern nor a text from outside can make a program hang.

**Compliance.** Over the [ECMA-262 test data](https://github.com/corvus-dotnet/ecma262-regex-test-data) (what V8 says
about 117,889 patterns and 5,883,170 texts, `exec`, the global search, `replace` and `split` among them, and the
patterns and texts of test262, judged by test262's Unicode 17 answers where V8 has Unicode 16), through this package,
it gives 13,702,347 right answers and none wrong, refuses no valid pattern, accepts no invalid one and reaches no
limit. R's strings are UTF-8, so that is every answer about a text and a pattern an R string can hold: the data's
texts with a lone surrogate or a NUL character have no R form. CI runs the whole data.

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
| `ecma_regex(pattern, flags = "")` | Compiles a pattern as `new RegExp(pattern, flags)` does. |
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
| `ecma_version()` | The package's and the crate's versions. |

A match's row is the match, then each group, then one column for each group name (of the groups that share a name,
the one that took part); `NA` is a group that did not take part. There is `NA` (or `NULL` in a list) for an `NA`
string.

**Positions.** Positions are in characters from 1, as `nchar` counts them, an end inclusive, as `regexpr` gives them;
an empty match ends one character before it starts. Without `u` or `v` a match can take half of a character beyond the
Basic Multilingual Plane: its text then holds that half as U+FFFD, and its positions are the whole character's.

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
nightly on one runner with every other Corvus ECMA-262 engine.

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
