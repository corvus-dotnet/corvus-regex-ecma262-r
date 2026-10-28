# ECMA-262 (JavaScript) regular expressions for R, backed by the corvus-regex-ecma262 Rust crate: the grammar and the
# answers of RegExp, every flag, over R's strings (as UTF-8), raw vectors of UTF-8 (which may hold a NUL) and
# ecma_utf16 texts of UTF-16 code units (which may hold lone surrogates, as a JavaScript string can).
#
#   date <- ecma_regex("(?<year>\\d{4})-(?<month>\\d{2})", "g")
#   ecma_test(c("due 2026-10", "none"), date)       # TRUE FALSE
#   ecma_match("due 2026-10", date)[, "year"]       # "2026"
#
# The native code (src/rust) returns a failure as a list of class crer_native_error, which is raised here.

# Raises the condition of a failure the native code returned, or gives the value back.
checked <- function(value, call = sys.call(-1L)) {
  if (!inherits(value, "crer_native_error")) {
    return(value)
  }
  kind <- switch(value[[1L]],
    pattern = "ecma_invalid_pattern",
    flags = "ecma_invalid_flags",
    too_large = "ecma_pattern_too_large",
    limit = "ecma_match_limit",
    encoding = "ecma_encoding_error",
    argument = "ecma_argument_error",
    "ecma_internal_error"
  )
  stop(structure(
    class = c(kind, "ecma_regex_error", "error", "condition"),
    list(message = value[[2L]], call = call)
  ))
}

.onLoad <- function(libname, pkgname) {
  .Call(native_crer_set_utf8_session, isTRUE(l10n_info()[["UTF-8"]]))
  invisible()
}

ecma_regex <- function(pattern, flags = "", timeout = NULL, edition = "current", unicode_version = NULL) {
  if (inherits(pattern, "ecma_regex")) {
    return(pattern)
  }
  if (inherits(pattern, "ecma_utf16")) {
    stop("a pattern must be a string or a raw vector of UTF-8", call. = FALSE)
  }
  ptr <- checked(.Call(native_crer_compile, pattern, flags, timeout_of(timeout), edition_code(edition),
                       unicode_version_code(unicode_version)))
  info <- .Call(native_crer_info, ptr)
  structure(ptr, source = info[[1L]], flags = info[[2L]], group_count = info[[3L]], group_names = info[[4L]],
            timeout = if (is.na(info[[5L]])) NULL else info[[5L]], edition = info[[6L]], unicode_version = info[[7L]],
            class = "ecma_regex")
}

# The native code of an edition: 0 for "current" (today's grammar), 1 for "es2020".
edition_code <- function(edition) {
  if (!is.character(edition) || length(edition) != 1L || is.na(edition) || !(edition %in% c("current", "es2020"))) {
    stop("edition must be \"current\" or \"es2020\"", call. = FALSE)
  }
  if (edition == "es2020") 1L else 0L
}

# The native code of a version of Unicode: 0 for NULL (V8's), 13, 17 or 18 as themselves, -1 for "latest".
unicode_version_code <- function(unicode_version) {
  if (is.null(unicode_version)) {
    return(0L)
  }
  if (identical(unicode_version, "latest")) {
    return(-1L)
  }
  if (is.numeric(unicode_version) && length(unicode_version) == 1L && !is.na(unicode_version) &&
      unicode_version %in% ecma_unicode_versions()) {
    return(as.integer(unicode_version))
  }
  stop("unicode_version must be NULL, 13, 17, 18 or \"latest\"", call. = FALSE)
}

ecma_unicode_versions <- function() c(13L, 17L, 18L)

ecma_default_unicode_version <- function() 17L

ecma_latest_unicode_version <- function() 18L

ecma_set_default_timeout <- function(seconds) {
  checked(.Call(native_crer_set_default_timeout, timeout_of(seconds)))
  invisible()
}

ecma_default_timeout <- function() {
  t <- .Call(native_crer_default_timeout)
  if (is.na(t)) NULL else t
}

ecma_valid <- function(pattern, flags = "", edition = "current", unicode_version = NULL) {
  if (is.raw(pattern)) {
    pattern <- list(pattern)
  }
  checked(.Call(native_crer_valid, pattern, flags, edition_code(edition), unicode_version_code(unicode_version)))
}

ecma_utf16 <- function(x) {
  if (inherits(x, "ecma_utf16")) {
    return(x)
  }
  units <- if (is.character(x) || is.raw(x)) {
    if (is.character(x) && length(x) != 1L) {
      stop("x must be one string", call. = FALSE)
    }
    checked(.Call(native_crer_utf16, x))
  } else if (is.numeric(x)) {
    units <- as.integer(x)
    if (anyNA(units) || any(units < 0L | units > 65535L) || any(units != x)) {
      stop("a UTF-16 code unit must be a number from 0 to 65535", call. = FALSE)
    }
    units
  } else {
    stop("x must be a string, a raw vector of UTF-8 or code units", call. = FALSE)
  }
  structure(as.integer(units), class = "ecma_utf16")
}

