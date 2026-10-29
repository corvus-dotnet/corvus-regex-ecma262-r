# The package's API against the answers V8 gives: compiling, testing, matching, locating, counting, replacing and
# splitting, positions in characters, the half characters of a match without u or v, and the conditions raised.
library(corvusregexecma262)

condition_of <- function(expr) {
  tryCatch({
    expr
    NULL
  }, condition = function(e) e)
}

raises <- function(expr, class) {
  e <- condition_of(expr)
  if (!inherits(e, class)) {
    stop(sprintf("expected a %s, got %s", class, if (is.null(e)) "no condition" else paste(class(e)[1L], conditionMessage(e))),
         call. = FALSE)
  }
  invisible(TRUE)
}

# Whether a is b; where b has no names or dimensions, a's names are not compared (a selection from a matrix keeps
# the column's name).
same <- function(a, b) {
  if (is.null(names(b)) && is.null(dim(b)) && is.null(dim(a))) {
    a <- unname(a)
  }
  if (!identical(a, b)) {
    stop(paste(c("not the same:", capture.output(str(a)), "and", capture.output(str(b))), collapse = "\n"), call. = FALSE)
  }
}

v <- ecma_version()
stopifnot(identical(names(v), c("package", "crate")), all(nzchar(v)))

# Compiling
date <- ecma_regex("(?<year>\\d{4})-(?<month>\\d{2})(-(\\d{2}))?", "gu")
stopifnot(inherits(date, "ecma_regex"))
same(attr(date, "source"), "(?<year>\\d{4})-(?<month>\\d{2})(-(\\d{2}))?")
same(attr(date, "flags"), "gu")
same(attr(date, "group_count"), 4L)
same(attr(date, "group_names"), c("year", "month"))
same(attr(ecma_regex("a", "yig"), "flags"), "giy")
same(format(date), "/(?<year>\\d{4})-(?<month>\\d{2})(-(\\d{2}))?/gu")
same(ecma_valid(c("a+", "a{2,1}", "a{2,1", NA), "u"), c(TRUE, FALSE, FALSE, NA))
# Annex B reads {2,1 as text without u.
same(ecma_valid("a{2,1"), TRUE)
raises(ecma_regex("("), "ecma_invalid_pattern")
raises(ecma_regex("\\p{Nope}", "u"), "ecma_invalid_pattern")
raises(ecma_regex("a", "uv"), "ecma_invalid_flags")
raises(ecma_regex(paste0(strrep("(", 1001), strrep(")", 1001))), "ecma_pattern_too_large")
raises(ecma_regex("("), "ecma_regex_error")
raises(ecma_test("a", 3), "ecma_argument_error")

# Testing
same(ecma_test(c("foo", "bar", NA), "o+"), c(TRUE, FALSE, NA))
# The y flag: a match starts where the search starts.
sticky <- ecma_regex("o", "y")
same(ecma_test(c("foo", "foo"), sticky, start = c(1L, 2L)), c(FALSE, TRUE))
same(ecma_test("café ok", ecma_regex("ok", "y"), start = 6L), TRUE)

# Matching: the match, each group, then each name
m <- ecma_match(c("due 2026-10, then", "none", NA, "on 2027-01-31"), date)
same(dim(m), c(4L, 7L))
same(colnames(m), c("", "", "", "", "", "year", "month"))
same(unname(m[1L, ]), c("2026-10", "2026", "10", NA, NA, "2026", "10"))
same(unname(m[2L, ]), rep(NA_character_, 7L))
same(unname(m[4L, "month"]), "01")
same(m[4L, 5L], "31")
same(unname(ecma_match("b", ecma_regex("(?<d>a)|(?<d>b)"))[, "d"]), "b")

# Locating, in characters from 1, the end inclusive
same(ecma_locate(c("a foo", "café ok", "x", NA), "ok|o+"), matrix(c(4L, 6L, NA, NA, 5L, 7L, NA, NA), ncol = 2L,
                                                             dimnames = list(NULL, c("start", "end"))))
same(ecma_locate("on 2027-01-31", date, group = "month")[1L, ], c(start = 9L, end = 10L))
same(ecma_locate("on 2027-01-31", date, group = 4L)[1L, ], c(start = 12L, end = 13L))
# An empty match ends before it starts, as regexpr's do.
same(ecma_locate("ab", "(?=b)")[1L, ], c(start = 2L, end = 1L))

