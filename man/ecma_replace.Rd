\name{ecma_replace}
\alias{ecma_replace}
\alias{ecma_replace_all}
\title{Replace Matches}
\description{
\code{ecma_replace} replaces the first match in each string, or every match when the pattern has the \code{g} flag
(\code{String.prototype.replace}); \code{ecma_replace_all} replaces every match (\code{replaceAll}).
}
\usage{
ecma_replace(x, regex, replacement)

ecma_replace_all(x, regex, replacement)
}
\arguments{
\item{x}{A character vector.}
\item{regex}{A regular expression from \code{\link{ecma_regex}}, or a pattern compiled without flags.}
\item{replacement}{A character vector of templates (recycled), or a function. In a template, \verb{$&} is the match,
  \verb{$`} and \verb{$'} the text before and after it, \code{$1} to \code{$99} a group, \code{$<name>} a named group,
  and \code{$$} a dollar sign; anything else is itself. A function is called with each match's row, as
  \code{\link{ecma_match}} lays it out (a named character vector), and returns one string.}
}
\value{
A character vector, \code{NA} where the string or its template is \code{NA}. A match that takes half of a character
leaves the other half as U+FFFD.
}
\examples{
date <- ecma_regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})", "g")
ecma_replace("2026-10, 2027-01", date, "$<month>/$1")
ecma_replace_all("1 2 3", "\\\\d+", function(m) as.character(as.integer(m[[1]]) * 2))
}
