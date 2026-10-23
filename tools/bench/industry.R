# The Industry benchmark from R: each workload counted by each engine, in nanoseconds per count, under the interleaved
# protocol every harness of the central benchmark page follows (docs/benchmarks/README.md in
# corvus-regex-ecma262-rs), a port of the C harness's driver (tools/c/industry.c there):
#
#   Rscript industry.R <workloads.json> [--engines corvus,pcre,tre,icu,v8] [--v8 <industry.mjs>] [--rounds 3]
#           [--seconds 0.7] [--passes 7] [--spread 0.05] [--filter <substring of the id>] [--out <results.json>]
#
# The workloads are the outer loop, each workload's rounds next and the engines innermost, their order turned by one
# each round, so that a workload's rounds are seconds apart, as its engines are. Each figure is a child process of its
# own (`Rscript industry.R --one`, or `node industry.mjs --one` for V8), which warms for two fifths of its seconds, then
# times `passes` passes of as many counts as fit the rest and reports their median. A workload's figure for an engine is
# the median of its rounds, with the fastest and the slowest round as its spread; a figure whose spread, (slowest -
# fastest) / median, is over --spread is listed in the run's facts (spread_over) and on stderr. A figure that does not
# finish in 30 s is stopped and recorded as giving no result within 30 s, and is not run in the workload's later rounds.
#
# The engines, each counting every match of a global search as an R program that wants every match would:
# - corvus: this package with the workload's flags and u, with ecma_count;
# - pcre: base R's gregexpr with perl = TRUE and useBytes = TRUE (PCRE2, with its JIT where R has it), which does not
#   claim ECMA-262, given the pattern as it is with the flags i, m and s and (*UTF) at its head, so that PCRE2 still
#   matches characters while gregexpr reports byte offsets, which a count does not need turned into characters;
# - tre: base R's gregexpr (TRE), which does not claim ECMA-262, the same way (it has no m or s flag, so a workload with
#   either is an error);
# - icu: stringi's stri_count_regex (ICU), which does not claim ECMA-262, the same way;
# - v8: Node's RegExp (--v8), with gu added.
# gregexpr and stri_count_regex take a pattern and compile it (or find it in a cache) in each call, as an R program uses
# them; ecma_count takes the pattern compiled once.
#
# The texts are those of the reference run, in CORVUS_REGEX_TEXTS (or ~/.local/share/corvus-regex-benchmarks); the run
# unzips each once into a directory of its own (CORVUS_REGEX_PLAIN), which the children read. POSIX only: the benchmark
# runs on Linux, in the image.
suppressPackageStartupMessages(library(jsonlite))

DEFAULT_ENGINES <- c("corvus", "pcre", "tre", "icu")
NOT_ECMA262 <- c("pcre", "tre", "icu")
LABELS <- c(corvus = "corvus-regex-ecma262", pcre = "PCRE2 (gregexpr, perl = TRUE)", tre = "TRE (gregexpr)",
            icu = "ICU (stringi)", v8 = "V8")

text_dir <- function() {
  dir <- Sys.getenv("CORVUS_REGEX_TEXTS")
  if (nzchar(dir)) dir else file.path(path.expand("~"), ".local", "share", "corvus-regex-benchmarks")
}

load_text <- function(file) {
  plain <- Sys.getenv("CORVUS_REGEX_PLAIN")
  name <- sub("\\.gz$", "", file)
  if (nzchar(plain) && file.exists(file.path(plain, name))) {
    return(readChar(file.path(plain, name), file.size(file.path(plain, name)), useBytes = TRUE) |> enc_utf8())
  }
  con <- gzfile(file.path(text_dir(), file), "rb")
  on.exit(close(con))
  bytes <- readBin(con, "raw", n = 1e9)
  s <- enc_utf8(rawToChar(bytes))
  sub("^﻿", "", s)
}

enc_utf8 <- function(s) {
  Encoding(s) <- "UTF-8"
  s
}

flags_u <- function(flags) if (grepl("[uv]", flags)) flags else paste0(flags, "u")