# Without u a character beyond the Basic Multilingual Plane is two code units, and . takes one: the text holds the
# half as U+FFFD, and the position is the whole character's.
same(ecma_match("\U0001F600x", "^.")[1L, 1L], "�")
same(ecma_locate("\U0001F600x", "^.")[1L, ], c(start = 1L, end = 1L))
same(ecma_match("\U0001F600x", ecma_regex("^.", "u"))[1L, 1L], "\U0001F600")
same(ecma_locate("a\U0001F600b", ecma_regex("\\udE00b"))[1L, ], c(start = 2L, end = 3L))

# Every match
all <- ecma_match_all(c("1 22 333", "", NA), ecma_regex("\\d+", "g"))
same(all[[1L]][, 1L], c("1", "22", "333"))
same(dim(all[[2L]]), c(0L, 1L))
same(all[[3L]], NULL)
same(ecma_match_all("x1y22", "(\\d)(\\d)?")[[1L]], matrix(c("1", "22", "1", "2", NA, "2"), ncol = 3L,
                                                                 dimnames = list(NULL, c("", "", ""))))
same(unname(ecma_match_all("2026-10, 2027-01", date)[[1L]][, "year"]), c("2026", "2027"))
same(ecma_locate_all("x1y22z333", "\\d+")[[1L]], matrix(c(2L, 4L, 7L, 2L, 5L, 9L), ncol = 2L,
                                                       dimnames = list(NULL, c("start", "end"))))
same(ecma_locate_all("x1y22z3", "(\\d)(\\d)?", group = 2L)[[1L]], matrix(c(NA, 5L, NA, NA, 5L, NA), ncol = 2L,
                                                                     dimnames = list(NULL, c("start", "end"))))
same(ecma_locate_all("2026-10, 2027-01", date, group = "month")[[1L]][, "start"], c(6L, 15L))
same(nrow(ecma_match_all("\U0001F600", ecma_regex("", "gu"))[[1L]]), 2L)
same(nrow(ecma_match_all("\U0001F600", ecma_regex("", "g"))[[1L]]), 3L)

# Counting
same(ecma_count(c(strrep("a ", 1000), "", NA), "a"), c(1000L, 0L, NA))
same(ecma_count("aab", ecma_regex("a", "y")), 2L)
same(ecma_count("baa", ecma_regex("a", "y")), 0L)

# Replacing
same(ecma_replace("2026-10, 2027-01", date, "$<month>/$1"), "10/2026, 01/2027")
same(ecma_replace(c("1 2 3", NA, "x"), "\\d+", "[$&]"), c("[1] 2 3", NA, "x"))
same(ecma_replace_all("1 2 3", "\\d+", "[$&]"), "[1] [2] [3]")
same(ecma_replace("a1b", "\\d+", "<$`|$'|$$>"), "a<a|b|$>b")
same(ecma_replace(c("a1", "b2"), "\\d", c("x", "y")), c("ax", "by"))
same(ecma_replace_all("1 2 3", "\\d+", function(m) as.character(as.integer(m[[1L]]) * 2L)), "2 4 6")
same(ecma_replace("2026-10 and 2027-01", ecma_regex("(?<year>\\d{4})-(?<month>\\d{2})"), function(m) m[["month"]]),
     "10 and 2027-01")
same(ecma_replace(c("none", NA), "\\d", function(m) "x"), c("none", NA))
same(ecma_replace("\U0001F600", "^.", "x"), "x�")
same(ecma_replace("\U0001F600", "^.", function(m) "x"), "x�")

# Splitting
same(ecma_split("a ; b;c", "\\s*(;)\\s*"), list(c("a", ";", "b", ";", "c")))
same(ecma_split("a;b;c", "\\s*(;)\\s*", limit = 2L), list(c("a", ";")))
same(ecma_split(c("a,b", NA), "(x)?,"), list(c("a", NA, "b"), NULL))

# Strings in other encodings are translated; a string marked as bytes is refused.
latin1 <- iconv("café", "UTF-8", "latin1")
Encoding(latin1) <- "latin1"
same(ecma_match(latin1, "é")[1L, 1L], "é")
# (R ignores the mark on an ASCII string.)
bytes <- "caf\xc3\xa9"
Encoding(bytes) <- "bytes"
raises(ecma_test(bytes, "a"), "ecma_encoding_error")

# A long text is checked once and remembered; another long text after it is checked too.
long <- strrep("ab", 5000)
same(ecma_count(long, "b"), 5000L)
same(ecma_count(long, "b"), 5000L)
same(ecma_count(paste0(long, "b"), "b"), 5001L)

