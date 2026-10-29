# Contributing

This guide is for someone who wants to build the package, run its tests and gates, and open a pull request. It covers
the tools, the build step by step, the gates every change must pass, and how a pull request is released. The
[design document](design.md) describes what is underneath.

## 1. Tools

| Tool | Needed for | Version |
|---|---|---|
| R | Everything | 4.2 or later, with its development tools (Rtools on Windows) |
| Rust | The native code | 1.89 or later; 1.98.0 for the format and lint gate |
| Git | The repository and the test data | Any recent version |
| jsonlite | The test-data runner | Any recent version |
| Node.js | The test data for other versions of Unicode and for ECMAScript 2020, and the V8 rows of the harness | 24 (the V8 it carries is the oracle) |
| PowerShell 7 | The release scripts (`tools/release`) | 7.4 or later |

- **Windows:** R and the matching Rtools from CRAN; `winget install Rustlang.Rustup Git.Git OpenJS.NodeJS.LTS
  Microsoft.PowerShell`, with the `x86_64-pc-windows-gnu` Rust target R's toolchain links.
- **Linux:** R with its development package (`r-base-dev` on Ubuntu); `rustup` from [rustup.rs](https://rustup.rs);
  Node.js 24 from nodejs.org.
- **macOS:** R from CRAN with the Xcode command line tools; `brew install rustup git node@24 powershell`, then
  `rustup-init`.

## 2. Getting the sources

```
git clone https://github.com/corvus-dotnet/corvus-regex-ecma262-r.git
git clone https://github.com/corvus-dotnet/ecma262-regex-test-data.git   # beside it: the test data
cd corvus-regex-ecma262-r
```

The test data is the oracle for the engine; the commands below assume it at `../ecma262-regex-test-data`.

## 3. Building and testing, step by step

Every command runs from the repository root.

1. **The native code.** From `src/rust`: `cargo +1.98.0 fmt --check`, `cargo +1.98.0 clippy --all-targets --locked --
   -D warnings` and `cargo test --locked` must pass. `Cargo.toml`'s `rust-version` must be the rustc named in
   `DESCRIPTION`'s SystemRequirements.
2. **The check.** `R CMD build .`, then `R CMD check --no-manual corvusregexecma262_*.tar.gz` must run the tests and
   give no warning (but the one R 4.2's linker on Windows gives for every Rust object).
3. **Install.** `MAKEFLAGS=-j4 R CMD INSTALL .` installs the package for the steps that follow.
4. **The getting-started page's examples.** `Rscript tools/docs/run-getting-started.R` runs each block of the page.
5. **The test data.** `Rscript -e 'install.packages("jsonlite")'` once, then
   `Rscript tools/dataset.R ../ecma262-regex-test-data/data wrong-cases.tsv` must report 0 wrong, 0 refused and 0 at a
   limit. For the other versions of Unicode and for ECMAScript 2020, write the data with its own scripts and run it with
   the package set to match:

   ```
   node ../ecma262-regex-test-data/unicode.js apply 13.0 /tmp/u13 ../ecma262-regex-test-data/data
   Rscript tools/dataset.R /tmp/u13 wrong-u13.tsv --unicode 13
   node ../ecma262-regex-test-data/edition.js apply /tmp/es2020 "" ../ecma262-regex-test-data/data
   Rscript tools/dataset.R /tmp/es2020 wrong-es2020.tsv --edition es2020
   ```

## 4. The crate and R-universe

The engine is the `corvus-regex-ecma262` crate from crates.io, at the version `src/rust/Cargo.toml` names; a fix to the
engine is made in [the crate's repository](https://github.com/corvus-dotnet/corvus-regex-ecma262-rs), released, and
taken here by moving that version. `DESCRIPTION`, `src/rust/Cargo.toml` and `src/rust/Cargo.lock` hold `0.0.0` on
main. R-universe builds the package from the source at the latest release (its registry entry names the branch
`*release`), so a release tags a commit with the version written in, which is on no branch.

## 5. Benchmarks

`tools/bench/run.sh <workloads.json> <texts directory> <out.json>` runs this package, base R's `gregexpr`, stringi and
V8 over the Industry workloads; the script lists what it needs and its settings. The published figures are on
[the benchmark page](https://corvus-oss.org/corvus-regex-ecma262-benchmarks/), which runs this repository's harness
image each night beside every other engine; a run on another machine is comparable with itself, never with the page.

## 6. What a pull request needs

- **The gates of section 3** passing on the change as pushed, on every platform and R version CI checks.
- **A fix to the engine's answers in the crate**, with its case in the test data first: the data repository's
  families are built around the faults found, with V8 as the oracle.
- **A failing test first** for a bug in the package: the test that reproduces it, then the fix.
- **The design document kept current**, describing the package as it is.
- **The help pages** (`man/`) kept true for every exported function, since they are the API reference.
- **The getting-started page** kept true: its examples are run in CI.

### Conventions

- The native code is Rust, formatted by `rustfmt` and clean under clippy at `-D warnings`, and never calls `Rf_error`:
  a failure is returned to the R layer, which raises it.
- A string marked as UTF-8 is read where R holds it, with no copy.

## 7. Releases

Every pull request merged into main releases what it changed, unless it is labelled `no_release`. `auto-release.yml`
runs `tools/release/release.ps1` on the merge: when the package changed since its last tag (`DESCRIPTION`,
`NAMESPACE`, `R/`, `src/`, `configure`, `configure.win`, or a published document), it makes a GitHub release tagged
`v<version>` with the next patch version, on a commit with the version written in, which R-universe builds. A change to
the benchmark harness alone is a harness release, which publishes the harness image. A pull request that needs a minor
or major version sets `nextVersion` in `.github/release.json`; a minor version is a breaking change.

`main` is protected by a ruleset: changes arrive by pull request, and the `CI gate` and `Harness image` checks must be
green on the branch as it will merge.
