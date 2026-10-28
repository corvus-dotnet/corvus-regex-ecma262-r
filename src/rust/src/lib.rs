//! The native code of the corvusregexecma262 R package: the corvus-regex-ecma262 crate, over R's character vectors.
//!
//! Every entry point returns an R value. A failure is returned as a list of class `crer_native_error` (its kind and
//! message), which the R layer raises as a condition: nothing here calls `Rf_error`, whose long jump would skip the
//! destructors of the Rust frames it crosses. A panic is caught at each entry point and returned the same way.
//!
//! R's strings are matched as UTF-8. A string marked as UTF-8, or in the native encoding of a UTF-8 session, is read
//! in place (checked to be UTF-8 first, since R does not check what it marks); one in another encoding is translated
//! to UTF-8 by R. Positions given to R are in characters from 1, as R counts them, an end inclusive. Without u or v a
//! match can start or end between the halves of a character beyond the Basic Multilingual Plane (the third byte of
//! its UTF-8): such a start is given as the character's position and such an end as the character's too, and the text
//! of the match holds the half as U+FFFD.
//!
//! A text may also be given in a list, as a raw vector of UTF-8 (which may hold a NUL, as an R string cannot) or an
//! `ecma_utf16` of UTF-16 code units (an integer vector, which may hold lone surrogates, as a JavaScript string can).
//! Positions in a raw vector are in bytes, and in an `ecma_utf16` in code units, from 1 and an end inclusive, and the
//! texts of a match come back in the form the text was given in. A pattern may be a raw vector too.

mod r;

use std::borrow::Cow;
use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_uint, c_void};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use corvus_regex_ecma262 as ecma;
use r::*;

/// A failure, returned to R as a list of class `crer_native_error`, which the R layer raises.
struct Failure {
    kind: &'static str,
    message: String,
}

impl Failure {
    fn new(kind: &'static str, message: impl Into<String>) -> Failure {
        Failure { kind, message: message.into() }
    }
}

type Result<T> = std::result::Result<T, Failure>;

fn compile_failure(e: ecma::Error) -> Failure {
    let kind = match e {
        ecma::Error::TooLarge(_) => "too_large",
        ecma::Error::Flags(_) => "flags",
        _ => "pattern",
    };
    Failure::new(kind, e.to_string())
}

fn limit_failure(e: ecma::MatchError) -> Failure {
    Failure::new("limit", e.to_string())
}

/// Runs an entry point's body: its value, or its failure (or panic) as a `crer_native_error`.
fn entry(f: impl FnOnce() -> Result<SEXP>) -> SEXP {
    let result = catch_unwind(AssertUnwindSafe(f)).unwrap_or_else(|panic| {
        let message = panic
            .downcast_ref::<&str>()
            .map(|s| s.to_string())
            .or_else(|| panic.downcast_ref::<String>().cloned())
            .unwrap_or_else(|| "a panic in the native code".into());
        Err(Failure::new("internal", message))
    });
    match result {
        Ok(value) => value,
        Err(failure) => unsafe {
            let list = Rf_protect(Rf_allocVector(VECSXP as c_uint, 2));
            SET_VECTOR_ELT(list, 0, string_vector(&[failure.kind]));
            // An R string cannot hold a NUL, which a message that quotes a pattern may.
            SET_VECTOR_ELT(list, 1, string_vector(&[&failure.message.replace('\0', "\\0")]));
            Rf_setAttrib(list, class_symbol(), string_vector(&["crer_native_error"]));
            Rf_unprotect(1);
            list
        },
    }
}

/// A CHARSXP for UTF-8 text.
unsafe fn mk_char(s: &str) -> SEXP {
    unsafe { Rf_mkCharLenCE(s.as_ptr() as *const c_char, s.len() as c_int, CE_UTF8) }
}

unsafe fn string_vector(items: &[&str]) -> SEXP {
    unsafe {
        let v = Rf_protect(Rf_allocVector(STRSXP as c_uint, items.len() as R_xlen_t));
        for (i, s) in items.iter().enumerate() {
            SET_STRING_ELT(v, i as R_xlen_t, mk_char(s));
        }
        Rf_unprotect(1);
        v
    }
}

/// Whether the session's native encoding is UTF-8 (set when the package loads).
static UTF8_SESSION: AtomicBool = AtomicBool::new(false);

/// The last long string found to be UTF-8, kept from collection (so that its address names no other string) while it
/// is remembered: a loop that matches one text again and again checks it once.
static CHECKED: std::sync::Mutex<usize> = std::sync::Mutex::new(0);

/// Strings shorter than this are checked each time; the check costs less than remembering them.
const REMEMBER: usize = 4096;

/// The UTF-8 of an element of a character vector, or `None` for `NA`.
///
/// SAFETY: the vector must be protected for as long as the text is used.
unsafe fn text_of<'a>(x: SEXP) -> Result<Option<&'a str>> {
    unsafe {
        if x == na_string() {
            return Ok(None);
        }
        let encoding = Rf_getCharCE(x);
        if encoding == CE_BYTES {
            return Err(Failure::new("encoding", "a string marked as bytes has no characters to match"));
        }
        if encoding == CE_UTF8 || (encoding == CE_NATIVE && UTF8_SESSION.load(Ordering::Relaxed)) {
            let bytes = std::slice::from_raw_parts(R_CHAR(x) as *const u8, LENGTH(x) as usize);
            if bytes.len() >= REMEMBER {
                let mut checked = CHECKED.lock().unwrap_or_else(|e| e.into_inner());
                if *checked == x as usize {
                    return Ok(Some(std::str::from_utf8_unchecked(bytes)));
                }
                let text = utf8(bytes)?;
                if *checked != 0 {
                    R_ReleaseObject(*checked as SEXP);
                }
                R_PreserveObject(x);
                *checked = x as usize;
                return Ok(Some(text));
            }
            return utf8(bytes).map(Some);
        }
        // Translated by R into memory it frees when the call returns.
        let translated = CStr::from_ptr(Rf_translateCharUTF8(x)).to_bytes();
        utf8(translated).map(Some)
    }
}