# Limits: a match that runs past its timeout raises a condition.
slow <- ecma_regex("^(a+)+\\1$")
raises(ecma_test(paste0(strrep("a", 64), "!"), slow, timeout = 0.005), "ecma_match_limit")
same(ecma_test(paste0(strrep("a", 64), "!"), "^(a+)+$", timeout = 1), FALSE)

# The match timeout of a pattern, which every function honours.
never <- "^(?:(a+)\\1*)+$"
long <- paste0(strrep("a", 60), "b")
timed <- ecma_regex(never, "u", timeout = 0.03)
same(attr(timed, "timeout"), 0.03)
raises(ecma_test(long, timed), "ecma_match_limit")
raises(ecma_match(long, timed), "ecma_match_limit")
raises(ecma_locate(long, timed), "ecma_match_limit")
raises(ecma_match_all(long, timed), "ecma_match_limit")
raises(ecma_locate_all(long, timed), "ecma_match_limit")
raises(ecma_count(long, timed), "ecma_match_limit")
# A condition from the direct path of a character vector names the call it came from, as the full path's does.
for (e in list(condition_of(ecma_count(long, timed)), condition_of(ecma_test(long, timed)))) {
  stopifnot(as.character(conditionCall(e)[[1L]]) %in% c("ecma_count", "ecma_test"), identical(deparse(conditionCall(e)[[2L]]), "long"))
}
raises(ecma_replace(long, timed, "x"), "ecma_match_limit")
raises(ecma_replace_all(long, timed, "x"), "ecma_match_limit")
raises(ecma_replace(long, timed, function(m) "x"), "ecma_match_limit")
raises(ecma_split(long, timed), "ecma_match_limit")
raises(ecma_split(long, timed, limit = 2L), "ecma_match_limit")
same(ecma_test("aaaa", timed), TRUE)
same(ecma_replace("aaaa", timed, "<$&>"), "<aaaa>")
same(ecma_test("aaaa", ecma_regex("^(a+)\\1$", timeout = 0.000001), timeout = 0), TRUE)
raises(ecma_test(long, ecma_regex(never, "u", timeout = 3600), timeout = 0.03), "ecma_match_limit")
e <- condition_of(ecma_test("", ecma_regex("(?:a?){2147483647}", timeout = 3600)))
stopifnot(inherits(e, "ecma_match_limit"), grepl("memory", conditionMessage(e)))
stopifnot(is.null(ecma_default_timeout()), is.null(attr(ecma_regex("a"), "timeout")))
ecma_set_default_timeout(0.03)
same(ecma_default_timeout(), 0.03)
defaulted <- ecma_regex(never, "u")
own <- ecma_regex("a", timeout = 5)
none <- ecma_regex("a", timeout = 0)
from_string <- tryCatch(ecma_test(long, never), condition = function(e) e)
ecma_set_default_timeout(NULL)
stopifnot(is.null(ecma_default_timeout()))
same(attr(defaulted, "timeout"), 0.03)
raises(ecma_test(long, defaulted), "ecma_match_limit")
stopifnot(inherits(from_string, "ecma_match_limit"))
same(attr(own, "timeout"), 5)
stopifnot(is.null(attr(none, "timeout")))
raises(ecma_set_default_timeout(-1), "ecma_argument_error")

# The edition and the version of Unicode: today's grammar and V8's Unicode by default, each resolved when the pattern
# is compiled.
a <- ecma_regex("a")
same(attr(a, "edition"), "current")
same(attr(a, "unicode_version"), 17L)
same(ecma_default_unicode_version(), 17L)
same(ecma_latest_unicode_version(), 18L)
same(ecma_unicode_versions(), c(13L, 17L, 18L))
for (asked in list(list(NULL, 17L), list(13, 13L), list(17L, 17L), list(18, 18L), list("latest", 18L))) {
  same(attr(ecma_regex("a", unicode_version = asked[[1L]]), "unicode_version"), asked[[2L]])
}
for (bad in list(12, 19, "18", "default", c(13, 17), NA_real_)) {
  raises(ecma_regex("a", unicode_version = bad), "error")
  raises(ecma_valid("a", unicode_version = bad), "error")
}
raises(ecma_regex("a", edition = "es2022"), "error")
raises(ecma_valid("a", edition = NA_character_), "error")