now <- function() proc.time()[["elapsed"]]

# Warms, then times passes: the median, the fastest and the slowest pass in nanoseconds per count, the count, and the
# counts timed.
measure <- function(seconds, passes, count) {
  expected <- count()
  warm_end <- now() + seconds * 0.4
  reps <- 0L
  while (now() < warm_end) {
    if (count() != expected) stop("the count changed")
    reps <- reps + 1L
  }
  per_pass <- max(1L, round(reps * 0.6 / passes))
  times <- numeric(passes)
  for (p in seq_len(passes)) {
    t0 <- Sys.time()
    for (i in seq_len(per_pass)) count()
    times[p] <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1e9 / per_pass
  }
  times <- sort(times)
  list(median = times[passes %/% 2L + 1L], min = times[1L], max = times[passes], count = expected,
       reps = per_pass * passes)
}

one <- function(path, index, engine, seconds, passes) {
  workloads <- fromJSON(path, simplifyVector = FALSE)
  if (index >= length(workloads)) {
    return(list(error = sprintf("no workload %d", index)))
  }
  w <- workloads[[index + 1L]]
  text <- load_text(w$file)
  pattern <- w$pattern
  flags <- w$flags
  inline <- paste(strsplit(gsub("[^ims]", "", flags), "")[[1L]], collapse = "")
  tryCatch({
    count <- switch(engine,
      corvus = {
        suppressPackageStartupMessages(library(corvusregexecma262))
        re <- ecma_regex(pattern, flags_u(flags))
        function() ecma_count(text, re)
      },
      pcre = {
        # Without useBytes, gregexpr turns each match's byte offset into a character position by counting the characters
        # from the start of the text, so a count of a UTF-8 text that is not all ASCII cost the matches times the length
        # (the Holmes workload 300 ms, and twenty workloads over 30 s, on 2026-10-23). With useBytes it reports the byte
        # offsets as they are, and (*UTF) keeps PCRE2 in UTF mode, so that ., classes, \p{..} and case folding still see
        # characters. Every workload counts as it did. PCRE2 still checks the UTF-8 from each search's start to the end of
        # the text, since R asks it to with useBytes, so a workload with many thousands of matches still costs more than
        # one pass over the text; R's own UTF-8 mode, which skips that check, is the one that converts the offsets.
        p <- paste0("(*UTF)", if (nzchar(inline)) paste0("(?", inline, ")", pattern) else pattern)
        function() {
          m <- gregexpr(p, text, perl = TRUE, useBytes = TRUE)[[1L]]
          if (m[1L] == -1L) 0L else length(m)
        }
      },
      tre = {
        if (grepl("[ms]", flags)) stop("TRE has no m or s flag")
        ignore <- grepl("i", flags)
        function() {
          m <- gregexpr(pattern, text, ignore.case = ignore)[[1L]]
          if (m[1L] == -1L) 0L else length(m)
        }
      },
      icu = {
        suppressPackageStartupMessages(library(stringi))
        opts <- stri_opts_regex(case_insensitive = grepl("i", flags), multiline = grepl("m", flags),
                                dotall = grepl("s", flags))
        function() stri_count_regex(text, pattern, opts_regex = opts)
      },
      stop(sprintf("unknown engine %s", engine))
    )
    m <- measure(seconds, passes, count)
    list(median = round(m$median, 1), min = round(m$min, 1), max = round(m$max, 1), count = m$count, reps = m$reps)
  }, error = function(e) list(error = conditionMessage(e)), warning = function(e) list(error = conditionMessage(e)))
}

# A figure stopped at the limit, which the page shows as giving no result within 30 s.
STOPPED <- list(error = "did not produce a result within 30 s", limit = 30L)