fn utf8(bytes: &[u8]) -> Result<&str> {
    match simdutf8::basic::from_utf8(bytes) {
        Ok(s) => Ok(s),
        Err(_) => Err(Failure::new(
            "encoding",
            match std::str::from_utf8(bytes) {
                Err(e) => format!("a string is not valid UTF-8: {e}"),
                Ok(_) => "a string is not valid UTF-8".into(),
            },
        )),
    }
}

/// A compiled pattern, behind an external pointer.
struct Compiled {
    re: ecma::Regex,
    /// The distinct names of the groups, in the order of the first group of each.
    names: Vec<String>,
}

unsafe extern "C" fn finalize(ptr: SEXP) {
    unsafe {
        let p = R_ExternalPtrAddr(ptr) as *mut Compiled;
        if !p.is_null() {
            drop(Box::from_raw(p));
            R_ClearExternalPtr(ptr);
        }
    }
}

/// The compiled pattern of an R regular expression object (the external pointer itself, with attributes).
unsafe fn compiled<'a>(re: SEXP) -> Result<&'a Compiled> {
    unsafe {
        if TYPEOF(re) != EXTPTRSXP || R_ExternalPtrTag(re) != regex_tag() {
            return Err(Failure::new("argument", "regex must be a regular expression from ecma_regex()"));
        }
        let p = R_ExternalPtrAddr(re) as *const Compiled;
        p.as_ref().ok_or_else(|| {
            Failure::new("argument", "the regular expression was not saved with the session; compile it again")
        })
    }
}

fn limit_of(timeout: f64) -> Result<Option<Duration>> {
    if timeout.is_nan() {
        Ok(None)
    } else if timeout.is_finite() && timeout >= 0.0 {
        Ok(Some(Duration::from_secs_f64(timeout)))
    } else {
        Err(Failure::new("argument", "timeout must be a number of seconds, 0 or more"))
    }
}

/// The edition the R layer's code names: 0 today's grammar, 1 ECMAScript 2020's.
unsafe fn edition_of(edition: SEXP) -> Result<ecma::Edition> {
    match unsafe { INTEGER_ELT(edition, 0) } {
        0 => Ok(ecma::Edition::Current),
        1 => Ok(ecma::Edition::Es2020),
        _ => Err(Failure::new("argument", "edition must be \"current\" or \"es2020\"")),
    }
}

/// The version of Unicode the R layer's code names: 0 the default (V8's), 13, 17, 18, or -1 the latest.
unsafe fn unicode_version_of(version: SEXP) -> Result<ecma::UnicodeVersion> {
    match unsafe { INTEGER_ELT(version, 0) } {
        0 => Ok(ecma::UnicodeVersion::Default),
        13 => Ok(ecma::UnicodeVersion::V13),
        17 => Ok(ecma::UnicodeVersion::V17),
        18 => Ok(ecma::UnicodeVersion::V18),
        -1 => Ok(ecma::UnicodeVersion::Latest),
        _ => Err(Failure::new("argument", "unicode_version must be NULL, 13, 17, 18 or \"latest\"")),
    }
}

/// Whether a byte is inside a character (not its first byte).
#[inline(always)]
fn inside(b: &[u8], at: usize) -> bool {
    at < b.len() && (b[at] & 0xC0) == 0x80
}

/// The text from `a` to `b` (byte offsets, either of which may be the third byte of a four-byte character, between
/// its halves), a half character at either end as U+FFFD.
fn piece(s: &str, a: usize, b: usize) -> Cow<'_, str> {
    if a >= b {
        return Cow::Borrowed("");
    }
    let bytes = s.as_bytes();
    let (head, a) = if inside(bytes, a) { (true, a + 2) } else { (false, a) };
    let (tail, b) = if inside(bytes, b) { (true, b - 2) } else { (false, b) };
    let body = if a < b { &s[a..b] } else { "" };
    if !head && !tail {
        return Cow::Borrowed(body);
    }
    let mut out = String::with_capacity(body.len() + 6);
    if head {
        out.push('\u{FFFD}');
    }
    out.push_str(body);
    if tail {
        out.push('\u{FFFD}');
    }
    Cow::Owned(out)
}