as.character.ecma_utf16 <- function(x, ...) {
  checked(.Call(native_crer_from_utf16, x, FALSE))
}

as.raw.ecma_utf16 <- function(x) {
  checked(.Call(native_crer_from_utf16, x, TRUE))
}

print.ecma_utf16 <- function(x, ...) {
  u <- unclass(x)
  shown <- vapply(u, function(c) {
    if (c >= 0x20L && c < 0x7FL && c != 0x5CL) intToUtf8(c) else sprintf("\\u%04X", c)
  }, character(1L))
  cat(sprintf("<ecma_utf16[%d]> \"%s\"\n", length(u), paste(shown, collapse = "")))
  invisible(x)
}

`[.ecma_utf16` <- function(x, i) structure(unclass(x)[i], class = "ecma_utf16")

c.ecma_utf16 <- function(...) {
  structure(unlist(lapply(list(...), function(p) unclass(ecma_utf16(p)))), class = "ecma_utf16")
}

# The texts of x for the native code, a character vector or a list: a raw vector or an ecma_utf16 alone is one text,
# given back alone (see one_back).
texts_of <- function(x) {
  if (is.raw(x) || inherits(x, "ecma_utf16")) {
    return(structure(list(x), one = TRUE))
  }
  if (is.list(x)) {
    for (t in x) {
      if (!(is.null(t) || is.raw(t) || inherits(t, "ecma_utf16") || (is.character(t) && length(t) == 1L))) {
        stop("each text in a list must be a raw vector of UTF-8, an ecma_utf16 or NULL", call. = FALSE)
      }
    }
  }
  x
}

# The result for one text alone given back alone.
one_back <- function(result, x) {
  if (isTRUE(attr(x, "one"))) result[[1L]] else result
}

# A regular expression from ecma_regex(), or a pattern compiled without flags.
as_regex <- function(regex) {
  if (inherits(regex, "ecma_regex")) regex else ecma_regex(regex)
}

timeout_of <- function(timeout) {
  if (is.null(timeout)) NA_real_ else as.double(timeout)
}

# The column names of a match's row: the match, each group, then each name.
row_names <- function(regex) {
  c("", rep("", attr(regex, "group_count")), attr(regex, "group_names"))
}

# The rows the native code gives, `width` entries each, as a matrix with a row for each (a list matrix for texts
# that are not strings).
as_rows <- function(values, regex) {
  names <- row_names(regex)
  matrix(values, ncol = length(names), byrow = TRUE, dimnames = list(NULL, names))
}

# The index in a match's row of a group given by number or by name.
group_index <- function(regex, group) {
  if (is.character(group)) {
    k <- match(group, attr(regex, "group_names"))
    if (length(group) != 1L || is.na(k)) {
      stop(sprintf("the pattern has no group named %s", paste(group, collapse = ", ")), call. = FALSE)
    }
    return(1L + attr(regex, "group_count") + k)
  }
  group <- as.integer(group)
  if (length(group) != 1L || is.na(group) || group < 0L || group > attr(regex, "group_count")) {
    stop(sprintf("the pattern has no group %s", paste(group, collapse = ", ")), call. = FALSE)
  }
  group + 1L
}

ecma_test <- function(x, regex, start = 1L, timeout = NULL) {
  regex <- as_regex(regex)
  x <- texts_of(x)
  checked(.Call(native_crer_first, regex, x, as.integer(start), timeout_of(timeout), 0L))
}

ecma_match <- function(x, regex, start = 1L, timeout = NULL) {
  regex <- as_regex(regex)
  x <- texts_of(x)
  as_rows(checked(.Call(native_crer_first, regex, x, as.integer(start), timeout_of(timeout), 1L)), regex)
}

ecma_locate <- function(x, regex, group = 0L, start = 1L, timeout = NULL) {
  regex <- as_regex(regex)
  g <- group_index(regex, group)
  x <- texts_of(x)
  spans <- checked(.Call(native_crer_first, regex, x, as.integer(start), timeout_of(timeout), 2L))
  width <- length(row_names(regex))
  spans <- matrix(spans, ncol = 2L * width, byrow = TRUE)
  out <- spans[, c(2L * g - 1L, 2L * g), drop = FALSE]
  colnames(out) <- c("start", "end")
  out
}