# Each version has its own scripts.
for (case in list(list("\\p{Script=Vithkuqi}", 13, FALSE), list("\\p{Script=Vithkuqi}", NULL, TRUE),
                  list("\\p{Script=Yezidi}", 13, TRUE), list("\\p{Script=Jurchen}", NULL, FALSE),
                  list("\\p{scx=Jurc}", 18, TRUE), list("\\p{Script=Jurchen}", "latest", TRUE))) {
  same(ecma_valid(case[[1L]], "u", unicode_version = case[[2L]]), case[[3L]])
  if (case[[3L]]) {
    ecma_regex(case[[1L]], "u", unicode_version = case[[2L]])
  } else {
    raises(ecma_regex(case[[1L]], "u", unicode_version = case[[2L]]), "ecma_invalid_pattern")
  }
}

# A property and case folding are the version's.
letter <- "\U00010597"
same(ecma_test(letter, ecma_regex("^\\p{Ll}$", "u")), TRUE)
same(ecma_test(letter, ecma_regex("^\\p{Ll}$", "u", unicode_version = 13)), FALSE)
same(ecma_test(letter, ecma_regex("\U00010570", "iu")), TRUE)
same(ecma_test(letter, ecma_regex("\U00010570", "iu", unicode_version = 13)), FALSE)
same(ecma_test("ꟁ", ecma_regex("Ꟁ", "i")), TRUE)
same(ecma_test("ꟁ", ecma_regex("Ꟁ", "i", unicode_version = 13)), FALSE)

# A case-insensitive backreference folds as its version folds, over a string and over UTF-16.
for (case in list(c("iu", "\U00010570\U00010597"), c("i", "Ꟁꟁ"))) {
  flags <- case[[1L]]
  text <- case[[2L]]
  twice <- strrep(substr(text, 1L, 1L), 2L)
  for (pattern in c("(.)\\1", "(?<=\\1(.))", "(?:x|(.))+\\1$")) {
    for (version in c(17, 18)) {
      re <- ecma_regex(pattern, flags, unicode_version = version)
      same(ecma_test(text, re), TRUE)
      same(ecma_test(ecma_utf16(text), re), TRUE)
    }
    re <- ecma_regex(pattern, flags, unicode_version = 13)
    same(ecma_test(text, re), FALSE)
    same(ecma_test(ecma_utf16(text), re), FALSE)
    same(ecma_test(twice, re), TRUE)
  }
}

# The grammar of 2020 refuses what later editions added, and accepts what it had.
for (case in list(c("(?i:a)", ""), c("(?-i:a)", "i"), c("(?s:.)", "u"), c("(?<a>x)|(?<a>y)", ""),
                  c("(?<a>x)|(?<a>y)", "u"), c("\\p{Script=Yezidi}", "u"), c("\\p{sc=Vith}", "u"),
                  c("\\p{Script_Extensions=Toto}", "u"))) {
  raises(ecma_regex(case[[1L]], case[[2L]], edition = "es2020", unicode_version = "latest"), "ecma_invalid_pattern")
  same(ecma_valid(case[[1L]], case[[2L]], edition = "es2020", unicode_version = "latest"), FALSE)
  ecma_regex(case[[1L]], case[[2L]], unicode_version = "latest")
}
for (case in list(c("\\p{Script=Greek}", "u"), c("\\p{L}\\p{gc=Lu}\\p{Lowercase}", "u"), c("\\P{scx=Latn}", "iu"),
                  c("\\p{Script=Yezidi}", ""), c("(?<a>x)(?<b>y)\\k<a>", "u"), c("(?<=a)(?<!b)", "s"),
                  c("(?:i)", ""))) {
  re <- ecma_regex(case[[1L]], case[[2L]], edition = "es2020", unicode_version = 13)
  same(attr(re, "edition"), "es2020")
  same(attr(re, "unicode_version"), 13L)
}
for (flags in c("d", "v", "dv", "gv")) {
  raises(ecma_regex("a", flags, edition = "es2020"), "ecma_invalid_flags")
  same(ecma_valid("a", flags, edition = "es2020"), FALSE)
  ecma_regex("a", flags)
}

# The settings and a timeout go together; tryCatch on ecma_regex is the form that gives NULL for a pattern that is
# not valid, and it needs no default timeout.
re <- ecma_regex(never, "u", timeout = 0.03, edition = "es2020", unicode_version = 13)
same(attr(re, "timeout"), 0.03)
same(c(attr(re, "edition"), attr(re, "unicode_version")), c("es2020", "13"))
raises(ecma_test(long, re), "ecma_match_limit")
same(tryCatch(ecma_regex("(?i:a)", timeout = 0.03, edition = "es2020"), ecma_regex_error = function(e) NULL), NULL)
ecma_set_default_timeout(0.03)
settled <- ecma_regex("a", edition = "es2020", unicode_version = 18)
ecma_set_default_timeout(NULL)
same(attr(settled, "timeout"), 0.03)

