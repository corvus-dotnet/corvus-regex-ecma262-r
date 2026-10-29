# corvusregexecma262 for R: design

An outline of the package as it is: what it offers, how it is built and why, and how it is tested and measured. The
[getting-started page](getting-started.md) shows how to use it.

## 1. What it is

An R package of regular expressions with ECMA-262's grammar and answers (ECMAScript 2025), vectorised over character
vectors, with raw vectors of UTF-8 and `ecma_utf16` code units beside them. It is a binding, through R's C API, to the
corvus-regex-ecma262 Rust crate, whose engine it uses as it is.

**Why ECMA-262.** JSON Schema, OpenAPI and many wire formats specify their patterns as ECMAScript regular
expressions. Base R's `regexpr` and `gsub` (PCRE2 or TRE) and stringi (ICU) have their own grammars and their own
meaning for `\d`, `\w`, `\s`, `.` and case folding, so a translation to them can never be exact. An engine that reads
ECMA-262 directly, held to V8's answers over a large data set (section 6), needs no translation.

## 2. Public surface

**Names.** Functions with the prefix `ecma_`, each taking the texts first, as base R's do: `ecma_test`, `ecma_match`
(a character matrix), `ecma_locate` (an integer matrix of starts and ends), `ecma_match_all`, `ecma_locate_all`,
`ecma_count`, `ecma_replace`, `ecma_replace_all` and `ecma_split`, the methods of a `RegExp`. Each takes a pattern
compiled once with `ecma_regex`, or a string compiled for the call, and the position as `start` where JavaScript keeps
`lastIndex`.

**Flags.** ECMA-262's, as a string, and nothing else.

**Edition and Unicode version.** By default a pattern is read with today's grammar (`edition = "current"`) and V8's
version of Unicode (`unicode_version = NULL`, 17 today). Either is overridden when the pattern is compiled,
independently: `"es2020"` is the grammar JSON Schema 2020-12 names, and the versions are 13, 17, 18 and `"latest"`.
Both are resolved when the pattern is compiled; a compiled pattern carries them as attributes.

**Errors.** Conditions of class `ecma_invalid_pattern`, `ecma_invalid_flags`, `ecma_pattern_too_large`,
`ecma_match_limit`, `ecma_encoding_error` and `ecma_argument_error`, each an `ecma_regex_error`.

**ECMA-262 algorithms.** `ecma_replace` substitutes as `GetSubstitution` does, replacing every match only with `g`, or
calls a function with each match; `ecma_replace_all` always replaces every match. `ecma_split` follows
`RegExp.prototype[Symbol.split]`, with `NA` for a group that did not take part.

**Input.** A string marked as UTF-8, or in the native encoding of a UTF-8 session, is read in place, after a check
that it is UTF-8; one in another encoding is translated, and one marked as bytes is refused. Positions over strings
are in characters from 1, an end inclusive, as `regexpr` gives them. A raw vector is one text of UTF-8 bytes (which may
hold a NUL, as an R string cannot), with positions in bytes; an `ecma_utf16` is one text of UTF-16 code units, lone
surrogates and all, with positions in code units. A missing string gives `NA`.

**Limits.** The crate's: a match timeout in seconds per pattern or for every pattern (`ecma_set_default_timeout`),
with a `timeout` of its own on the single searches; the size limits; and no stack overflow.

## 3. Engine

The engine is the Rust crate's, which
[its design](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs/blob/main/docs/design.md) describes. The
package's work is between R and the crate:

- **Errors without a long jump.** Every native entry point returns an R value. A failure comes back as a list of class
  `crer_native_error`, which the R layer raises as a condition, so no `Rf_error` long-jumps over the destructors of the
  Rust frames it would cross; a panic is caught at each entry point and returned the same way.
- **Handles.** A compiled pattern is an external pointer to the crate's compiled pattern, freed by R's finaliser, with
  the source, the flags and the settings as attributes.
- **Text and positions.** A string's UTF-8 is matched where R holds it; byte positions are turned into character
  positions from 1. Without u or v a match can end between the halves of a character beyond the Basic Multilingual
  Plane: its positions are then the whole character's, and its text holds the half as U+FFFD.
- **The fast path.** `ecma_test` and `ecma_count` over a compiled pattern and a character vector go straight to the
  native code, so a call costs little more than R's own call overhead.

## 4. The package

The package carries the native code in `src/rust`, which R CMD INSTALL builds with Cargo (Rust 1.89 or later, named in
`DESCRIPTION`'s SystemRequirements). R-universe builds it from the source at the latest release, with binary packages
for Windows and macOS. The help pages (`man/`) are the API reference, published as the package's manual on
R-universe.

## 5. Targets and layout

R 4.2 and later, on Linux (x64 and arm64), macOS and Windows.

- `R/`: the R API; `src/rust`: the native code (the crate, over R's C API); `man/`: the help; `tests/`: the tests.
- `tools/dataset.R`: the test-data runner; `tools/docs`: the getting-started runner; `tools/bench`: the benchmark
  harness; `tools/release`: the release scripts.

## 6. Testing

**The ECMA-262 test data.** [`ecma262-regex-test-data`](https://github.com/corvus-dotnet/ecma262-regex-test-data)
holds V8's answers: validity under each grammar, `test` answers, the positions of `exec`, the global search, `y`,
`replace` and `split`, and every `exec` call of test262. `tools/dataset.R` runs all of it through the installed package,
over strings, raw vectors and code units, with none wrong, refused or at a limit, and as the data's own scripts write it
for Unicode 13 and 18 and for ECMAScript 2020.

**Other tests.** `R CMD check` with no warning (but the one R 4.2's linker on Windows gives for every Rust object), on
Linux, macOS and Windows, on R 4.2, the release and R-devel, which runs the tests over every function; the native code's own tests, formatting and clippy; and the getting-started page's
examples, through the installed package.

## 7. Benchmarks

The harness image, `ghcr.io/corvus-dotnet/corvus-regex-ecma262-r`, runs the Industry workloads of
`dotnet/performance` over this package (UTF-8 and UTF-16), base R's `gregexpr` (PCRE2 and TRE), stringi (ICU) and V8.
The published figures are on [the benchmark page](https://corvus-oss.org/corvus-regex-ecma262-benchmarks/), which runs
every engine's image each night; this repository publishes none of its own.

Three rows are not like for like with an engine that is not ECMA-262's, as the price of its rules under u: `.*` (`.`
excludes CR, so the CRLF text has more matches), `Sher[a-z]+|Hol[a-z]+` under i (the search must also find the long s
and the Kelvin sign), and `[a-q][^u-z]{13}x` (a supplementary character is two units, so the distance to the `x` is
not fixed).

## 8. Differences an R user will meet

- The flags are a string, not `perl = TRUE`, `fixed = TRUE` or `ignore.case = TRUE`, and the grammar is ECMA-262's.
- A template writes a group as `$1` or `$<name>`, not `\\1`.
- `ecma_replace` replaces every match only with the `g` flag, as `sub` and `gsub` are two functions.

The [getting-started page](getting-started.md) has the full list.
