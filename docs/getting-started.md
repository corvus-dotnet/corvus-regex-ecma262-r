# Getting started with R

## Introduction

`corvusregexecma262` is an R package whose patterns answer as ECMAScript does. Where base R's `regexpr` and `gsub`
(PCRE2 or TRE) and stringi (ICU) have their own grammars and their own meaning for `\d`, `\w`, `\s`, `.`, case
folding and Unicode properties, this package has ECMA-262's, so a pattern written for JavaScript, or taken from a JSON
Schema, matches the same texts here as it does there. It is the corvus-regex-ecma262 Rust crate, held to V8's answers
on the ECMA-262 test data, and its functions are vectorised over their texts, as base R's are.

This guide covers:

- **Setup**: installing from R-universe.
- **Patterns and flags**: the flags are ECMA-262's letters, and what each one does.
- **The edition and the version of Unicode**: the grammar of ECMAScript 2020, and the Unicode tables a pattern reads.
- **Matching**: `ecma_test`, `ecma_match`, `ecma_locate`, `ecma_match_all`, `ecma_count`, `ecma_replace` and
  `ecma_split`.
- **Timeouts**: the limit of time and of memory a match may take.
- **UTF-8 and UTF-16**: strings, raw vectors of UTF-8 and `ecma_utf16` code units, each with its own positions.
- **Vectors and NA**: what each function returns for many texts and for a missing one.
- **Differences from base R and stringi**: what to expect when they meet.

## Setup

```
install.packages("corvusregexecma262", repos = c("https://corvus-dotnet.r-universe.dev", "https://cloud.r-project.org"))
```