# Raw vectors: UTF-8 bytes, which may hold a NUL as an R string cannot. Positions are in bytes, and the texts of a
# match are raw vectors.
nul <- as.raw(c(0x61, 0x00, 0x62))
same(ecma_test(nul, "\\0"), TRUE)
same(ecma_locate(nul, "\\0")[1L, ], c(start = 2L, end = 2L))
same(ecma_match(nul, "a\\0")[[1L, 1L]], as.raw(c(0x61, 0x00)))
same(ecma_locate(charToRaw("café ok"), "ok")[1L, ], c(start = 7L, end = 8L))
# Half a character beyond the Basic Multilingual Plane: two of its four bytes, the half's text U+FFFD.
same(ecma_locate(charToRaw("\U0001F600x"), "^.")[1L, ], c(start = 1L, end = 2L))
same(ecma_match(charToRaw("\U0001F600x"), "^.")[[1L, 1L]], charToRaw("�"))
same(ecma_test(list(nul, NULL, charToRaw("x")), "\\0"), c(TRUE, NA, FALSE))
same(ecma_match_all(nul, ecma_regex("[ab]", "g"))[[1L]][, 1L], list(as.raw(0x61), as.raw(0x62)))
same(ecma_locate_all(nul, "[ab]")[[1L]][, "start"], c(1L, 3L))
same(ecma_count(list(nul, nul), "[ab]"), c(2L, 2L))
same(ecma_replace(nul, "\\0", "-"), charToRaw("a-b"))
same(ecma_replace(nul, "b", as.raw(c(0x00, 0x63))), as.raw(c(0x61, 0x00, 0x00, 0x63)))
same(ecma_replace(list(nul, NULL), "b", "c"), list(as.raw(c(0x61, 0x00, 0x63)), NULL))
same(ecma_replace_all(nul, "[ab]", function(m) toupper(rawToChar(m[[1L]]))), as.raw(c(0x41, 0x00, 0x42)))
same(ecma_replace_all(nul, "\\0", function(m) as.raw(c(0x00, 0x00))), as.raw(c(0x61, 0x00, 0x00, 0x62)))
same(ecma_split(nul, "\\0"), list(list(as.raw(0x61), as.raw(0x62))))
same(ecma_split(nul, "(x)?\\0"), list(list(as.raw(0x61), NULL, as.raw(0x62))))
# A pattern may be a raw vector, which may hold a NUL.
nul_pattern <- ecma_regex(as.raw(c(0x61, 0x00)))
same(attr(nul_pattern, "source"), as.raw(c(0x61, 0x00)))
same(format(nul_pattern), "/a\\0/")
same(ecma_test(nul, nul_pattern), TRUE)
same(attr(ecma_regex(charToRaw("a+")), "source"), "a+")
same(ecma_valid(list(as.raw(c(0x61, 0x00)), charToRaw("("), NULL)), c(TRUE, FALSE, NA))
# Bytes that are not UTF-8 are refused, never read.
raises(ecma_test(as.raw(0xFF), "a"), "ecma_encoding_error")
raises(ecma_test(as.raw(c(0xED, 0xA0, 0x80)), "a"), "ecma_encoding_error")
raises(ecma_regex(as.raw(c(0x61, 0xC0))), "ecma_encoding_error")
raises(ecma_test(list(1:3), "a"), "error")

