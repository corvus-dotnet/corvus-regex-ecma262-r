\name{ecma_regex}
\alias{ecma_regex}
\alias{ecma_valid}
\alias{ecma_set_default_timeout}
\alias{ecma_default_timeout}
\alias{print.ecma_regex}
\alias{format.ecma_regex}
\alias{ecma_unicode_versions}
\alias{ecma_default_unicode_version}
\alias{ecma_latest_unicode_version}
\title{Compile an ECMA-262 Regular Expression}
\description{
\code{ecma_regex} compiles a pattern as \code{new RegExp(pattern, flags)} does, with a match timeout.
\code{ecma_valid} says whether each pattern is valid with the flags, without compiling it.
\code{ecma_set_default_timeout} sets the timeout of every pattern compiled without one, and
\code{ecma_default_timeout} gives it. \code{ecma_unicode_versions} gives the versions of Unicode a pattern can be read
with, \code{ecma_default_unicode_version} the one \code{NULL} stands for and \code{ecma_latest_unicode_version} the one
\code{"latest"} stands for.
}
\usage{
ecma_regex(pattern, flags = "", timeout = NULL, edition = "current", unicode_version = NULL)

ecma_valid(pattern, flags = "", edition = "current", unicode_version = NULL)

ecma_set_default_timeout(seconds)

ecma_default_timeout()

ecma_unicode_versions()

ecma_default_unicode_version()

ecma_latest_unicode_version()

\method{print}{ecma_regex}(x, ...)

\method{format}{ecma_regex}(x, ...)
}
\arguments{
\item{pattern}{For \code{ecma_regex}, one string, or a raw vector of UTF-8 (which may hold a NUL); for
  \code{ecma_valid}, a character vector, a raw vector, or a list of strings and raw vectors.}
\item{flags}{The flags, such as \code{""}, \code{"u"} or \code{"gimsuy"}: for \code{ecma_valid}, recycled.}
\item{timeout}{The time in seconds each match may take before it is abandoned with \code{ecma_match_limit}, \code{0}
for no limit, or \code{NULL} for \code{ecma_default_timeout()}.}
\item{edition}{The edition of ECMA-262 whose grammar the pattern is read with: \code{"current"}, today's, or
\code{"es2020"}, ECMAScript 2020's, which JSON Schema 2020-12 names.}
\item{unicode_version}{The version of Unicode whose tables the pattern is read with: \code{NULL} for the version of
the V8 the answers are held to (17 today), \code{13}, \code{17}, \code{18}, or \code{"latest"} for the latest the
package carries (18 today).}
\item{seconds}{The default timeout in seconds, or \code{NULL} (or \code{0}) for no limit.}
\item{x}{A compiled regular expression.}
\item{...}{Not used.}
}
\value{
\code{ecma_regex} returns an object of class \code{ecma_regex}, with the attributes \code{source} (a raw vector where
it holds a NUL, which \code{format} writes as \verb{\\0}), \code{flags} (in
the order \code{RegExp} gives them), \code{group_count} and \code{group_names} (the distinct names of the groups, in
the order of the first group of each), \code{timeout} (\code{NULL} for none), \code{edition} and
\code{unicode_version} (the version resolved: 13, 17 or 18). It is used by every other function,
and from any number of calls. \code{ecma_default_timeout} returns the default timeout in seconds, or \code{NULL}.
\code{ecma_valid} returns a logical vector, \code{NA} for an \code{NA} pattern. \code{ecma_unicode_versions},
\code{ecma_default_unicode_version} and \code{ecma_latest_unicode_version} return integers: \code{c(13L, 17L, 18L)},
\code{17L} and \code{18L}.
}
\details{
The \code{g} flag makes \code{\link{ecma_replace}} replace every match, and the \code{y} flag makes each search match
where it starts. The \code{d} flag is accepted and changes nothing, since every match gives its groups' positions.

A pattern has a match timeout, as a \code{Regex} of .NET has: every function that matches gives each of its matches
the timeout, and a match that reaches it, or the cap on backtracking memory that comes with it, raises
\code{ecma_match_limit}. A pattern compiled without one takes \code{ecma_default_timeout()}, which is \code{NULL} (no
limit) unless \code{ecma_set_default_timeout} set it. Without a timeout a match has no limit of time or of memory, so
give one to a pattern or a text from outside. A pattern given as a string to the other functions takes the default.

The edition and the version of Unicode are each independent of the other, and are settled when the pattern is
compiled, so they cost a match nothing. \code{edition = "es2020"} refuses what later editions added, and nothing else:
the \code{d} and \code{v} flags (\code{ecma_invalid_flags}), modifier groups such as \verb{(?i:...)}, a group name
used by two groups, and a property name or value that is not in that edition's tables, such as
\verb{\\p{Script=Yezidi}} (each \code{ecma_invalid_pattern}). A pattern it accepts has the same answers as in today's
grammar. The version of Unicode sets the members of each \verb{\\p{...}}, the characters of a group name, and case
folding. There is no separate function that gives \code{NULL} for a pattern that is not valid: \code{tryCatch} on
\code{ecma_regex}, which takes a timeout of its own, is that form, so a validator needs no default timeout.

A compiled regular expression is not saved with the session: compile it again in a new one.
}
\examples{
date <- ecma_regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})", "g")
date
attr(date, "group_names")
ecma_valid(c("a+", "a{2,1}", "("), "u")
timed <- ecma_regex("^(?:(a+)\\\\1*)+$", "u", timeout = 0.05)
attr(timed, "timeout")
schema <- ecma_regex("^\\\\p{L}+$", "u", timeout = 1, edition = "es2020", unicode_version = 13)
attr(schema, "unicode_version")
ecma_valid("(?i:a)", edition = "es2020")
}
