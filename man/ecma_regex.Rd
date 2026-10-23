\name{ecma_regex}
\alias{ecma_regex}
\alias{ecma_valid}
\alias{ecma_set_default_timeout}
\alias{ecma_default_timeout}
\alias{print.ecma_regex}
\alias{format.ecma_regex}
\title{Compile an ECMA-262 Regular Expression}
\description{
\code{ecma_regex} compiles a pattern as \code{new RegExp(pattern, flags)} does, with a match timeout.
\code{ecma_valid} says whether each pattern is valid with the flags, without compiling it.
\code{ecma_set_default_timeout} sets the timeout of every pattern compiled without one, and
\code{ecma_default_timeout} gives it.
}
\usage{
ecma_regex(pattern, flags = "", timeout = NULL)

ecma_valid(pattern, flags = "")

ecma_set_default_timeout(seconds)

ecma_default_timeout()

\method{print}{ecma_regex}(x, ...)

\method{format}{ecma_regex}(x, ...)
}
\arguments{
\item{pattern}{For \code{ecma_regex}, one string, or a raw vector of UTF-8 (which may hold a NUL); for
  \code{ecma_valid}, a character vector, a raw vector, or a list of strings and raw vectors.}
\item{flags}{The flags, such as \code{""}, \code{"u"} or \code{"gimsuy"}: for \code{ecma_valid}, recycled.}
\item{timeout}{The time in seconds each match may take before it is abandoned with \code{ecma_match_limit}, \code{0}
for no limit, or \code{NULL} for \code{ecma_default_timeout()}.}
\item{seconds}{The default timeout in seconds, or \code{NULL} (or \code{0}) for no limit.}
\item{x}{A compiled regular expression.}
\item{...}{Not used.}
}
\value{
\code{ecma_regex} returns an object of class \code{ecma_regex}, with the attributes \code{source} (a raw vector where
it holds a NUL, which \code{format} writes as \verb{\\0}), \code{flags} (in
the order \code{RegExp} gives them), \code{group_count} and \code{group_names} (the distinct names of the groups, in
the order of the first group of each) and \code{timeout} (\code{NULL} for none). It is used by every other function,
and from any number of calls. \code{ecma_default_timeout} returns the default timeout in seconds, or \code{NULL}.
\code{ecma_valid} returns a logical vector, \code{NA} for an \code{NA} pattern.
}
\details{
The \code{g} flag makes \code{\link{ecma_replace}} replace every match, and the \code{y} flag makes each search match
where it starts. The \code{d} flag is accepted and changes nothing, since every match gives its groups' positions.

A pattern has a match timeout, as a \code{Regex} of .NET has: every function that matches gives each of its matches
the timeout, and a match that reaches it, or the cap on backtracking memory that comes with it, raises
\code{ecma_match_limit}. A pattern compiled without one takes \code{ecma_default_timeout()}, which is \code{NULL} (no
limit) unless \code{ecma_set_default_timeout} set it. Without a timeout a match has no limit of time or of memory, so
give one to a pattern or a text from outside. A pattern given as a string to the other functions takes the default.

A compiled regular expression is not saved with the session: compile it again in a new one.
}
\examples{
date <- ecma_regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})", "g")
date
attr(date, "group_names")
ecma_valid(c("a+", "a{2,1}", "("), "u")
timed <- ecma_regex("^(?:(a+)\\\\1*)+$", "u", timeout = 0.05)
attr(timed, "timeout")
}