R-universe has binary packages for Windows and macOS. A source install builds the native code, and needs
[Rust](https://rustup.rs) 1.89 or later.

```r
library(corvusregexecma262)
```

## Patterns and flags

A pattern is written as it would be in JavaScript, and the flags are the letters `RegExp` takes, as a string.
`ecma_regex` compiles a pattern once; every function also takes the pattern as a string, compiled for that call.

| Flag | Meaning |
|---|---|
| `d` | Accepted for completeness; indices are always kept. |
| `g` | `ecma_replace` replaces every match; without it, the first, as `String.prototype.replace` does. |
| `i` | Canonicalize of the mode in force: simple case folding with `u` or `v`, `toUpperCase` without. Never the locale. |
| `m` | `^` and `$` at line terminators. |
| `s` | The dot matches line terminators. |
| `u` | The `u` flag grammar; matched by code point. |
| `v` | Set notation and properties of strings; matched by code point. `u` and `v` together is an error, as in ECMA-262. |
| `y` | A match only at the start position. |

```r
library(corvusregexecma262)

a <- ecma_regex("\\p{Script=Greek}+", "u")
b <- ecma_regex("[[a-z]--[aeiou]]+", "v")
c <- ecma_regex("^(?<year>\\d{4})-(?<month>\\d{2})$", "u")

stopifnot(ecma_test("αβγ", a), ecma_test("rhythm", b))
stopifnot(ecma_match("2026-10", c)[, "month"] == "10")
```

With no flag the pattern is read with the Annex B grammar and matched by UTF-16 code unit, which is what ECMA-262 does
with no flag. JSON Schema's reading, the `u` flag first and Annex B when that refuses, is two compiles, each with the
match timeout, so no default timeout is needed; `tryCatch` is the form that does not stop:

```r
library(corvusregexecma262)

schema_pattern <- function(pattern) {
  tryCatch(ecma_regex(pattern, "u", timeout = 1),
           ecma_invalid_pattern = function(e) ecma_regex(pattern, "", timeout = 1))
}

stopifnot(ecma_test("Ωmega", schema_pattern("^\\p{L}+$")))
# An identity escape, which only Annex B allows.
stopifnot(ecma_test("-", schema_pattern("\\-")))
```

A pattern that is not valid signals `ecma_invalid_pattern`, whose message says why; invalid flags signal
`ecma_invalid_flags`. Every pattern has deterministic limits of size, and `ecma_pattern_too_large` says when one is
passed. Each is an `ecma_regex_error`.

```r
library(corvusregexecma262)

e <- tryCatch(ecma_regex("a{2,1}", "u"), ecma_regex_error = function(e) e)
stopifnot(inherits(e, "ecma_invalid_pattern"), nzchar(conditionMessage(e)))
stopifnot(inherits(tryCatch(ecma_regex("a", "uv"), error = function(e) e), "ecma_invalid_flags"))
stopifnot(identical(ecma_valid(c("a+", "(?<n>a)(?<n>b)"), "u"), c(TRUE, FALSE)))
```

## The edition and the version of Unicode

JSON Schema 2020-12 names the grammar of ECMAScript 2020. `edition = "es2020"` refuses what later editions added, and
nothing else: the `d` and `v` flags, modifier groups such as `(?i:...)`, a group name used by two groups, and a
property name or value that is not in the 2020 tables (such as `\p{Script=Yezidi}`). A pattern it accepts has the same
answers as in today's grammar.

The version of Unicode is chosen apart from the edition: `unicode_version` is 13, 17, 18, `"latest"` (18 today) or
`NULL`, the version of the V8 the answers are held to (17 today). It decides the members of each `\p{...}`, the
characters of a group name and the case folding of the `i` flag. A compiled pattern's `unicode_version` attribute
reports the version it was compiled with. Both are read when the pattern is compiled, so a match costs the same
whichever is chosen.

```r
library(corvusregexecma262)

# ECMAScript 2020 as its edition was published, with the Unicode of its year.
greek <- ecma_regex("^\\p{Script=Greek}+$", "u", timeout = 1, edition = "es2020", unicode_version = 13)
stopifnot(ecma_test("αβγ", greek), attr(greek, "unicode_version") == 13)

# Vithkuqi is in Unicode 14 and later, so not in Unicode 13.
stopifnot(!ecma_valid("\\p{Script=Vithkuqi}", "u", unicode_version = 13))
```

## Matching

The functions are those of a `RegExp`, with the position as `start` where JavaScript keeps `lastIndex`. Positions are
in characters from 1, an end inclusive, as `regexpr` gives them. A match is a row of a character matrix: the match,
then each group, then a column for each group name.

```r
library(corvusregexecma262)

date <- ecma_regex("(?<year>\\d{4})-(?<month>\\d{2})", "gu")
text <- "due 2026-10, then 2027-01"

stopifnot(ecma_test(text, date))
m <- ecma_match(text, date)
stopifnot(m[, 1] == "2026-10", m[, "year"] == "2026", m[, 3] == "10")
where <- ecma_locate(text, date)
stopifnot(where[, "start"] == 5, where[, "end"] == 11)

# Every match of a global search, as matchAll makes it.
stopifnot(identical(ecma_match_all(text, date)[[1]][, 1], c("2026-10", "2027-01")))
stopifnot(ecma_count(text, date) == 2)

# ecma_replace replaces every match with the g flag, and the first without it, with every $ form of ECMA-262, or a function.
stopifnot(ecma_replace(text, date, "$<month>/$1") == "due 10/2026, then 01/2027")
stopifnot(ecma_replace(text, date, function(m) m[["year"]]) == "due 2026, then 2027")

# ecma_split puts what the groups captured between the pieces; a group that did not take part is NA.
stopifnot(identical(ecma_split("a ; b;c", "\\s*(;)\\s*")[[1]], c("a", ";", "b", ";", "c")))
```

`ecma_match(x, regex, start)` is `exec` with `lastIndex` set to `start - 1`, and `y` anchors it there. `ecma_test`
and `ecma_count` make no match, and so allocate nothing for one. A compiled pattern is immutable, so one is reused
from call to call.

## Timeouts

A match has no limit by default. A pattern compiled with a `timeout` (in seconds) abandons a match that reaches it, or
that reaches the cap on backtracking memory the timeout brings, with the condition `ecma_match_limit`, whatever the
pattern:

```r
library(corvusregexecma262)

slow <- ecma_regex("^(?:(a+)\\1*)+$", timeout = 0.1)
e <- tryCatch(ecma_test(paste0(strrep("a", 60), "b"), slow), ecma_regex_error = function(e) e)
stopifnot(inherits(e, "ecma_match_limit"))
```

A pattern compiled without a timeout takes `ecma_default_timeout()`, which is `NULL` (no limit) unless
`ecma_set_default_timeout` sets it. A program that matches patterns or texts from outside should set one, for example
with `ecma_set_default_timeout(1)` when it starts. `ecma_test`, `ecma_match` and `ecma_locate` take a `timeout` of
their own for each search.

A pattern without a backreference is matched in time linear in the text, and no pattern can overflow the stack, so the
timeout is what bounds the others.

## UTF-8 and UTF-16

A string marked as UTF-8, or in the native encoding of a UTF-8 session, is read in place with no transcoding, after a
check that it is UTF-8; one in another encoding is translated, and one marked as bytes is refused. Over strings,
positions are in characters, as `nchar` counts them. A raw vector is one text of UTF-8 bytes, with positions in bytes;
one that is not UTF-8 signals `ecma_encoding_error`, and is never matched or read as U+FFFD. An `ecma_utf16` is one
text of UTF-16 code units, lone surrogates and all, with positions in code units.

```r
library(corvusregexecma262)

dot_b <- ecma_regex(".b", "u")
text <- "a\U0001F600b"
stopifnot(ecma_locate(text, dot_b)[, "end"] == 3)                       # characters
stopifnot(ecma_locate(charToRaw(enc2utf8(text)), dot_b)[, "end"] == 6)  # bytes of UTF-8
stopifnot(ecma_locate(ecma_utf16(text), dot_b)[, "end"] == 4)           # UTF-16 code units

e <- tryCatch(ecma_test(as.raw(0xff), dot_b), ecma_regex_error = function(e) e)
stopifnot(inherits(e, "ecma_encoding_error"))
```

Under the `u` and `v` flags a character is a code point in every encoding, so a class, a dot or a quantifier takes a
four-byte sequence as one character. With no flag ECMA-262 matches by UTF-16 code unit, so a match can take half of a
character beyond the Basic Multilingual Plane: over a string its text then holds that half as U+FFFD, and its
positions are the whole character's.

## Vectors and NA

Each function takes a vector of strings and answers for each: `ecma_test` a logical vector, `ecma_match` a matrix with
a row for each string, `ecma_locate` an integer matrix, and `ecma_match_all`, `ecma_locate_all` and `ecma_split` a
list. A missing string gives `NA`, or `NULL` in a list. A raw vector or an `ecma_utf16` is one text; a list of them is
many.

```r
library(corvusregexecma262)

stopifnot(identical(ecma_test(c("due 2026-10", "none", NA), "\\d{4}"), c(TRUE, FALSE, NA)))
stopifnot(identical(ecma_count(c("1 2 3", ""), "\\d"), c(3L, 0L)))
```

## Differences from base R and stringi

The functions follow `RegExp`; the meaning follows ECMA-262. The differences a user coming from base R's `regexpr`
and `gsub`, or from stringi, will meet:

- **The grammar.** No `(?i)` inline option (ECMA-262 has `(?i:...)` groups), no atomic groups, no possessive
  quantifiers, no `\A` or `\z`, no `[[:alpha:]]` classes, no conditionals and no recursion. The flags are a separate
  string, not `perl = TRUE`, `fixed = TRUE` or `ignore.case = TRUE`.
- **The character classes.** `\d` is `[0-9]`, `\w` is the 63 ASCII word characters, `\s` is ECMAScript's white space
  and line terminators, and `.` excludes the four line terminators (LF, CR, U+2028, U+2029), whatever the locale.
- **Replacement.** A template writes a group as `$1` or `$<name>`, not `\\1`, and `$&`, `` $` `` and `$'` are the
  match and the text before and after it. `ecma_replace` replaces every match only with the `g` flag, as `sub` and
  `gsub` are two functions; `ecma_replace_all` always does.
- **Split.** `ecma_split` is JavaScript's, which puts what the groups captured between the pieces and keeps empty
  pieces at the end.
- **Timeouts.** Neither base R nor stringi has a limit on a match's time. Here a pattern without a backreference is
  matched in time linear in the text, and a timeout bounds the others.