ecma_match_all <- function(x, regex) {
  regex <- as_regex(regex)
  x <- texts_of(x)
  lapply(checked(.Call(native_crer_all, regex, x, 1L)), function(rows) {
    if (is.null(rows)) NULL else as_rows(rows, regex)
  })
}

ecma_locate_all <- function(x, regex, group = 0L) {
  regex <- as_regex(regex)
  g <- group_index(regex, group)
  x <- texts_of(x)
  if (g == 1L) {
    return(lapply(checked(.Call(native_crer_all, regex, x, 2L)), function(spans) {
      if (is.null(spans)) NULL else matrix(spans, ncol = 2L, byrow = TRUE, dimnames = list(NULL, c("start", "end")))
    }))
  }
  width <- length(row_names(regex))
  lapply(checked(.Call(native_crer_all, regex, x, 3L)), function(spans) {
    if (is.null(spans)) {
      return(NULL)
    }
    spans <- matrix(spans, ncol = 2L * width, byrow = TRUE)
    out <- spans[, c(2L * g - 1L, 2L * g), drop = FALSE]
    colnames(out) <- c("start", "end")
    out
  })
}

ecma_count <- function(x, regex) {
  checked(.Call(native_crer_count, as_regex(regex), texts_of(x)))
}

ecma_replace <- function(x, regex, replacement) {
  replace_with(x, as_regex(regex), replacement, FALSE)
}

ecma_replace_all <- function(x, regex, replacement) {
  replace_with(x, as_regex(regex), replacement, TRUE)
}

replace_with <- function(x, regex, replacement, all) {
  x <- texts_of(x)
  if (!is.function(replacement)) {
    if (is.raw(replacement) || inherits(replacement, "ecma_utf16")) {
      replacement <- list(replacement)
    }
    return(one_back(checked(.Call(native_crer_replace, regex, x, replacement, all)), x))
  }
  names <- row_names(regex)
  width <- length(names)
  made <- lapply(checked(.Call(native_crer_pieces, regex, x, all)), function(item) {
    if (is.null(item)) {
      return(if (is.character(x)) NA_character_ else NULL)
    }
    pieces <- item[[1L]]
    k <- length(pieces) - 1L
    if (k == 0L) {
      return(pieces[[1L]])
    }
    groups <- item[[2L]]
    like <- pieces[[1L]]
    values <- lapply(seq_len(k), function(i) {
      row <- groups[((i - 1L) * width + 1L):(i * width)]
      names(row) <- names
      in_form(replacement(row), like)
    })
    joined <- c(rbind(as.list(pieces[-length(pieces)]), values), list(pieces[[length(pieces)]]))
    if (is.character(like)) paste0(unlist(joined), collapse = "") else do.call(c, joined)
  })
  if (is.character(x)) {
    return(vapply(made, identity, character(1L), USE.NAMES = FALSE))
  }
  one_back(made, x)
}

# A replacement function's value in the form of the text: one string, or for a raw vector or an ecma_utf16 text, one
# of the same or a string.
in_form <- function(value, like) {
  if (is.character(value) && length(value) == 1L && (is.character(like) || !is.na(value))) {
    if (is.character(like)) {
      return(value)
    }
    return(if (is.raw(like)) charToRaw(enc2utf8(value)) else ecma_utf16(value))
  }
  if (is.raw(like) && is.raw(value)) {
    return(value)
  }
  if (inherits(like, "ecma_utf16") && inherits(value, "ecma_utf16")) {
    return(value)
  }
  stop(if (is.character(like)) "a replacement function must return one string" else
    "a replacement function must return one string, or a text in the form of the one matched", call. = FALSE)
}

ecma_split <- function(x, regex, limit = NULL) {
  regex <- as_regex(regex)
  limit <- if (is.null(limit)) NA_integer_ else as.integer(limit)
  checked(.Call(native_crer_split, regex, texts_of(x), limit))
}

ecma_version <- function() {
  v <- checked(.Call(native_crer_version))
  c(package = v[[1L]], crate = v[[2L]])
}

print.ecma_regex <- function(x, ...) {
  cat(sprintf("<ecma_regex> %s\n", format(x)))
  invisible(x)
}

format.ecma_regex <- function(x, ...) {
  sprintf("/%s/%s", shown_source(attr(x, "source")), attr(x, "flags"))
}

# A source as a string: one held as a raw vector (for its NUL) with each NUL written as the escape \0.
shown_source <- function(source) {
  if (!is.raw(source)) {
    return(source)
  }
  bytes <- unlist(lapply(as.integer(source), function(b) if (b == 0L) c(0x5CL, 0x30L) else b))
  s <- rawToChar(as.raw(bytes))
  Encoding(s) <- "UTF-8"
  s
}
