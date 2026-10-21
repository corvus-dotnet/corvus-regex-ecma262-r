\name{ecma_test}
\alias{ecma_test}
\alias{ecma_match}
\alias{ecma_locate}
\title{Test, Match and Locate the First Match}
\description{
For each string, \code{ecma_test} says whether the pattern matches (\code{RegExp.prototype.test}),
\code{ecma_match} gives the first match and what each group captured (\code{exec}), and \code{ecma_locate} gives where
the first match, or one of its groups, starts and ends.
}
\usage{
ecma_test(x, regex, start = 1L, timeout = NULL)

ecma_match(x, regex, start = 1L, timeout = NULL)

ecma_locate(x, regex, group = 0L, start = 1L, timeout = NULL)
}
\arguments{
\item{x}{A character vector.}
\item{regex}{A regular expression from \code{\link{ecma_regex}}, or a pattern compiled without flags.}
\item{start}{Where each search starts, in characters from 1 (recycled), as \code{lastIndex} sets it: with the
  \code{y} flag a match must start there.}
\item{timeout}{A limit, in seconds, on the time each match may take, or \code{NULL} for none.}
\item{group}{The group to locate, by number (0 is the whole match) or by name.}
}
\value{
\code{ecma_test} returns a logical vector. \code{ecma_match} returns a character matrix with a row for each string:
the match, then each group, then one column for each group name (named by it: of the groups that share a name, the one
that took part). \code{ecma_locate} returns an integer matrix with the columns \code{start} and \code{end}. An empty
match ends one character before it starts. There is \code{NA} for an \code{NA} string, for a string the pattern does
not match, and for a group that did not take part.
}
\section{Limits}{
A match that reaches \code{timeout}, or the cap on backtracking memory, raises \code{ecma_match_limit}. A pattern
without a backreference is matched in time proportional to its size times the text.
}
\examples{
date <- ecma_regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
ecma_test(c("due 2026-10", "none", NA), date)
ecma_match("due 2026-10", date)
ecma_locate("due 2026-10", date, group = "month")
ecma_test(c("foo", "foo"), ecma_regex("o", "y"), start = c(1L, 2L))
}