# ecma_utf16: UTF-16 code units, which may hold lone surrogates as a JavaScript string can. Positions are in code
# units, and the texts of a match are ecma_utf16s.
pair <- ecma_utf16("a\U0001F600b")
same(unclass(pair), c(0x61L, 0xD83DL, 0xDE00L, 0x62L))
same(unclass(ecma_utf16(charToRaw("é"))), 0xE9L)
lone <- ecma_utf16(c(0x61, 0xD800, 0x62))
same(ecma_test(lone, "\\uD800"), TRUE)
same(ecma_test(lone, ecma_regex("\\uD800", "u")), TRUE)
same(ecma_locate(lone, "\\uD800")[1L, ], c(start = 2L, end = 2L))
same(ecma_match(lone, "a.")[[1L, 1L]], ecma_utf16(c(0x61, 0xD800)))
same(ecma_locate(pair, "\\uDE00b")[1L, ], c(start = 3L, end = 4L))
# A start between the halves of a pair, as lastIndex can be.
same(ecma_test(pair, ecma_regex("\\uDE00", "y"), start = 3L), TRUE)
same(ecma_test(pair, ecma_regex("\\uDE00", "uy"), start = 3L), FALSE)
same(ecma_count(pair, ecma_regex("", "g")), 5L)
same(ecma_count(pair, ecma_regex("", "gu")), 4L)
same(ecma_match_all(pair, ecma_regex(".", "gu"))[[1L]][, 1L],
     list(ecma_utf16("a"), ecma_utf16("\U0001F600"), ecma_utf16("b")))
same(ecma_replace(pair, "\\uD83D", "x"), ecma_utf16(c(0x61, 0x78, 0xDE00, 0x62)))
same(ecma_replace(lone, "b", lone), ecma_utf16(c(0x61, 0xD800, 0x61, 0xD800, 0x62)))
same(ecma_replace_all(ecma_utf16("abc"), "[ac]", function(m) toupper(as.character(m[[1L]]))), ecma_utf16("AbC"))
same(ecma_split(lone, "\\uD800"), list(list(ecma_utf16("a"), ecma_utf16("b"))))
same(as.character(ecma_utf16(c(0x61, 0xD800))), "a�")
same(as.raw(ecma_utf16(c(0x61, 0x00, 0x62))), nul)
raises(as.character(ecma_utf16(c(0x61, 0x00))), "ecma_encoding_error")
same(capture.output(print(lone)), "<ecma_utf16[3]> \"a\\uD800b\"")
same(c(ecma_utf16("a"), "b"), ecma_utf16("ab"))
same(lone[2:3], ecma_utf16(c(0xD800, 0x62)))
raises(ecma_utf16(70000), "error")
raises(ecma_utf16(c("a", "b")), "error")
raises(ecma_regex(ecma_utf16("a")), "error")

# The README's example.
date <- ecma_regex("(?<year>\\d{4})-(?<month>\\d{2})", "g")
same(ecma_test(c("due 2026-10", "none"), date), c(TRUE, FALSE))
same(unname(ecma_match("due 2026-10", date)[, "year"]), "2026")
same(ecma_locate("due 2026-10", date)[1L, ], c(start = 5L, end = 11L))
same(ecma_match_all("2026-10, 2027-01", date)[[1L]][, 1L], c("2026-10", "2027-01"))
same(ecma_replace("2026-10, 2027-01", date, "$<month>/$1"), "10/2026, 01/2027")
same(ecma_replace("2026-10", date, function(m) m[["month"]]), "10")
same(ecma_split("a ; b;c", "\\s*(;)\\s*"), list(c("a", ";", "b", ";", "c")))

# Nested classes on a small stack: with v a class holds classes, each a level of reading. On a stack of 512 KB the
# deepest nesting allowed is read, compiled and matched, and deeper is refused as too large, rather than overflowing
# the stack, which ends the process (as with the crate up to 0.1.1). R runs on the main thread, so a child is started
# with ulimit -s; there is no ulimit on Windows.
if (.Platform$OS.type == "unix") {
  script <- tempfile(fileext = ".R")
  writeLines(c(
    "library(corvusregexecma262)",
    "nest <- function(depth) paste0(strrep('[', depth), 'a', strrep(']', depth))",
    "refused <- vapply(c(nest(1001L), strrep('[', 200000L)), function(p) tryCatch({",
    "  ecma_regex(p, 'v')",
    "  'compiled'",
    "}, ecma_pattern_too_large = function(e) 'too large'), '')",
    "cat(ecma_test('a', ecma_regex(nest(1000L), 'v')), unname(refused))"
  ), script)
  rscript <- shQuote(file.path(R.home("bin"), "Rscript"))
  command <- sprintf("ulimit -s 512 && exec %s %s", rscript, shQuote(script))
  libs <- paste0("R_LIBS=", shQuote(paste(.libPaths(), collapse = .Platform$path.sep)))
  # The answer is on stdout; R may write warnings of its own start to stderr (under R CMD check it does).
  out <- suppressWarnings(system2("sh", c("-c", shQuote(command)), stdout = TRUE, stderr = FALSE, env = libs))
  same(out, "TRUE too large too large")
}

cat("all API checks passed\n")
