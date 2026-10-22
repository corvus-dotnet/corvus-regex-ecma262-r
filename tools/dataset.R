# Runs this package over the ECMA-262 regular expression test data (github.com/corvus-dotnet/ecma262-regex-test-data),
# judged by the data's own rule ("How a runner judges an engine" in its README) as the C library's runner judges it:
#
#   Rscript tools/dataset.R <data directory> <wrong-cases output file> [--files <glob>] [--workers N]
#
# Each record is asked about under each grammar V8 found it valid in: the record's flags with u added (the unicode
# answers), the record's flags alone (the legacy answers) and, in the file that has them, the flags with v added (the
# unicode_sets answers). R's strings are UTF-8, so a text is matched as R holds it, positions in characters; a text with
# a lone surrogate has no UTF-8 form and is not asked about, and a lone surrogate in a pattern is read as U+FFFD. An R
# string cannot hold a NUL character, so a text with one is not asked about, nor a pattern with one.
# Records marked v8_deviation are left out. Any difference from V8 is a wrong answer; a refusal of a valid pattern, an
# acceptance of an invalid one, and a match that reaches its limit are counted apart and listed too. captures.jsonl is
# judged on exec, the global search, the sticky flag, replace and split. A match is given 2 seconds.
#
# The data gives positions in UTF-16 code units. They are compared in characters from 1, an end inclusive, as the
# package gives them: a position between the halves of a character (which a match without u or v can reach) is the
# character's, for a start and for an end. Texts are compared with V8's answer converted to UTF-8, a lone surrogate
# as U+FFFD, as the package writes a half character.
#
# jsonlite reads a lone surrogate escape as nothing it can keep, so each is rewritten first as the escape of a code
# point of a block of private use code points (the block's first + its offset from U+D800), and a NUL escape as the
# code point after those 2,048, so that a string with either is known. The block is chosen for each line from the
# blocks of Planes 15 and 16: the first whose code points the line does not hold, which is known when the line, read
# with that block, holds as many of them as it had escapes rewritten. So no character of the data is taken for a lone
# surrogate or a NUL (test262's texts hold the ends of the private use ranges).
suppressPackageStartupMessages({
  library(corvusregexecma262)
  library(jsonlite)
  library(parallel)
})

LIMIT <- 2
REPLACEMENT <- "<$&|$1|$2|$10|$<a>|$$|$`|$'>"
# The first code point of each block a line's lone surrogates and NULs may be read as, and the block of the line being
# judged (set by read_record).
BLOCKS <- c(seq(0xF0000, 0xFE000, by = 0x1000), seq(0x100000, 0x10E000, by = 0x1000))
marks <- new.env()
marks$first <- 0xF0000

native <- asNamespace("corvusregexecma262")

# An escaped backslash, a surrogate pair's escapes, a lone surrogate's escape, or a NUL's.
surrogate_escape <- r"[\\\\|\\u(d[89ab][0-9a-f]{2})\\u(d[c-f][0-9a-f]{2})|\\u(d[89a-f][0-9a-f]{2})|\\u0000]"

# The line with each lone surrogate escape and NUL escape rewritten for a block, and how many were.
rewrite <- function(line, block) {
  if (!grepl("\\\\u(d[89a-f]|0000)", line, perl = TRUE, ignore.case = TRUE)) {
    return(list(line = line, written = 0L))
  }
  m <- gregexpr(surrogate_escape, line, perl = TRUE, ignore.case = TRUE)
  tokens <- regmatches(line, m)[[1L]]
  written <- 0L
  regmatches(line, m) <- list(vapply(tokens, function(t) {
    if (nchar(t) != 6L) {
      return(t)
    }
    written <<- written + 1L
    v <- if (t == "\\u0000") block + 0x800 - 0x10000 else block + strtoi(substr(t, 3L, 6L), 16L) - 0xD800 - 0x10000
    sprintf("\\u%04x\\u%04x", 0xD800 + bitwShiftR(v, 10L), 0xDC00 + bitwAnd(v, 0x3FF))
  }, character(1L), USE.NAMES = FALSE))
  list(line = line, written = written)
}