# One figure in a child process: the child's line of JSON, or one with the error.
figure <- function(script, v8, path, index, engine, seconds, passes) {
  out <- if (engine == "v8") {
    suppressWarnings(system2("node", c(v8, "--one", path, index, seconds, passes), stdout = TRUE, stderr = FALSE,
                             timeout = 30))
  } else {
    suppressWarnings(system2(file.path(R.home("bin"), "Rscript"), c(script, "--one", path, index, engine, seconds, passes),
                             stdout = TRUE, stderr = FALSE, timeout = 30))
  }
  status <- attr(out, "status")
  if (!is.null(status) && status == 124L) {
    return(STOPPED)
  }
  out <- out[nzchar(out)]
  if (length(out) == 0L) {
    return(list(error = "the process ended without figures"))
  }
  tryCatch(fromJSON(out[length(out)], simplifyVector = FALSE), error = function(e) list(error = "the process wrote no figures"))
}

first_line <- function(cmd) {
  out <- tryCatch(suppressWarnings(system(cmd, intern = TRUE, ignore.stderr = TRUE)), error = function(e) character(0L))
  if (length(out)) trimws(out[1L]) else ""
}

field <- function(path, prefix) {
  lines <- tryCatch(readLines(path, warn = FALSE), error = function(e) character(0L))
  hit <- lines[startsWith(lines, prefix)]
  if (length(hit)) trimws(sub("^[^:]*:", "", hit[1L])) else ""
}

option <- function(args, name, default = NULL) {
  k <- match(paste0("--", name), args)
  if (is.na(k)) default else args[[k + 1L]]
}

