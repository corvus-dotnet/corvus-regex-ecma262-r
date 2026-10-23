\name{ecma_split}
\alias{ecma_split}
\title{Split Strings Around Matches}
\description{
Splits each string around the matches, as \code{String.prototype.split} does: what each group captured is spliced in
after the piece before it, and an empty match at the start or the end of the string splits nothing.
}
\usage{
ecma_split(x, regex, limit = NULL)
}
\arguments{
\item{x}{A character vector, or texts in another form: a raw vector of UTF-8 or an \code{ecma_utf16} of code units,
  or a list of them (see \code{\link{ecma_utf16}}).}
\item{regex}{A regular expression from \code{\link{ecma_regex}}, or a pattern compiled without flags.}
\item{limit}{The most pieces to give, or \code{NULL} for every one.}
}
\value{
A list with a character vector for each string, \code{NA} for a group that did not take part, and \code{NULL} for an
\code{NA} string. For texts in another form, a list with a list of pieces in the form of each text (\code{NULL} for a
group that did not take part).
}
\examples{
ecma_split("a ; b;c", "\\\\s*(;)\\\\s*")
ecma_split("a,b", "(x)?,")
}
