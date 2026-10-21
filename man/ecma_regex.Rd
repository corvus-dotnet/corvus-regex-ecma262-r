\name{ecma_regex}
\alias{ecma_regex}
\alias{ecma_valid}
\alias{print.ecma_regex}
\alias{format.ecma_regex}
\title{Compile an ECMA-262 Regular Expression}
\description{
\code{ecma_regex} compiles a pattern as \code{new RegExp(pattern, flags)} does. \code{ecma_valid} says whether each
pattern is valid with the flags, without compiling it.
}
\usage{
ecma_regex(pattern, flags = "")

ecma_valid(pattern, flags = "")

\method{print}{ecma_regex}(x, ...)

\method{format}{ecma_regex}(x, ...)
}
\arguments{
\item{pattern}{For \code{ecma_regex}, one string; for \code{ecma_valid}, a character vector.}
\item{flags}{The flags, such as \code{""}, \code{"u"} or \code{"gimsuy"}: for \code{ecma_valid}, recycled.}
\item{x}{A compiled regular expression.}
\item{...}{Not used.}
}
\value{
\code{ecma_regex} returns an object of class \code{ecma_regex}, with the attributes \code{source}, \code{flags} (in
the order \code{RegExp} gives them), \code{group_count} and \code{group_names} (the distinct names of the groups, in
the order of the first group of each). It is used by every other function, and from any number of calls.
\code{ecma_valid} returns a logical vector, \code{NA} for an \code{NA} pattern.
}
\details{
The \code{g} flag makes \code{\link{ecma_replace}} replace every match, and the \code{y} flag makes each search match
where it starts. The \code{d} flag is accepted and changes nothing, since every match gives its groups' positions.

A compiled regular expression is not saved with the session: compile it again in a new one.
}
\examples{
date <- ecma_regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})", "g")
date
attr(date, "group_names")
ecma_valid(c("a+", "a{2,1}", "("), "u")
}