/// A text to match: a string of a character vector, or an element of a list, a raw vector of UTF-8 or an
/// `ecma_utf16` of code units.
enum Text<'a> {
    /// Positions in characters, the texts of a match strings.
    Chars(&'a str),
    /// Positions in bytes, the texts of a match raw vectors.
    Bytes(&'a str),
    /// Positions in code units, the texts of a match `ecma_utf16`s.
    Units(Vec<u16>),
}

/// The text of element `i` of a character vector or a list, or `None` for `NA` (`NULL` in a list).
///
/// SAFETY: the vector must be protected for as long as the text is used.
unsafe fn text_at<'a>(x: SEXP, i: R_xlen_t) -> Result<Option<Text<'a>>> {
    unsafe {
        if TYPEOF(x) == STRSXP {
            return Ok(text_of(STRING_ELT(x, i))?.map(Text::Chars));
        }
        item_of(VECTOR_ELT(x, i))
    }
}

/// The text of an element of a list: `NULL`, a raw vector of UTF-8, an `ecma_utf16` or one string.
///
/// SAFETY: the element must be protected for as long as the text is used.
unsafe fn item_of<'a>(v: SEXP) -> Result<Option<Text<'a>>> {
    unsafe {
        match TYPEOF(v) {
            NILSXP => Ok(None),
            RAWSXP => {
                let bytes: &[u8] = match Rf_xlength(v) {
                    0 => &[],
                    n => std::slice::from_raw_parts(RAW(v), n as usize),
                };
                utf8(bytes).map(|s| Some(Text::Bytes(s)))
            }
            INTSXP => units_of(v).map(|u| Some(Text::Units(u))),
            STRSXP if Rf_xlength(v) == 1 => Ok(text_of(STRING_ELT(v, 0))?.map(Text::Chars)),
            _ => Err(Failure::new(
                "argument",
                "each text in a list must be a raw vector of UTF-8, an ecma_utf16 of code units, or NULL",
            )),
        }
    }
}

/// The code units of an integer vector, each 0 to 65535.
unsafe fn units_of(v: SEXP) -> Result<Vec<u16>> {
    unsafe {
        let n = Rf_xlength(v) as usize;
        let values: &[c_int] = if n == 0 { &[] } else { std::slice::from_raw_parts(INTEGER(v), n) };
        values
            .iter()
            .map(|&u| u16::try_from(u).ok())
            .collect::<Option<Vec<u16>>>()
            .ok_or_else(|| Failure::new("argument", "a UTF-16 code unit must be a number from 0 to 65535"))
    }
}

fn check_texts(x: SEXP, what: &str) -> Result<()> {
    match unsafe { TYPEOF(x) } {
        STRSXP | VECSXP => Ok(()),
        _ => Err(Failure::new("argument", format!("{what} must be a character vector or a list of texts"))),
    }
}

/// A raw vector of bytes.
unsafe fn raw_vector(bytes: &[u8]) -> SEXP {
    unsafe {
        let v = Rf_allocVector(RAWSXP as c_uint, bytes.len() as R_xlen_t);
        if !bytes.is_empty() {
            std::ptr::copy_nonoverlapping(bytes.as_ptr(), RAW(v), bytes.len());
        }
        v
    }
}

/// An `ecma_utf16` of code units.
unsafe fn units_vector(units: &[u16]) -> SEXP {
    unsafe {
        let v = Rf_protect(Rf_allocVector(INTSXP as c_uint, units.len() as R_xlen_t));
        let o = INTEGER(v);
        for (i, &u) in units.iter().enumerate() {
            *o.add(i) = c_int::from(u);
        }
        Rf_setAttrib(v, class_symbol(), string_vector(&["ecma_utf16"]));
        Rf_unprotect(1);
        v
    }
}

/// A text the crate matches, `str` or `[u16]`, through the members of `Regex` for each.
trait Hay: ecma::Haystack {
    fn size(&self) -> usize;
    fn captures_from<'t>(
        re: &ecma::Regex,
        text: &'t Self,
        start: usize,
        limit: Option<Duration>,
    ) -> std::result::Result<Option<ecma::Captures<'t, Self>>, ecma::MatchError>;
    fn matches<'r, 't>(re: &'r ecma::Regex, text: &'t Self) -> ecma::Matches<'r, 't, Self>;
    fn captures_all<'r, 't>(re: &'r ecma::Regex, text: &'t Self) -> ecma::CaptureMatches<'r, 't, Self>;
    fn replaced<'t>(
        re: &ecma::Regex,
        text: &'t Self,
        template: &Self,
        all: bool,
    ) -> std::result::Result<Cow<'t, Self>, ecma::MatchError>;
    #[allow(clippy::type_complexity)]
    fn pieces<'t>(
        re: &ecma::Regex,
        text: &'t Self,
        limit: Option<usize>,
    ) -> std::result::Result<Vec<Option<Cow<'t, Self>>>, ecma::MatchError>;
}

impl Hay for str {
    fn size(&self) -> usize {
        self.len()
    }
    fn captures_from<'t>(
        re: &ecma::Regex,
        text: &'t str,
        start: usize,
        limit: Option<Duration>,
    ) -> std::result::Result<Option<ecma::Captures<'t>>, ecma::MatchError> {
        match limit {
            Some(l) => re.captures_at_within(text, start, l),
            None => re.captures_at(text, start),
        }
    }
    fn matches<'r, 't>(re: &'r ecma::Regex, text: &'t str) -> ecma::Matches<'r, 't> {
        re.find_iter(text)
    }
    fn captures_all<'r, 't>(re: &'r ecma::Regex, text: &'t str) -> ecma::CaptureMatches<'r, 't> {
        re.captures_iter(text)
    }
    fn replaced<'t>(
        re: &ecma::Regex,
        text: &'t str,
        template: &str,
        all: bool,
    ) -> std::result::Result<Cow<'t, str>, ecma::MatchError> {
        if all { re.replace_all(text, template) } else { re.replace(text, template) }
    }
    fn pieces<'t>(
        re: &ecma::Regex,
        text: &'t str,
        limit: Option<usize>,
    ) -> std::result::Result<Vec<Option<Cow<'t, str>>>, ecma::MatchError> {
        match limit {
            Some(l) => re.splitn(text, l),
            None => re.split(text),
        }
    }
}

impl Hay for [u16] {
    fn size(&self) -> usize {
        self.len()
    }
    fn captures_from<'t>(
        re: &ecma::Regex,
        text: &'t [u16],
        start: usize,
        limit: Option<Duration>,
    ) -> std::result::Result<Option<ecma::Captures<'t, [u16]>>, ecma::MatchError> {
        match limit {
            Some(l) => re.captures_at_within_utf16(text, start, l),
            None => re.captures_at_utf16(text, start),
        }
    }
    fn matches<'r, 't>(re: &'r ecma::Regex, text: &'t [u16]) -> ecma::Matches<'r, 't, [u16]> {
        re.find_iter_utf16(text)
    }
    fn captures_all<'r, 't>(re: &'r ecma::Regex, text: &'t [u16]) -> ecma::CaptureMatches<'r, 't, [u16]> {
        re.captures_iter_utf16(text)
    }
    fn replaced<'t>(
        re: &ecma::Regex,
        text: &'t [u16],
        template: &[u16],
        all: bool,
    ) -> std::result::Result<Cow<'t, [u16]>, ecma::MatchError> {
        if all { re.replace_all_utf16(text, template) } else { re.replace_utf16(text, template) }
    }
    fn pieces<'t>(
        re: &ecma::Regex,
        text: &'t [u16],
        limit: Option<usize>,
    ) -> std::result::Result<Vec<Option<Cow<'t, [u16]>>>, ecma::MatchError> {
        match limit {
            Some(l) => re.splitn_utf16(text, l),
            None => re.split_utf16(text),
        }
    }
}

/// Converts byte offsets to R's character positions, going on from where it was last asked, since a search asks in
/// order.
struct Positions {
    at: usize,
    count: usize,
}

impl Positions {
    fn new() -> Positions {
        Positions { at: 0, count: 0 }
    }