# How many code points of a block (its 2,048 and the NUL's after them) the strings of a value hold.
count_in <- function(value, block) {
  if (is.character(value)) {
    sum(vapply(value, function(s) sum((cps <- utf8ToInt(s)) >= block & cps <= block + 0x800), numeric(1L)))
  } else if (is.list(value)) {
    sum(vapply(value, count_in, numeric(1L), block = block)) + if (is.null(names(value))) 0 else count_in(names(value), block)
  } else {
    0
  }
}

# The record of a line, its lone surrogates and NULs read as code points of the first block the line does not use.
read_record <- function(line) {
  for (block in BLOCKS) {
    rw <- rewrite(line, block)
    r <- parse_json(rw$line)
    if (count_in(r, block) == rw$written) {
      marks$first <- block
      return(r)
    }
  }
  stop("every block of Planes 15 and 16 is used by the line")
}

is_lone <- function(cps) cps >= marks$first & cps <= marks$first + 0x7FF

is_nul <- function(cps) cps == marks$first + 0x800

lone <- function(s) any(is_lone(utf8ToInt(s)))

# Whether a string has no R form: a lone surrogate, or a NUL.
unaskable <- function(s) {
  cps <- utf8ToInt(s)
  any(is_lone(cps) | is_nul(cps))
}

# UTF-8, a lone surrogate as U+FFFD (as String::from_utf16_lossy writes it).
lossy <- function(s) {
  cps <- utf8ToInt(s)
  if (!any(is_lone(cps))) {
    return(s)
  }
  cps[is_lone(cps)] <- 0xFFFD
  intToUtf8(cps)
}

# The UTF-16 code units of a text as read.
units <- function(s) {
  cps <- utf8ToInt(s)
  out <- integer(0L)
  for (c in cps) {
    out <- c(out, if (is_lone(c)) {
      0xD800 + c - marks$first
    } else if (c > 0xFFFF) {
      c(0xD800 + bitwShiftR(c - 0x10000, 10L), 0xDC00 + bitwAnd(c - 0x10000, 0x3FF))
    } else {
      c
    })
  }
  out
}

# The UTF-16 code units of s, printable ASCII as it is and anything else as \uXXXX.
escape <- function(s) {
  u <- units(s)
  paste0(ifelse(u >= 0x20 & u < 0x7F & u != 0x5C, vapply(u, function(x) intToUtf8(x), character(1L)),
                sprintf("\\u%04x", u)), collapse = "")
}

shown <- function(pattern) escape(lossy(pattern))

# For each UTF-16 code unit index of a text (and its end), R's character position of a start there (from 1) and of an
# end there (inclusive): a position between the halves of a character is the character's, for both.
positions <- function(s) {
  cps <- utf8ToInt(s)
  n <- length(cps)
  w <- ifelse(cps > 0xFFFF, 2L, 1L)
  points <- c(rep(seq_len(n) - 1L, w), n)
  ends <- points
  second <- cumsum(w)[w == 2L]
  ends[second] <- ends[second] + 1L
  list(start = points + 1L, end = ends)
}

new_counts <- function() c(right = 0, wrong = 0, refused = 0, accepted = 0, limited = 0, errors = 0)

compile_or_why <- function(pattern, flags) {
  tryCatch(list(re = ecma_regex(lossy(pattern), flags)), ecma_invalid_pattern = function(e) {
    list(message = paste("PARSE:", conditionMessage(e)), error = FALSE)
  }, ecma_pattern_too_large = function(e) {
    list(message = paste("TOO-LARGE:", conditionMessage(e)), error = FALSE)
  }, error = function(e) {
    list(message = paste("ERROR:", conditionMessage(e)), error = TRUE)
  })
}

