# PostgreSQL 18 Alpine with TimescaleDB (OSS) and pg_duckdb
#
# Build arguments (override with --build-arg):
#   PG_MAJOR            PostgreSQL major version          (default: 18)
#   TIMESCALEDB_VERSION TimescaleDB git branch/tag        (default: main)
#   PG_DUCKDB_VERSION   pg_duckdb git branch/tag          (default: main)
#
# Build example:
#   docker build -t pg_timescale_duckdb .
#
# Run example:
#   docker run --rm -e POSTGRES_PASSWORD=secret -p 5432:5432 pg_timescale_duckdb

ARG PG_MAJOR=18

# ---------------------------------------------------------------------------
# Stage 1 – compile TimescaleDB and pg_duckdb against the target PostgreSQL
# ---------------------------------------------------------------------------
FROM postgres:${PG_MAJOR}-alpine AS builder

ARG PG_MAJOR=18
ARG TIMESCALEDB_VERSION=main
ARG PG_DUCKDB_VERSION=main

# Build-time toolchain
# Notes:
#   • curl   – needed by DuckDB cmake checks
#   • perl   – required by PostgreSQL PGXS Makefile infrastructure
#   • python3 – needed by DuckDB cmake configuration scripts
RUN apk add --no-cache \
        build-base \
        cmake \
        curl \
        git \
        bash \
        perl \
        python3 \
        openssl-dev \
        lz4-dev \
        zstd-dev \
        linux-headers

# -------------------------------------------------------------------------
# TimescaleDB – OSS (Apache 2.0)
# -------------------------------------------------------------------------
# bootstrap is a thin wrapper around cmake; BUILD_FORCE_REMOVE avoids the
# interactive prompt that appears when the build directory already exists.
RUN git clone \
        --branch "${TIMESCALEDB_VERSION}" \
        https://github.com/timescale/timescaledb.git \
        /tmp/timescaledb \
    && cd /tmp/timescaledb \
    && BUILD_FORCE_REMOVE=true ./bootstrap \
        -DCMAKE_BUILD_TYPE=Release \
        -DREGRESS_CHECKS=OFF \
        -DTAP_CHECKS=OFF \
        -DGENERATE_DOWNGRADE_SCRIPTS=OFF \
        -DWARNINGS_AS_ERRORS=OFF \
    && cd build \
    && make -j"$(nproc)" \
    && make install \
    && rm -rf /tmp/timescaledb

# -------------------------------------------------------------------------
# pg_duckdb
# -------------------------------------------------------------------------
# DuckDB is bundled as a git submodule and compiled from source.
# DUCKDB_GEN=make avoids the ninja dependency while still using parallel
# make (-j) for speed.  libduckdb.so is installed to $(pg_config --pkglibdir)
# together with pg_duckdb.so; the extension's RPATH points there so the
# dynamic linker resolves it correctly at runtime.
RUN git clone \
        --branch "${PG_DUCKDB_VERSION}" \
        https://github.com/duckdb/pg_duckdb.git \
        /tmp/pg_duckdb \
    && cd /tmp/pg_duckdb \
    && git submodule update --init --recursive \
    && make -j"$(nproc)" DUCKDB_GEN=make install \
    && rm -rf /tmp/pg_duckdb

# ---------------------------------------------------------------------------
# Stage 2 – lean runtime image
# ---------------------------------------------------------------------------
FROM postgres:${PG_MAJOR}-alpine

ARG PG_MAJOR=18
ARG TIMESCALEDB_VERSION
ARG PG_DUCKDB_VERSION

LABEL org.opencontainers.image.title="pg_timescale_duckdb" \
      org.opencontainers.image.description="PostgreSQL ${PG_MAJOR} Alpine with TimescaleDB OSS and pg_duckdb" \
      org.opencontainers.image.source="https://github.com/matzek92/pg_timescale_duckdb"

# Runtime libraries required by the extensions:
#   libstdc++ / libgomp  – C++ runtime + OpenMP (pg_duckdb / DuckDB)
#   lz4-libs / zstd-libs – compression support used by both extensions
#   openssl              – TLS / crypto (TimescaleDB)
RUN apk add --no-cache \
        libstdc++ \
        libgomp \
        lz4-libs \
        zstd-libs \
        openssl

# Copy the compiled extension shared libraries (.so) and their SQL/control files.
# pg_duckdb installs both pg_duckdb.so and libduckdb.so to pkglibdir, so this
# single COPY covers everything needed at runtime.
COPY --from=builder /usr/local/lib/postgresql/   /usr/local/lib/postgresql/
COPY --from=builder /usr/local/share/postgresql/extension/ \
                    /usr/local/share/postgresql/extension/

# Pre-load both extensions at server start.
# Users can override this via docker run -e POSTGRES_INITDB_ARGS or by
# mounting a custom postgresql.conf.
CMD ["postgres", "-c", "shared_preload_libraries=timescaledb,pg_duckdb"]
