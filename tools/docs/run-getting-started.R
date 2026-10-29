# Runs each block of R on the getting-started page the documentation site publishes (docs/getting-started.md), each in
# an environment of its own, against the installed package, so that the page shows only code that works:
#   Rscript tools/docs/run-getting-started.R
# A block that stops (a failed stopifnot) fails the script.

page <- readLines("docs/getting-started.md", encoding = "UTF-8", warn = FALSE)
starts <- which(page == "```r")
blocks <- lapply(starts, function(s) {
  end <- s + which(page[(s + 1):length(page)] == "```")[1]
  page[(s + 1):(end - 1)]
})
if (length(blocks) < 5) stop("the page has ", length(blocks), " examples")

failed <- character()
for (n in seq_along(blocks)) {
  ok <- tryCatch({
    eval(parse(text = blocks[[n]], encoding = "UTF-8"), envir = new.env(parent = globalenv()))
    TRUE
  }, error = function(e) {
    message("docs/getting-started.md:", starts[n] + 1, ": ", conditionMessage(e))
    FALSE
  })
  if (ok) cat("example", n, "ok\n") else failed <- c(failed, as.character(n))
}
if (length(failed)) stop("the getting-started examples that failed: ", paste(failed, collapse = ", "))
cat(length(blocks), "getting-started examples ran.\n")