    /// The characters begun before `at`: a lead byte starts a character, so a position inside one (the third byte of
    /// a four-byte one) counts it as begun.
    fn begun(&mut self, b: &[u8], at: usize) -> usize {
        if at < self.at {
            self.at = 0;
            self.count = 0;
        }
        self.count += b[self.at..at].iter().filter(|&&c| (c as i8) >= -0x40).count();
        self.at = at;
        self.count
    }

    /// R's position (from 1) of a match's start and its end (inclusive): a start between the halves of a character
    /// is the character's position, as is an end there.
    fn span(&mut self, b: &[u8], start: usize, end: usize) -> (c_int, c_int) {
        let s = self.begun(b, start);
        let s = if inside(b, start) { s } else { s + 1 };
        let e = self.begun(b, end);
        (s as c_int, e as c_int)
    }

    /// The position of a match's start and end in a text, in its own positions: characters for a string, bytes for a
    /// raw vector, code units for an `ecma_utf16`.
    fn of(&mut self, text: &Text<'_>, start: usize, end: usize) -> (c_int, c_int) {
        match text {
            Text::Chars(s) => self.span(s.as_bytes(), start, end),
            Text::Bytes(_) | Text::Units(_) => ((start + 1) as c_int, end as c_int),
        }
    }
}

/// The byte offset of R's character position `start` (from 1); past the end, the text's length plus one, as
/// `lastIndex` past the end is.
fn offset_of(s: &str, start: c_int) -> usize {
    if start <= 1 {
        return 0;
    }
    let n = (start - 1) as usize;
    s.char_indices().nth(n).map_or_else(|| s.len() + (n - s.chars().count()).min(1), |(i, _)| i)
}

/// The width of a match's row: the match, each group, then each name.
fn width(c: &Compiled) -> usize {
    c.re.captures_len() + c.names.len()
}

/// The groups of a match by number, then by name: start and end, or None.
fn spans_of<H: Hay + ?Sized>(c: &Compiled, caps: &ecma::Captures<'_, H>, out: &mut Vec<Option<(usize, usize)>>) {
    out.extend(caps.iter().map(|m| m.map(|m| (m.start(), m.end()))));
    out.extend(c.names.iter().map(|n| caps.name(n).map(|m| (m.start(), m.end()))));
}

/// The first match at or after `start`, its groups appended to `out`: whether there was one.
fn first<H: Hay + ?Sized>(
    c: &Compiled,
    s: &H,
    start: usize,
    limit: Option<Duration>,
    out: &mut Vec<Option<(usize, usize)>>,
) -> Result<bool> {
    if start > s.size() {
        return Ok(false);
    }
    let caps = H::captures_from(&c.re, s, start, limit).map_err(limit_failure)?;
    Ok(caps.map(|caps| spans_of(c, &caps, out)).is_some())
}

/// Every match of a global search, the groups of each appended to `out` (only the match's when `whole`): how many.
fn all<H: Hay + ?Sized>(c: &Compiled, s: &H, whole: bool, out: &mut Vec<Option<(usize, usize)>>) -> Result<usize> {
    let groups = c.re.captures_len();
    if whole || (groups == 1 && c.names.is_empty()) {
        let mut it = H::matches(&c.re, s);
        let mut batch = [(0usize, 0usize); 256];
        let mut n = 0;
        loop {
            let k = it.next_batch(&mut batch).map_err(limit_failure)?;
            out.extend(batch[..k].iter().map(|&(a, b)| Some((a, b))));
            n += k;
            if k < batch.len() {
                return Ok(n);
            }
        }
    }
    if c.names.is_empty() {
        let mut it = H::captures_all(&c.re, s);
        let mut batch = vec![None; groups * 64];
        let mut n = 0;
        loop {
            let k = it.next_batch(&mut batch).map_err(limit_failure)?;
            out.extend_from_slice(&batch[..k * groups]);
            n += k;
            if k < 64 {
                return Ok(n);
            }
        }
    }
    let mut n = 0;
    for caps in H::captures_all(&c.re, s) {
        spans_of(c, &caps.map_err(limit_failure)?, out);
        n += 1;
    }
    Ok(n)
}

/// How many matches a global search finds, none of them made.
fn count<H: Hay + ?Sized>(c: &Compiled, s: &H) -> Result<usize> {
    let mut it = H::matches(&c.re, s);
    let mut batch = [(0usize, 0usize); 256];
    let mut n = 0;
    loop {
        let k = it.next_batch(&mut batch).map_err(limit_failure)?;
        n += k;
        if k < batch.len() {
            return Ok(n);
        }
    }
}

impl Text<'_> {
    /// The offset of a position in the text's own positions (from 1); past the end, its length plus one.
    fn offset(&self, start: c_int) -> usize {
        match self {
            Text::Chars(s) => offset_of(s, start),
            Text::Bytes(s) => (start.max(1) as usize - 1).min(s.len() + 1),
            Text::Units(u) => (start.max(1) as usize - 1).min(u.len() + 1),
        }
    }

    fn first(
        &self,
        c: &Compiled,
        start: usize,
        limit: Option<Duration>,
        out: &mut Vec<Option<(usize, usize)>>,
    ) -> Result<bool> {
        match self {
            Text::Chars(s) | Text::Bytes(s) => first(c, *s, start, limit, out),
            Text::Units(u) => first(c, &u[..], start, limit, out),
        }
    }

    fn all(&self, c: &Compiled, whole: bool, out: &mut Vec<Option<(usize, usize)>>) -> Result<usize> {
        match self {
            Text::Chars(s) | Text::Bytes(s) => all(c, *s, whole, out),
            Text::Units(u) => all(c, &u[..], whole, out),
        }
    }

    fn count(&self, c: &Compiled) -> Result<usize> {
        match self {
            Text::Chars(s) | Text::Bytes(s) => count(c, *s),
            Text::Units(u) => count(c, &u[..]),
        }
    }

    fn len(&self) -> usize {
        match self {
            Text::Chars(s) | Text::Bytes(s) => s.len(),
            Text::Units(u) => u.len(),
        }
    }

    /// The R value of the text from `a` to `b`: a CHARSXP for a string (a half character as U+FFFD), a raw vector
    /// (likewise), or an `ecma_utf16`.
    unsafe fn piece(&self, a: usize, b: usize) -> SEXP {
        unsafe {
            match self {
                Text::Chars(s) => mk_char(&piece(s, a, b)),
                Text::Bytes(s) => raw_vector(piece(s, a, b).as_bytes()),
                Text::Units(u) => units_vector(&u[a..b.max(a)]),
            }
        }
    }
}