modes_of <- function(r) {
  valid <- r$valid
  out <- list(list("u", "unicode", isTRUE(valid$unicode)), list("", "legacy", isTRUE(valid$legacy)))
  if (!is.null(valid$unicode_sets)) {
    out[[3L]] <- list("v", "unicode_sets", isTRUE(valid$unicode_sets))
  }
  out
}

judge_tests <- function(name, r, pattern, st) {
  flags <- if (is.null(r$flags)) "" else r$flags
  head_pattern <- shown(pattern)
  for (mode in modes_of(r)) {
    mode_flags <- paste0(flags, mode[[1L]])
    answer <- mode[[2L]]
    valid <- mode[[3L]]
    head <- sprintf("%s\t/%s/%s", name, head_pattern, mode_flags)
    compiled <- compile_or_why(pattern, mode_flags)
    if (is.null(compiled$re)) {
      if (compiled$error) st$c["errors"] <- st$c["errors"] + 1
      if (valid) {
        st$c["refused"] <- st$c["refused"] + 1
        st$w <- c(st$w, sprintf("REFUSED\t%s\t%s", head, strsplit(compiled$message, "\n", fixed = TRUE)[[1L]][1L]))
      }
      next
    }
    if (!valid) {
      st$c["accepted"] <- st$c["accepted"] + 1
      st$w <- c(st$w, sprintf("ACCEPTED-INVALID\t%s", head))
      next
    }
    tests <- Filter(function(t) is.logical(t[[answer]]) && length(t[[answer]]) == 1L && is.character(t$text) &&
                      !unaskable(t$text), r$tests)
    if (length(tests) == 0L) next
    texts <- vapply(tests, function(t) t$text, character(1L))
    expected <- vapply(tests, function(t) t[[answer]], logical(1L))
    got <- .Call(native$native_crer_first, compiled$re, texts, 1L, LIMIT, 0L)
    if (inherits(got, "crer_native_error")) {
      # A text reached its limit: each is asked alone.
      got <- vapply(texts, function(t) {
        one <- .Call(native$native_crer_first, compiled$re, t, 1L, LIMIT, 0L)
        if (inherits(one, "crer_native_error")) {
          if (one[[1L]] == "limit") {
            st$c["limited"] <- st$c["limited"] + 1
            st$w <- c(st$w, sprintf("LIMIT\t%s\t%s\tutf8\t%s", head, escape(t),
                                    if (grepl("memory", one[[2L]])) "memory" else "time"))
          } else {
            st$c["errors"] <- st$c["errors"] + 1
            st$w <- c(st$w, sprintf("ERROR\t%s\t%s\tutf8\t%s", head, escape(t), one[[2L]]))
          }
          return(NA)
        }
        one
      }, logical(1L), USE.NAMES = FALSE)
    }
    judged <- !is.na(got)
    right <- judged & got == expected
    st$c["right"] <- st$c["right"] + sum(right)
    bad <- which(judged & !right)
    st$c["wrong"] <- st$c["wrong"] + length(bad)
    for (i in bad) {
      st$w <- c(st$w, sprintf("WRONG\t%s\t%s\tutf8\texpected %s", head, escape(texts[i]),
                              if (expected[i]) "true" else "false"))
    }
  }
}

# The expected [start, end] pairs of a match's groups (NULL for one that did not take part) in R's positions.
expect_spans <- function(e, at) {
  unlist(lapply(e, function(g) if (is.null(g)) c(NA_integer_, NA_integer_) else c(at$start[g[[1L]] + 1L], at$end[g[[2L]] + 1L])))
}

# Whether a match's spans (the first 2 × groups of its row) are the expected groups; NULL expects no match.
same_slots <- function(expected, spans, groups, at) {
  if (is.null(expected) || is.na(spans[1L])) {
    return(is.null(expected) && is.na(spans[1L]))
  }
  length(expected) == groups && identical(as.integer(spans[seq_len(2L * groups)]), as.integer(expect_spans(expected, at)))
}