main <- function(args) {
  script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
  if (length(args) && args[[1L]] == "--one") {
    result <- one(args[[2L]], as.integer(args[[3L]]), args[[4L]], as.numeric(args[[5L]]), as.integer(args[[6L]]))
    cat(toJSON(result, auto_unbox = TRUE, digits = NA), "\n", sep = "")
    return(invisible())
  }
  path <- args[[1L]]
  v8 <- option(args, "v8")
  engines <- if (is.null(option(args, "engines"))) c(DEFAULT_ENGINES, if (!is.null(v8)) "v8") else
    strsplit(option(args, "engines"), ",")[[1L]]
  rounds <- as.integer(option(args, "rounds", "3"))
  seconds <- option(args, "seconds", "0.7")
  passes <- option(args, "passes", "7")
  limit <- as.numeric(option(args, "spread", "0.05"))
  filter <- option(args, "filter")
  workloads <- fromJSON(path, simplifyVector = FALSE)
  ids <- vapply(workloads, function(w) w$id, character(1L))
  chosen <- which(is.null(filter) | grepl(if (is.null(filter)) "" else filter, ids, fixed = TRUE)) - 1L

  # The texts unzipped once, for every child.
  plain <- tempfile("corvus-regex-texts-r-")
  dir.create(plain)
  for (w in workloads) {
    target <- file.path(plain, sub("\\.gz$", "", w$file))
    if (!file.exists(target)) writeBin(charToRaw(load_text(w$file)), target)
  }
  Sys.setenv(CORVUS_REGEX_PLAIN = plain)

  figures <- list()
  v8_engine <- ""
  for (c in seq_along(chosen)) {
    k <- chosen[[c]]
    key <- as.character(k)
    for (rnd in seq_len(rounds) - 1L) {
      for (turn in seq_along(engines) - 1L) {
        e <- engines[[(turn + rnd) %% length(engines) + 1L]]
        # A figure stopped at the limit in an earlier round is not run again.
        if (identical(figures[[e]][[key]]$line, STOPPED)) next
        line <- figure(script, v8, path, k, e, seconds, passes)
        fig <- figures[[e]][[key]]
        if (is.null(fig)) fig <- list(each = numeric(0L))
        fig$line <- line
        if (!is.null(line$median)) {
          fig$each <- c(fig$each, line$median)
        } else {
          message(sprintf("%-13s %-62s %s", e, ids[[k + 1L]], toJSON(line, auto_unbox = TRUE)))
        }
        figures[[e]][[key]] <- fig
        if (e == "v8" && !is.null(line$engine)) v8_engine <- line$engine
      }
    }
    message(sprintf("workload %d of %d done", c, length(chosen)))
  }
  unlink(plain, recursive = TRUE)

  over <- character(0L)
  differ <- character(0L)
  results <- list()
  for (e in engines) {
    rows <- list()
    for (k in chosen) {
      key <- as.character(k)
      wid <- ids[[k + 1L]]
      fig <- figures[[e]][[key]]
      each <- fig$each
      line <- fig$line
      if (length(each) < rounds) {
        # A round with no figure (an error, a limit) makes the figure an error.
        rows[[wid]] <- if (!is.null(line$error)) line else list(error = "a round gave no figure")
        next
      }
      m <- median(each)
      spread <- if (m > 0) (max(each) - min(each)) / m else 0
      if (spread > limit) {
        over <- c(over, sprintf("%s %s %.1f%%", e, wid, spread * 100))
        message(sprintf("SPREAD %-13s %-62s %.1f%% over %.1f%%", e, wid, spread * 100, limit * 100))
      }
      n <- line$count
      entry <- list(median = round(m, 1), min = min(each), max = max(each), count = n, rounds = length(each),
                    spread = round(spread, 4), each = I(each))
      # Without V8 in the run (V8=0), its count as the workloads carry it (v8Count, from the central run).
      oracle <- if (!is.null(figures[["v8"]])) figures[["v8"]][[key]]$line$count else workloads[[k + 1L]]$v8Count
      if (!is.null(oracle) && n != oracle && e != "v8") {
        differ <- c(differ, sprintf("%s %s %d vs V8 %d", e, wid, n, oracle))
        message(sprintf("COUNT  %-13s %-62s %d against V8's %d", e, wid, n, oracle))
        if (e %in% NOT_ECMA262) {
          entry$differs <- sprintf("%s %d, V8 %d", LABELS[[e]], n, oracle)
        } else {
          entry <- list(error = sprintf("counted %d where V8 counts %d", n, oracle))
        }
      }
      rows[[wid]] <- entry
    }
    results[[e]] <- rows
  }

  suppressPackageStartupMessages(library(corvusregexecma262))
  icu <- if (requireNamespace("stringi", quietly = TRUE)) stringi::stri_info()$ICU.version else ""
  stringi_version <- if (requireNamespace("stringi", quietly = TRUE)) as.character(utils::packageVersion("stringi")) else ""
  commit <- Sys.getenv("CORVUS_COMMIT")
  facts <- list(
    cpu = field("/proc/cpuinfo", "model name"),
    cores = as.character(parallel::detectCores()),
    affinity = field("/proc/self/status", "Cpus_allowed_list"),
    os = paste(Sys.info()[["sysname"]], Sys.info()[["release"]]),
    load = first_line("cut -d' ' -f1 /proc/loadavg"),
    r = R.version.string,
    commit = if (nzchar(commit)) commit else first_line("git rev-parse HEAD 2>/dev/null"),
    date = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    seconds = seconds,
    passes = passes,
    runner = Sys.getenv("RUNNER_NAME"),
    runner_os = Sys.getenv("RUNNER_OS"),
    image = trimws(paste(Sys.getenv("ImageOS"), Sys.getenv("ImageVersion"))),
    "corvus-regex-ecma262" = ecma_version()[["package"]],
    pcre = unname(extSoftVersion()[["PCRE"]]),
    icu = paste0("ICU ", icu, if (nzchar(stringi_version)) paste0(" (stringi ", stringi_version, ")") else ""),
    tre = paste0("R ", getRversion()),
    rounds = as.character(rounds),
    protocol = "interleaved",
    spread_limit = format(limit),
    spread_over = paste(over, collapse = "; "),
    counts_differ = paste(differ, collapse = "; "),
    v8 = v8_engine
  )
  data <- list(facts = facts, end = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), results = results)
  json <- toJSON(data, auto_unbox = TRUE, digits = NA, null = "null")
  out <- option(args, "out")
  if (is.null(out)) cat(json, "\n") else writeLines(json, out, useBytes = TRUE)
}

main(commandArgs(trailingOnly = TRUE))