/// The vector of R values for texts of `x`'s form: a character vector for a character vector, else a list.
unsafe fn texts_vector(x: SEXP, n: R_xlen_t) -> SEXP {
    unsafe { Rf_allocVector(if TYPEOF(x) == STRSXP { STRSXP } else { VECSXP } as c_uint, n) }
}

/// Sets element `i` of a vector from [`texts_vector`] to a text (`None` for NA, NULL in a list).
unsafe fn set_text(out: SEXP, i: R_xlen_t, value: Option<SEXP>) {
    unsafe {
        if TYPEOF(out) == STRSXP {
            SET_STRING_ELT(out, i, value.unwrap_or_else(na_string));
        } else {
            SET_VECTOR_ELT(out, i, value.unwrap_or_else(nil));
        }
    }
}

/// The elements of a character vector, recycled to `n`.
unsafe fn element(x: SEXP, i: R_xlen_t) -> SEXP {
    unsafe { STRING_ELT(x, i % Rf_xlength(x)) }
}

fn check_strings(x: SEXP, what: &str) -> Result<()> {
    if unsafe { TYPEOF(x) } != STRSXP {
        return Err(Failure::new("argument", format!("{what} must be a character vector")));
    }
    Ok(())
}

/// The text of a pattern: a string, or a raw vector of UTF-8 (which may hold a NUL); `None` for NA.
///
/// SAFETY: the pattern must be protected for as long as the text is used.
unsafe fn pattern_of<'a>(p: SEXP) -> Result<Option<&'a str>> {
    unsafe {
        match item_of(p) {
            Ok(Some(Text::Chars(s) | Text::Bytes(s))) => Ok(Some(s)),
            Ok(None) => Ok(None),
            Err(e) => Err(e),
            Ok(Some(Text::Units(_))) => {
                Err(Failure::new("argument", "a pattern must be a string or a raw vector of UTF-8"))
            }
        }
    }
}

/// Called once when the package loads (see init.c).
///
/// # Safety
/// The arguments are R\'s `R_NilValue`, `R_ClassSymbol` and `R_NaString`, and the symbol that tags a regular
/// expression\'s external pointer.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_init(nil: SEXP, class_symbol: SEXP, na_string: SEXP, regex_tag: SEXP) {
    set_globals(nil, class_symbol, na_string, regex_tag);
}

/// Whether the session's native encoding is UTF-8, from `l10n_info()` when the package loads.
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_set_utf8_session(utf8: SEXP) -> SEXP {
    entry(|| unsafe {
        UTF8_SESSION
            .store(TYPEOF(utf8) == LGLSXP && Rf_xlength(utf8) == 1 && LOGICAL_ELT(utf8, 0) == 1, Ordering::Relaxed);
        Ok(nil())
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn crer_version() -> SEXP {
    entry(|| Ok(unsafe { string_vector(&[env!("CARGO_PKG_VERSION"), ecma_version()]) }))
}

/// The crate's version, from the lock file the package was built with.
fn ecma_version() -> &'static str {
    const LOCK: &str = include_str!("../Cargo.lock");
    let mut lines = LOCK.lines();
    while let Some(line) = lines.next() {
        if line == "name = \"corvus-regex-ecma262\""
            && let Some(v) = lines.next().and_then(|l| l.strip_prefix("version = \""))
        {
            return v.trim_end_matches('"');
        }
    }
    ""
}

/// The UTF-16 code units of a string or of a raw vector of UTF-8: an integer vector, which the R layer classes.
///
/// # Safety
/// The argument is a live R value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_utf16(x: SEXP) -> SEXP {
    entry(|| unsafe {
        let units: Vec<u16> = match item_of(x)? {
            Some(Text::Chars(s) | Text::Bytes(s)) => s.encode_utf16().collect(),
            Some(Text::Units(u)) => u,
            None => return Err(Failure::new("argument", "the text must not be NA")),
        };
        let v = Rf_protect(Rf_allocVector(INTSXP as c_uint, units.len() as R_xlen_t));
        let o = INTEGER(v);
        for (i, &u) in units.iter().enumerate() {
            *o.add(i) = c_int::from(u);
        }
        Rf_unprotect(1);
        Ok(v)
    })
}

/// The text of UTF-16 code units (an integer vector): `as_raw` FALSE, a string, a lone surrogate as U+FFFD (a NUL
/// a failure, which an R string cannot hold); TRUE, a raw vector of its UTF-8, a lone surrogate likewise.
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_from_utf16(x: SEXP, as_raw: SEXP) -> SEXP {
    entry(|| unsafe {
        let s = String::from_utf16_lossy(&units_of(x)?);
        if LOGICAL_ELT(as_raw, 0) == 1 {
            return Ok(raw_vector(s.as_bytes()));
        }
        if s.contains('\0') {
            return Err(Failure::new("encoding", "an R string cannot hold a NUL: the text can be a raw vector"));
        }
        Ok(string_vector(&[&s]))
    })
}

/// Compiles a pattern (a string, or a raw vector of UTF-8) with a timeout in seconds (0 for none, NA for the
/// default), in the grammar of an edition and under a version of Unicode (the codes of edition_of and
/// unicode_version_of): an external pointer, or a failure.
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_compile(pattern: SEXP, flags: SEXP, timeout: SEXP, edition: SEXP, version: SEXP) -> SEXP {
    entry(|| unsafe {
        check_strings(flags, "flags")?;
        if (TYPEOF(pattern) != RAWSXP && Rf_xlength(pattern) != 1) || Rf_xlength(flags) != 1 {
            return Err(Failure::new("argument", "pattern and flags must each be one string"));
        }
        if TYPEOF(pattern) != STRSXP && TYPEOF(pattern) != RAWSXP {
            return Err(Failure::new("argument", "pattern must be a string or a raw vector of UTF-8"));
        }
        let (Some(p), Some(f)) = (pattern_of(pattern)?, text_of(STRING_ELT(flags, 0))?) else {
            return Err(Failure::new("argument", "pattern and flags must not be NA"));
        };
        let mut builder = ecma::RegexBuilder::new(p);
        builder.flags(f).edition(edition_of(edition)?).unicode_version(unicode_version_of(version)?);
        if let Some(t) = limit_of(REAL_ELT(timeout, 0))? {
            builder.match_timeout(Some(t));
        }
        let re = builder.build().map_err(compile_failure)?;
        let names = re.group_names().map(String::from).collect();
        let ptr = Rf_protect(R_MakeExternalPtr(
            Box::into_raw(Box::new(Compiled { re, names })) as *mut c_void,
            regex_tag(),
            nil(),
        ));
        R_RegisterCFinalizerEx(ptr, finalize, 1);
        Rf_unprotect(1);
        Ok(ptr)
    })
}

/// Sets the timeout in seconds of every pattern compiled from now on without one (0 or NA for none): NULL, or a
/// failure.
///
/// # Safety
/// The argument is a live R value.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_set_default_timeout(seconds: SEXP) -> SEXP {
    entry(|| unsafe {
        ecma::set_default_match_timeout(limit_of(REAL_ELT(seconds, 0))?);
        Ok(nil())
    })
}

