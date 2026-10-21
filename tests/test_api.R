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

# The README's example.
date <- ecma_regex("(?<year>\\d{4})-(?<month>\\d{2})", "g")
same(ecma_test(c("due 2026-10", "none"), date), c(TRUE, FALSE))
same(unname(ecma_match("due 2026-10", date)[, "year"]), "2026")
same(ecma_locate("due 2026-10", date)[1L, ], c(start = 5L, end = 11L))
same(ecma_match_all("2026-10, 2027-01", date)[[1L]][, 1L], c("2026-10", "2027-01"))
same(ecma_replace("2026-10, 2027-01", date, "$<month>/$1"), "10/2026, 01/2027")
same(ecma_replace("2026-10", date, function(m) m[["month"]]), "10")
same(ecma_split("a ; b;c", "\\s*(;)\\s*"), list(c("a", ";", "b", ";", "c")))

cat("all API checks passed\n")
