# The R benchmark harness as an image: this package built from the repository and installed, with jsonlite and stringi
# from the image's package repository, and Node 24 for the V8 rows, with tools/bench/run.sh as the entry point. Built
# from the repository's root:
#
#   docker build -t corvus-regex-ecma262-r .
#   docker run --rm -v <workloads.json>:/workloads.json:ro -v <texts dir>:/texts:ro -v <out dir>:/out <image>
#
# which writes /out/industry.json, the run's data file in the results page's shape. The ECMA-262 test data is cloned
# at depth 1 inside the container unless its data/ directory is mounted at /data. JOB=short, SECONDS_EACH, PASSES,
# CORES, SETTLE and RUN_URL pass through (see tools/bench/run.sh). The central benchmark site runs this image each
# night; .github/workflows/harness-image.yml builds, smoke-runs and publishes it.
FROM node:24.22.0-bookworm-slim@sha256:91acba91b842bec0bf7ea6f5e09c644c7ccad72c4996ed9616d861d1c7cd60d4 AS node

FROM rocker/r-ver:4.6.1@sha256:bafb3b9a72791eeeb810f0bc0472e74c7f4939b20b46c96cb7ebc6838b6a25ef
RUN apt-get update && apt-get install -y --no-install-recommends python3 git util-linux ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local/bin/node /usr/local/bin/node
ENV CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup PATH=/usr/local/cargo/bin:$PATH
RUN curl -sSfL -o /tmp/rustup-init https://static.rust-lang.org/rustup/archive/1.29.2/x86_64-unknown-linux-gnu/rustup-init \
    && echo "5be191e8c70a5007074254cb74d78dbfdd25cd5a61c27de7b8e5410122ec24f4  /tmp/rustup-init" | sha256sum -c - \
    && chmod +x /tmp/rustup-init && /tmp/rustup-init -y --profile minimal --default-toolchain 1.98.0 --no-modify-path && rm /tmp/rustup-init
# jsonlite and stringi from a dated snapshot of CRAN (Posit's binaries for the base image's Ubuntu), not the
# image's moving "latest": a new stringi brings a new ICU, which changes the ICU row's figures.
RUN Rscript -e 'install.packages(c("jsonlite", "stringi"), repos = "https://p3m.dev/cran/__linux__/noble/2026-10-22")'
WORKDIR /harness
COPY . .
RUN MAKEFLAGS=-j4 R CMD INSTALL --no-test-load . && rm -rf src/rust/target
# The commit the image is built from, for the run's record (the image has no .git).
ARG COMMIT=""
ENV CORVUS_COMMIT=$COMMIT
ENTRYPOINT ["/harness/tools/bench/container-entry.sh"]