same_split <- function(expected, got) {
  is.list(expected) && length(expected) == length(got) &&
    all(mapply(function(e, g) if (is.null(e)) is.na(g) else !is.na(g) && lossy(e) == g, expected, got))
}

judge_mode <- function(where, a, text, re, g, y, st) {
  check <- function(what, ok) {
    if (isTRUE(ok)) {
      st$c["right"] <- st$c["right"] + 1
    } else {
      st$c["wrong"] <- st$c["wrong"] + 1
      st$w <- c(st$w, sprintf("WRONG\tcaptures.jsonl\t%s\t%s", where(), what))
    }
  }
  at <- positions(text)
  groups <- attr(re, "group_count") + 1L
  width <- groups + length(attr(re, "group_names"))
  spans <- .Call(native$native_crer_first, re, text, 1L, LIMIT, 2L)
  if (inherits(spans, "crer_native_error")) {
    if (spans[[1L]] != "limit") stop(spans[[2L]])
    st$c["limited"] <- st$c["limited"] + 1
    st$w <- c(st$w, sprintf("LIMIT\tcaptures.jsonl\t%s", where()))
    return(invisible())
  }
  check("exec", same_slots(a$exec, spans, groups, at))

  all <- if (is.null(a$all)) list() else a$all
  found <- .Call(native$native_crer_all, g, text, 3L)[[1L]]
  if (inherits(found, "crer_native_error")) stop(found[[2L]])
  k <- length(found) %/% (2L * width)
  n <- 0L
  ok <- TRUE
  for (i in seq_len(min(k, length(all)))) {
    e <- all[[i]]
    if (is.null(e) || !same_slots(e, found[(i - 1L) * 2L * width + seq_len(2L * width)], groups, at)) {
      ok <- FALSE
      break
    }
    n <- i
  }
  if ((length(all) < 20L && n != length(all)) || (length(all) == 20L && n < 20L)) ok <- FALSE
  check("all", ok)

  # Sticky at UTF-16 index 1, where that is a position of the text (not between the halves of a character).
  if (nzchar(text) && utf8ToInt(text)[1L] <= 0xFFFF) {
    check("sticky", same_slots(a$sticky, .Call(native$native_crer_first, y, text, 2L, LIMIT, 2L), groups, at))
  }

  check("replace", !is.null(a$replace) && ecma_replace(text, re, REPLACEMENT) == lossy(a$replace))
  check("replaceAll", !is.null(a$replaceAll) && ecma_replace(text, g, REPLACEMENT) == lossy(a$replaceAll))
  check("split", same_split(a$split, ecma_split(text, re)[[1L]]))
  check("split3", same_split(a$split3, ecma_split(text, re, limit = 3L)[[1L]]))
}

judge_captures <- function(r, pattern, st) {
  flags <- if (is.null(r$flags)) "" else r$flags
  valid <- r$valid
  head_pattern <- shown(pattern)
  cache <- list()
  make <- function(f) {
    if (is.null(cache[[paste0("_", f)]])) {
      compiled <- compile_or_why(pattern, f)
      cache[[paste0("_", f)]] <<- if (is.null(compiled$re)) FALSE else compiled$re
    }
    re <- cache[[paste0("_", f)]]
    if (isFALSE(re)) NULL else re
  }
  for (test in r$tests) {
    if (isTRUE(test$v8_deviation) || !is.character(test$text) || unaskable(test$text)) next
    text <- test$text
    for (mode in c("unicode", "legacy")) {
      if (!isTRUE(valid[[mode]]) || is.null(test[[mode]])) next
      mode_flags <- paste0(flags, if (mode == "unicode") "u" else "")
      where <- function() sprintf("/%s/%s\t%s", head_pattern, mode_flags, escape(text))
      re <- make(mode_flags)
      g <- make(paste0(mode_flags, "g"))
      y <- make(paste0(mode_flags, "y"))
      if (is.null(re) || is.null(g) || is.null(y)) {
        st$c["refused"] <- st$c["refused"] + 1
        st$w <- c(st$w, sprintf("REFUSED\tcaptures.jsonl\t%s", where()))
        next
      }
      tryCatch(judge_mode(where, test[[mode]], text, re, g, y, st), error = function(e) {
        st$c["errors"] <- st$c["errors"] + 1
        st$w <- c(st$w, sprintf("ERROR\tcaptures.jsonl\t%s\t%s", where(), conditionMessage(e)))
      })
    }
  }
}

