\name{corvusregexecma262-package}
\alias{corvusregexecma262-package}
\alias{corvusregexecma262}
\docType{package}
\title{ECMA-262 (JavaScript) Regular Expressions}
\description{
Regular expressions with the grammar and the answers of ECMA-262, the \code{RegExp} of JavaScript, so that a pattern
answers in R as it does in a browser or Node.js. Every flag: \code{d}, \code{g}, \code{i}, \code{m}, \code{s},
\code{u}, \code{v} and \code{y}, with the grammar of each; lookbehind, named groups, modifier groups such as
\code{(?i:...)}, and every Unicode property ECMA-262 lists.

Compile a pattern with \code{\link{ecma_regex}}, then use it with \code{\link{ecma_test}}, \code{\link{ecma_match}},
\code{\link{ecma_locate}}, \code{\link{ecma_match_all}}, \code{\link{ecma_locate_all}}, \code{\link{ecma_count}},
\code{\link{ecma_replace}} and \code{\link{ecma_split}}, each over a character vector. Each also takes a pattern as a
string, compiled without flags.
}
\section{Strings and positions}{
R's strings are matched as UTF-8: one marked as UTF-8, or in the native encoding of a UTF-8 session, is read in place
(after a check that it is UTF-8); one in another encoding is translated. A string marked as bytes is refused. Positions
are in characters from 1, as \code{nchar} counts them, an end inclusive, as \code{regexpr} gives them.

Without \code{u} or \code{v} a pattern is matched by UTF-16 code unit, as ECMA-262 matches it, so a match can take
half of a character beyond the Basic Multilingual Plane. Its text then holds that half as U+FFFD, and its positions are
the whole character's.
}
\section{Conditions}{
A pattern that is not valid raises \code{ecma_invalid_pattern}; flags that are not, \code{ecma_invalid_flags}; a
pattern over a limit of size, \code{ecma_pattern_too_large}; a match that reaches its timeout or its cap on
backtracking memory, \code{ecma_match_limit}; a string that is not UTF-8 or is marked as bytes,
\code{ecma_encoding_error}; and an argument of the wrong kind, \code{ecma_argument_error}. All inherit from
\code{ecma_regex_error}.
}
\seealso{
\url{https://github.com/corvus-dotnet/corvus-regex-ecma262-r}
}
\keyword{package}