/// The timeout in seconds of a pattern compiled now without one: a number, NA for none.
#[unsafe(no_mangle)]
pub extern "C" fn crer_default_timeout() -> SEXP {
    unsafe { Rf_ScalarReal(ecma::default_match_timeout().map_or(na_real(), |t| t.as_secs_f64())) }
}

/// What a compiled pattern is: list(source (a raw vector of UTF-8 where it holds a NUL), flags, group count, names,
/// timeout (NA for none), edition ("current" or "es2020"), version of Unicode (resolved)).
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_info(re: SEXP) -> SEXP {
    entry(|| unsafe {
        let c = compiled(re)?;
        let list = Rf_protect(Rf_allocVector(VECSXP as c_uint, 7));
        let source = c.re.as_str();
        SET_VECTOR_ELT(
            list,
            0,
            if source.contains('\0') { raw_vector(source.as_bytes()) } else { string_vector(&[source]) },
        );
        SET_VECTOR_ELT(list, 1, string_vector(&[&c.re.flags().to_string()]));
        let groups = Rf_allocVector(INTSXP as c_uint, 1);
        SET_VECTOR_ELT(list, 2, groups);
        *INTEGER(groups) = (c.re.captures_len() - 1) as c_int;
        let names: Vec<&str> = c.names.iter().map(String::as_str).collect();
        SET_VECTOR_ELT(list, 3, string_vector(&names));
        SET_VECTOR_ELT(list, 4, Rf_ScalarReal(c.re.match_timeout().map_or(na_real(), |t| t.as_secs_f64())));
        let edition = if c.re.edition() == ecma::Edition::Es2020 { "es2020" } else { "current" };
        SET_VECTOR_ELT(list, 5, string_vector(&[edition]));
        let version = Rf_allocVector(INTSXP as c_uint, 1);
        SET_VECTOR_ELT(list, 6, version);
        *INTEGER(version) = c.re.unicode_version().major() as c_int;
        Rf_unprotect(1);
        Ok(list)
    })
}

/// Whether each pattern (a character vector, or a list of strings and raw vectors) is valid with the flags
/// (recycled), in the grammar of an edition and under a version of Unicode (the codes of edition_of and
/// unicode_version_of): a logical vector, NA for NA.
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_valid(patterns: SEXP, flags: SEXP, edition: SEXP, version: SEXP) -> SEXP {
    entry(|| unsafe {
        check_texts(patterns, "pattern")?;
        check_strings(flags, "flags")?;
        let (edition, version) = (edition_of(edition)?, unicode_version_of(version)?);
        let n = Rf_xlength(patterns);
        if n > 0 && Rf_xlength(flags) == 0 {
            return Err(Failure::new("argument", "flags must not be empty"));
        }
        let out = Rf_protect(Rf_allocVector(LGLSXP as c_uint, n));
        let o = LOGICAL(out);
        for i in 0..n {
            let p = if TYPEOF(patterns) == STRSXP {
                text_of(STRING_ELT(patterns, i))
            } else {
                pattern_of(VECTOR_ELT(patterns, i))
            };
            let r = match (p, text_of(element(flags, i))) {
                (Ok(Some(p)), Ok(Some(f))) => {
                    ecma::Flags::parse(f).is_ok_and(|f| ecma::Regex::is_valid_with(p, f, edition, version)) as c_int
                }
                (Ok(None), _) | (_, Ok(None)) => NA_INTEGER,
                (Err(e), _) | (_, Err(e)) => {
                    Rf_unprotect(1);
                    return Err(e);
                }
            };
            *o.offset(i) = r;
        }
        Rf_unprotect(1);
        Ok(out)
    })
}