judge_lines <- function(name, lines) {
  st <- new.env()
  st$c <- new_counts()
  st$w <- character(0L)
  records <- 0L
  skipped <- 0L
  for (line in lines) {
    if (!nzchar(trimws(line))) next
    r <- read_record(line)
    if (isTRUE(r$v8_deviation)) {
      skipped <- skipped + 1L
      next
    }
    records <- records + 1L
    if (!is.character(r$pattern) || any(is_nul(utf8ToInt(r$pattern)))) next
    if (name == "captures.jsonl") judge_captures(r, r$pattern, st) else judge_tests(name, r, r$pattern, st)
  }
  list(c = st$c, w = st$w, records = records, skipped = skipped)
}

main <- function(args) {
  if (length(args) < 2L) {
    cat("usage: Rscript tools/dataset.R <data directory> <wrong-cases file> [--files glob] [--workers N]\n")
    quit(status = 2L)
  }
  data <- args[[1L]]
  wrong_path <- args[[2L]]
  glob <- "*.jsonl"
  workers <- 4L
  i <- 3L
  while (i < length(args)) {
    if (args[[i]] == "--files") glob <- args[[i + 1L]]
    if (args[[i]] == "--workers") workers <- as.integer(args[[i + 1L]])
    i <- i + 2L
  }
  files <- sort(list.files(data, pattern = utils::glob2rx(glob)))
  files <- files[endsWith(files, ".jsonl")]
  total <- new_counts()
  wrong <- character(0L)
  records <- 0L
  skipped <- 0L
  start <- Sys.time()
  for (name in files) {
    lines <- readLines(file.path(data, name), encoding = "UTF-8", warn = FALSE)
    chunks <- split(lines, ceiling(seq_along(lines) / 200L))
    results <- mclapply(chunks, function(chunk) judge_lines(name, chunk), mc.cores = workers, mc.preschedule = FALSE)
    file_total <- new_counts()
    for (res in results) {
      if (inherits(res, "try-error")) stop(res)
      file_total <- file_total + res$c
      wrong <- c(wrong, res$w)
      records <- records + res$records
      skipped <- skipped + res$skipped
    }
    cat(sprintf("%-24s right %10.0f  wrong %6.0f  refused-valid %4.0f  accepted-invalid %4.0f  limit %4.0f  %6.1fs\n", name,
                file_total["right"], file_total["wrong"], file_total["refused"], file_total["accepted"],
                file_total["limited"], as.numeric(Sys.time() - start, units = "secs")))
    total <- total + file_total
  }
  writeLines(enc2utf8(sort(wrong, method = "radix")), file(wrong_path, encoding = "UTF-8"))
  cat(sprintf("\nrecords %d (skipped %d deviations)  right %.0f  wrong %.0f  refused-valid %.0f  accepted-invalid %.0f  limit %.0f  errors %.0f  in %.1fs\n",
              records, skipped, total["right"], total["wrong"], total["refused"], total["accepted"], total["limited"],
              total["errors"], as.numeric(Sys.time() - start, units = "secs")))
  quit(status = if (sum(total[c("wrong", "refused", "accepted", "errors", "limited")]) == 0) 0L else 1L)
}

main(commandArgs(trailingOnly = TRUE))
