\name{ecma_match_all}
\alias{ecma_match_all}
\alias{ecma_locate_all}
\alias{ecma_count}
\title{Every Match of a Global Search}
\description{
For each string, \code{ecma_match_all} gives every match of a global search and what each group captured
(\code{matchAll}), \code{ecma_locate_all} where each match, or one of its groups, starts and ends, and \code{ecma_count} how many there are.
After an empty match the search goes on one character later (one code unit without \code{u} or \code{v}); with the
\code{y} flag each match must start where the one before it ended.
}
\usage{
ecma_match_all(x, regex)

ecma_locate_all(x, regex, group = 0L)

ecma_count(x, regex)
}
\arguments{
\item{x}{A character vector.}
\item{regex}{A regular expression from \code{\link{ecma_regex}}, or a pattern compiled without flags. Whether or not
  it has the \code{g} flag, every match is found.}
\item{group}{The group to locate in each match, by number (0 is the whole match) or by name.}
}
\value{
\code{ecma_match_all} returns a list with a character matrix for each string, laid out as \code{\link{ecma_match}}'s
with a row for each match. \code{ecma_locate_all} returns a list with an integer matrix for each string, with the
columns \code{start} and \code{end} (\code{NA} for a group that did not take part). Each is \code{NULL} for an \code{NA} string. \code{ecma_count} returns an integer
vector, \code{NA} for an \code{NA} string; it makes no match, and is the fastest way to know how many there are.
}
\examples{
ecma_match_all("1 22 333", "\\\\d+")
ecma_locate_all("x1y22z333", "\\\\d+")
ecma_count(c("a b a", "", NA), "a")
}
