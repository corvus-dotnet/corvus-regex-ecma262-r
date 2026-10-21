# ECMA-262 (JavaScript) regular expressions for R, backed by the corvus-regex-ecma262 Rust crate: the grammar and the
# answers of RegExp, every flag, over R's strings (as UTF-8).
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

ecma_regex <- function(pattern, flags = "") {
  if (inherits(pattern, "ecma_regex")) {
    return(pattern)
  }
  ptr <- checked(.Call(native_crer_compile, pattern, flags))
  info <- .Call(native_crer_info, ptr)
  structure(ptr, source = info[[1L]], flags = info[[2L]], group_count = info[[3L]], group_names = info[[4L]],
            class = "ecma_regex")
}

ecma_valid <- function(pattern, flags = "") {
  checked(.Call(native_crer_valid, pattern, flags))
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

# The rows the native code gives, `width` entries each, as a matrix with a row for each.
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
  checked(.Call(native_crer_first, regex, x, as.integer(start), timeout_of(timeout), 0L))
}

ecma_match <- function(x, regex, start = 1L, timeout = NULL) {
  regex <- as_regex(regex)
  as_rows(checked(.Call(native_crer_first, regex, x, as.integer(start), timeout_of(timeout), 1L)), regex)
}

ecma_locate <- function(x, regex, group = 0L, start = 1L, timeout = NULL) {
  regex <- as_regex(regex)
  g <- group_index(regex, group)
  spans <- checked(.Call(native_crer_first, regex, x, as.integer(start), timeout_of(timeout), 2L))
  width <- length(row_names(regex))
  spans <- matrix(spans, ncol = 2L * width, byrow = TRUE)
  out <- spans[, c(2L * g - 1L, 2L * g), drop = FALSE]
  colnames(out) <- c("start", "end")
  out
}

ecma_match_all <- function(x, regex) {
  regex <- as_regex(regex)
  lapply(checked(.Call(native_crer_all, regex, x, 1L)), function(rows) {
    if (is.null(rows)) NULL else as_rows(rows, regex)
  })
}

ecma_locate_all <- function(x, regex, group = 0L) {
  regex <- as_regex(regex)
  g <- group_index(regex, group)
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
  checked(.Call(native_crer_count, as_regex(regex), x))
}

ecma_replace <- function(x, regex, replacement) {
  replace_with(x, as_regex(regex), replacement, FALSE)
}

ecma_replace_all <- function(x, regex, replacement) {
  replace_with(x, as_regex(regex), replacement, TRUE)
}

replace_with <- function(x, regex, replacement, all) {
  if (!is.function(replacement)) {
    return(checked(.Call(native_crer_replace, regex, x, replacement, all)))
  }
  names <- row_names(regex)
  width <- length(names)
  vapply(checked(.Call(native_crer_pieces, regex, x, all)), function(item) {
    if (is.null(item)) {
      return(NA_character_)
    }
    pieces <- item[[1L]]
    k <- length(pieces) - 1L
    if (k == 0L) {
      return(pieces)
    }
    groups <- item[[2L]]
    made <- vapply(seq_len(k), function(i) {
      row <- groups[((i - 1L) * width + 1L):(i * width)]
      names(row) <- names
      value <- replacement(row)
      if (!is.character(value) || length(value) != 1L) {
        stop("a replacement function must return one string", call. = FALSE)
      }
      value
    }, character(1L))
    paste0(c(rbind(pieces[-length(pieces)], made), pieces[length(pieces)]), collapse = "")
  }, character(1L), USE.NAMES = FALSE)
}

ecma_split <- function(x, regex, limit = NULL) {
  regex <- as_regex(regex)
  limit <- if (is.null(limit)) NA_integer_ else as.integer(limit)
  checked(.Call(native_crer_split, regex, x, limit))
}

ecma_version <- function() {
  v <- checked(.Call(native_crer_version))
  c(package = v[[1L]], crate = v[[2L]])
}

print.ecma_regex <- function(x, ...) {
  cat(sprintf("<ecma_regex> /%s/%s\n", attr(x, "source"), attr(x, "flags")))
  invisible(x)
}

format.ecma_regex <- function(x, ...) {
  sprintf("/%s/%s", attr(x, "source"), attr(x, "flags"))
}