/// The first match in each text at or after `start` (in the text's positions, recycled), with a timeout (seconds,
/// NA for none). `mode` 0: whether there is one (logical); 1: its text and each group's, row by row (a character
/// vector for a character vector, else a list; a row of `width` for each text, NA or NULL for no match or a group
/// that did not take part); 2: the start and end of each group (integer, two entries for each group in a row of 2 ×
/// `width`).
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_first(re: SEXP, x: SEXP, start: SEXP, timeout: SEXP, mode: SEXP) -> SEXP {
    entry(|| unsafe {
        let c = compiled(re)?;
        check_texts(x, "x")?;
        let limit = limit_of(REAL_ELT(timeout, 0))?;
        let mode = INTEGER_ELT(mode, 0);
        let n = Rf_xlength(x);
        let starts = Rf_xlength(start);
        let w = width(c) as R_xlen_t;
        let out = Rf_protect(match mode {
            0 => Rf_allocVector(LGLSXP as c_uint, n),
            1 => texts_vector(x, n * w),
            _ => Rf_allocVector(INTSXP as c_uint, n * w * 2),
        });
        let mut spans = Vec::with_capacity(w as usize);
        let result = (|| {
            for i in 0..n {
                let text = text_at(x, i)?;
                let at = if starts == 0 { 1 } else { INTEGER_ELT(start, i % starts) };
                let found = match &text {
                    Some(t) if at != NA_INTEGER => {
                        spans.clear();
                        Some(t.first(c, t.offset(at), limit, &mut spans)?)
                    }
                    _ => None,
                };
                // The match's groups, or none (each then NA) where there is no match.
                let row: &[Option<(usize, usize)>] = if found == Some(true) { &spans } else { &[] };
                match mode {
                    0 => *LOGICAL(out).offset(i) = found.map_or(NA_INTEGER, |f| f as c_int),
                    1 => {
                        for g in 0..w {
                            let v = match (&text, row.get(g as usize).copied().flatten()) {
                                (Some(t), Some((a, b))) => Some(t.piece(a, b)),
                                _ => None,
                            };
                            set_text(out, i * w + g, v);
                        }
                    }
                    _ => {
                        let o = INTEGER(out).offset(i * w * 2);
                        let mut p = Positions::new();
                        for g in 0..w as usize {
                            let (a, b) = match (&text, row.get(g).copied().flatten()) {
                                (Some(t), Some((a, b))) => p.of(t, a, b),
                                _ => (NA_INTEGER, NA_INTEGER),
                            };
                            *o.add(2 * g) = a;
                            *o.add(2 * g + 1) = b;
                        }
                    }
                }
            }
            Ok(())
        })();
        Rf_unprotect(1);
        result.map(|()| out)
    })
}

/// Every match of a global search in each text: a list with an element for each text (NULL for NA). `mode` 1: the
/// text of each match and its groups, row by row (a character vector for a string, else a list; `width` for each
/// match); 2: the start and end of each match alone (integer, two for each match); 3: the start and end of the match
/// and each group (integer, 2 × `width` for each match).
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_all(re: SEXP, x: SEXP, mode: SEXP) -> SEXP {
    entry(|| unsafe {
        let c = compiled(re)?;
        check_texts(x, "x")?;
        let mode = INTEGER_ELT(mode, 0);
        let n = Rf_xlength(x);
        let out = Rf_protect(Rf_allocVector(VECSXP as c_uint, n));
        let mut spans = Vec::new();
        let result = (|| {
            for i in 0..n {
                let Some(t) = text_at(x, i)? else { continue };
                spans.clear();
                t.all(c, mode == 2, &mut spans)?;
                if mode == 1 {
                    let v = texts_vector(x, spans.len() as R_xlen_t);
                    SET_VECTOR_ELT(out, i, v);
                    for (j, span) in spans.iter().enumerate() {
                        set_text(v, j as R_xlen_t, span.map(|(a, b)| t.piece(a, b)));
                    }
                } else {
                    let v = Rf_allocVector(INTSXP as c_uint, 2 * spans.len() as R_xlen_t);
                    SET_VECTOR_ELT(out, i, v);
                    let o = INTEGER(v);
                    let mut p = Positions::new();
                    for (j, span) in spans.iter().enumerate() {
                        let (a, b) = span.map_or((NA_INTEGER, NA_INTEGER), |(a, b)| p.of(&t, a, b));
                        *o.add(2 * j) = a;
                        *o.add(2 * j + 1) = b;
                    }
                }
            }
            Ok(())
        })();
        Rf_unprotect(1);
        result.map(|()| out)
    })
}

/// How many matches a global search finds in each text: an integer vector, NA for NA.
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_count(re: SEXP, x: SEXP) -> SEXP {
    entry(|| unsafe {
        let c = compiled(re)?;
        check_texts(x, "x")?;
        let n = Rf_xlength(x);
        let out = Rf_protect(Rf_allocVector(INTSXP as c_uint, n));
        let o = INTEGER(out);
        let result = (|| {
            for i in 0..n {
                *o.offset(i) = match text_at(x, i)? {
                    Some(t) => c_int::try_from(t.count(c)?).unwrap_or(NA_INTEGER),
                    None => NA_INTEGER,
                };
            }
            Ok(())
        })();
        Rf_unprotect(1);
        result.map(|()| out)
    })
}

/// Each text with its first match replaced, or every match when `all` is TRUE or the pattern has the g flag
/// (`String.prototype.replace` and `replaceAll`), by the template (recycled; for a list of texts, a string, a raw
/// vector or an `ecma_utf16` for each): a character vector for a character vector, else a list of texts in the
/// form of each, NA (NULL) where the text or the template is.
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_replace(re: SEXP, x: SEXP, template: SEXP, all: SEXP) -> SEXP {
    entry(|| unsafe {
        let c = compiled(re)?;
        check_texts(x, "x")?;
        if TYPEOF(x) == STRSXP {
            check_strings(template, "replacement")?;
        } else {
            check_texts(template, "replacement")?;
        }
        let every = LOGICAL_ELT(all, 0) == 1;
        let n = Rf_xlength(x);
        let templates = Rf_xlength(template);
        if n > 0 && templates == 0 {
            return Err(Failure::new("argument", "replacement must not be empty"));
        }
        let out = Rf_protect(texts_vector(x, n));
        let result = (|| {
            for i in 0..n {
                let v = match (text_at(x, i)?, text_at(template, i % templates)?) {
                    (Some(Text::Chars(s)), Some(Text::Chars(t))) => {
                        let r = str::replaced(&c.re, s, t, every).map_err(limit_failure)?;
                        Some(if matches!(r, Cow::Borrowed(_)) { STRING_ELT(x, i) } else { mk_char(&r) })
                    }
                    (Some(Text::Units(u)), Some(t)) => {
                        let t: Cow<'_, [u16]> = match t {
                            Text::Units(t) => Cow::Owned(t),
                            Text::Chars(t) | Text::Bytes(t) => Cow::Owned(t.encode_utf16().collect()),
                        };
                        Some(units_vector(&<[u16]>::replaced(&c.re, &u, &t, every).map_err(limit_failure)?))
                    }
                    (Some(Text::Chars(s) | Text::Bytes(s)), Some(t)) => {
                        let t: Cow<'_, str> = match t {
                            Text::Units(t) => Cow::Owned(String::from_utf16_lossy(&t)),
                            Text::Chars(t) | Text::Bytes(t) => Cow::Borrowed(t),
                        };
                        Some(raw_vector(str::replaced(&c.re, s, &t, every).map_err(limit_failure)?.as_bytes()))
                    }
                    _ => None,
                };
                set_text(out, i, v);
            }
            Ok(())
        })();
        Rf_unprotect(1);
        result.map(|()| out)
    })
}

