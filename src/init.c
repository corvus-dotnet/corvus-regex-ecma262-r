/* Registers the package's native routines, which are written in Rust (src/rust), and passes R's global values to
   them: they are data exported by R's library, which the Rust code does not import. */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>

void crer_init(SEXP nil, SEXP class, SEXP na_string, SEXP regex_tag);
SEXP crer_set_utf8_session(SEXP utf8);
SEXP crer_version(void);
SEXP crer_compile(SEXP pattern, SEXP flags);
SEXP crer_info(SEXP regex);
SEXP crer_valid(SEXP patterns, SEXP flags);
SEXP crer_first(SEXP regex, SEXP x, SEXP start, SEXP timeout, SEXP mode);
SEXP crer_all(SEXP regex, SEXP x, SEXP mode);
SEXP crer_count(SEXP regex, SEXP x);
SEXP crer_replace(SEXP regex, SEXP x, SEXP replacement, SEXP all);
SEXP crer_pieces(SEXP regex, SEXP x, SEXP all);
SEXP crer_split(SEXP regex, SEXP x, SEXP limit);

static const R_CallMethodDef call_methods[] = {
    {"crer_set_utf8_session", (DL_FUNC) &crer_set_utf8_session, 1},
    {"crer_version", (DL_FUNC) &crer_version, 0},
    {"crer_compile", (DL_FUNC) &crer_compile, 2},
    {"crer_info", (DL_FUNC) &crer_info, 1},
    {"crer_valid", (DL_FUNC) &crer_valid, 2},
    {"crer_first", (DL_FUNC) &crer_first, 5},
    {"crer_all", (DL_FUNC) &crer_all, 3},
    {"crer_count", (DL_FUNC) &crer_count, 2},
    {"crer_replace", (DL_FUNC) &crer_replace, 4},
    {"crer_pieces", (DL_FUNC) &crer_pieces, 3},
    {"crer_split", (DL_FUNC) &crer_split, 3},
    {NULL, NULL, 0}
};

void R_init_corvusregexecma262(DllInfo *dll) {
    crer_init(R_NilValue, R_ClassSymbol, NA_STRING, Rf_install("corvus_regex_ecma262"));
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
