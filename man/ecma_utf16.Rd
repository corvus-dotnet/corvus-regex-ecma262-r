\name{ecma_utf16}
\alias{ecma_utf16}
\alias{as.character.ecma_utf16}
\alias{as.raw.ecma_utf16}
\alias{print.ecma_utf16}
\alias{[.ecma_utf16}
\alias{c.ecma_utf16}
\title{Texts as UTF-16 Code Units, and as Raw Vectors of UTF-8}
\description{
A JavaScript string is a sequence of UTF-16 code units, which may hold a lone surrogate, and may hold a NUL. An R
string can hold neither, so every function that matches also takes texts in two other forms. \code{ecma_utf16} makes
the first: the UTF-16 code units of a text. The second is a raw vector of UTF-8 bytes, as \code{charToRaw} gives one,
which may hold a NUL.
}
\usage{
ecma_utf16(x)

\method{as.character}{ecma_utf16}(x, ...)

\method{as.raw}{ecma_utf16}(x)

\method{print}{ecma_utf16}(x, ...)
}
\arguments{
\item{x}{For \code{ecma_utf16}, one string, a raw vector of UTF-8, or the code units themselves (numbers from 0 to
  65535). For the methods, an \code{ecma_utf16}.}
\item{...}{Not used.}
}
\details{
Where a function takes \code{x}, it may be a character vector (each string a text, positions in characters), a raw
vector (one text of UTF-8, positions in bytes), an \code{ecma_utf16} (one text, positions in code units), or a list
whose elements are raw vectors, \code{ecma_utf16}s or \code{NULL} (for a missing text). Positions are from 1 with an
end inclusive, as for strings, and the texts of a match, a replacement and the pieces of a split come back in the form
of the text they came from. A raw vector that is not UTF-8 is refused with \code{ecma_encoding_error}: it is never read
in part. Over UTF-16 a match without \code{u} or \code{v} may start or end between the halves of a surrogate pair, and
its text holds the half as a lone surrogate, as JavaScript gives it; over UTF-8 such a position is the third byte of
the character's four, and the half is written as U+FFFD.

A pattern may be a raw vector too, so that it can hold a NUL, but not an \code{ecma_utf16}: a lone surrogate in a
pattern is written as an escape, such as \verb{\\uD800}.
}
\value{
\code{ecma_utf16} returns an integer vector of class \code{ecma_utf16}. \code{as.character} returns the text as one
string, a lone surrogate as U+FFFD; a text that holds a NUL has no R string, and raises \code{ecma_encoding_error}.
\code{as.raw} returns its UTF-8, a lone surrogate as U+FFFD.
}
\examples{
lone <- ecma_utf16(c(0x61, 0xD800, 0x62))
lone
ecma_test(lone, "\\\\uD800")
ecma_locate(ecma_utf16("a\U0001F600b"), "\\\\uDE00b")
ecma_split(list(as.raw(c(0x61, 0x00, 0x62)), NULL), "\\\\0")
}