/// The pieces of each text around its first match, or every match when `all` is TRUE or the pattern has the g
/// flag, for a replacement R makes: a list with an element for each text (NULL for NA), list(the k + 1 pieces
/// between the matches, the text of each match and its groups row by row, `width` for each), each a character
/// vector for a string and a list for a raw vector or an `ecma_utf16`.
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_pieces(re: SEXP, x: SEXP, all: SEXP) -> SEXP {
    entry(|| unsafe {
        let c = compiled(re)?;
        check_texts(x, "x")?;
        let every = LOGICAL_ELT(all, 0) == 1 || c.re.flags().global;
        let n = Rf_xlength(x);
        let out = Rf_protect(Rf_allocVector(VECSXP as c_uint, n));
        let mut spans = Vec::new();
        let w = width(c);
        let result = (|| {
            for i in 0..n {
                let Some(t) = text_at(x, i)? else { continue };
                spans.clear();
                let k = if every {
                    t.all(c, false, &mut spans)?
                } else {
                    // replace without g starts at 0 whatever lastIndex is, but a sticky pattern must match there.
                    t.first(c, 0, None, &mut spans)? as usize
                };
                let item = Rf_allocVector(VECSXP as c_uint, 2);
                SET_VECTOR_ELT(out, i, item);
                let pieces = texts_vector(x, k as R_xlen_t + 1);
                SET_VECTOR_ELT(item, 0, pieces);
                let groups = texts_vector(x, spans.len() as R_xlen_t);
                SET_VECTOR_ELT(item, 1, groups);
                let mut at = 0;
                for j in 0..k {
                    let (a, b) = spans[j * w].expect("group 0 is the match");
                    set_text(pieces, j as R_xlen_t, Some(t.piece(at, a)));
                    at = b;
                }
                set_text(pieces, k as R_xlen_t, Some(t.piece(at, t.len())));
                for (j, span) in spans.iter().enumerate() {
                    set_text(groups, j as R_xlen_t, span.map(|(a, b)| t.piece(a, b)));
                }
            }
            Ok(())
        })();
        Rf_unprotect(1);
        result.map(|()| out)
    })
}

/// Each text split around the matches (`String.prototype.split`), with at most `limit` pieces (NA for none): a
/// list with an element for each text (NULL for NA), a character vector of the pieces for a string (NA for a group
/// that did not take part) and a list of them for a raw vector or an `ecma_utf16` (NULL for one).
///
/// # Safety
/// The arguments are live R values.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn crer_split(re: SEXP, x: SEXP, limit: SEXP) -> SEXP {
    entry(|| unsafe {
        let c = compiled(re)?;
        check_texts(x, "x")?;
        let limit = INTEGER_ELT(limit, 0);
        let limit = if limit == NA_INTEGER { None } else { Some(limit.max(0) as usize) };
        let n = Rf_xlength(x);
        let out = Rf_protect(Rf_allocVector(VECSXP as c_uint, n));
        let result = (|| {
            for i in 0..n {
                let Some(t) = text_at(x, i)? else { continue };
                match &t {
                    Text::Chars(s) | Text::Bytes(s) => {
                        let parts = str::pieces(&c.re, s, limit).map_err(limit_failure)?;
                        let v = texts_vector(x, parts.len() as R_xlen_t);
                        SET_VECTOR_ELT(out, i, v);
                        for (j, p) in parts.iter().enumerate() {
                            let value = p.as_ref().map(|p| {
                                if matches!(t, Text::Chars(_)) { mk_char(p) } else { raw_vector(p.as_bytes()) }
                            });
                            set_text(v, j as R_xlen_t, value);
                        }
                    }
                    Text::Units(u) => {
                        let parts = <[u16]>::pieces(&c.re, u, limit).map_err(limit_failure)?;
                        let v = texts_vector(x, parts.len() as R_xlen_t);
                        SET_VECTOR_ELT(out, i, v);
                        for (j, p) in parts.iter().enumerate() {
                            set_text(v, j as R_xlen_t, p.as_ref().map(|p| units_vector(p)));
                        }
                    }
                }
            }
            Ok(())
        })();
        Rf_unprotect(1);
        result.map(|()| out)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pieces_write_half_characters_as_replacement_characters() {
        let s = "a😀b";
        assert_eq!(piece(s, 0, 1), "a");
        assert_eq!(piece(s, 1, 3), "\u{FFFD}");
        assert_eq!(piece(s, 3, 5), "\u{FFFD}");
        assert_eq!(piece(s, 1, 5), "😀");
        assert_eq!(piece(s, 3, 3), "");
        assert_eq!(piece(s, 0, 3), "a\u{FFFD}");
    }

    #[test]
    fn positions_round_half_characters_to_the_character() {
        let b = "a😀b".as_bytes();
        let mut p = Positions::new();
        assert_eq!(p.span(b, 0, 1), (1, 1));
        assert_eq!(p.span(b, 1, 3), (2, 2));
        assert_eq!(p.span(b, 3, 5), (2, 2));
        assert_eq!(p.span(b, 5, 6), (3, 3));
        // Empty: the end is one before the start, as R's own functions give it.
        assert_eq!(p.span(b, 5, 5), (3, 2));
    }

    #[test]
    fn offsets_of_character_positions() {
        assert_eq!(offset_of("aéb", 1), 0);
        assert_eq!(offset_of("aéb", 3), 3);
        assert_eq!(offset_of("aéb", 4), 4);
        assert_eq!(offset_of("aéb", 9), 5);
    }
}
