# pg_timescale_duckdb

Container image for a PostgreSQL database bundled with two powerful extensions:

| Extension | Source | License |
|-----------|--------|---------|
| [TimescaleDB](https://github.com/timescale/timescaledb) | built from source | Apache 2.0 (OSS) |
| [pg_duckdb](https://github.com/duckdb/pg_duckdb) | built from source | MIT |

**Base image:** [`postgres:18-alpine`](https://hub.docker.com/_/postgres) (PostgreSQL 18, Alpine Linux)

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) 20.10+
- (optional) [Docker Compose](https://docs.docker.com/compose/) v2

---

## Build the image

```bash
docker build -t pg_timescale_duckdb .
```

> **Note:** The build compiles DuckDB from source, which can take **30–60 minutes** depending on the host machine.

### Build arguments

| Argument | Default | Description |
|----------|---------|-------------|
| `PG_MAJOR` | `18` | PostgreSQL major version |
| `TIMESCALEDB_VERSION` | `main` | TimescaleDB git branch or tag (e.g. `2.17.2`) |
| `PG_DUCKDB_VERSION` | `main` | pg_duckdb git branch or tag (e.g. `v0.10.0`) |

Example with pinned versions:

```bash
docker build \
  --build-arg TIMESCALEDB_VERSION=2.17.2 \
  --build-arg PG_DUCKDB_VERSION=v0.10.0 \
  -t pg_timescale_duckdb:pinned .
```

---

## Run

### Docker

```bash
docker run -d \
  --name pg_timescale_duckdb \
  -e POSTGRES_PASSWORD=secret \
  -p 5432:5432 \
  pg_timescale_duckdb
```

### Docker Compose

```bash
docker compose up -d
```

The compose file uses the variables defined in `docker-compose.yml`; edit them there or override via a `.env` file.

---

## Enable the extensions

After the container is running, connect and create the extensions in your database:

```sql
-- TimescaleDB
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- pg_duckdb
CREATE EXTENSION IF NOT EXISTS pg_duckdb;
```

Both extensions are pre-loaded via `shared_preload_libraries=timescaledb,pg_duckdb` (set in the image `CMD`).

---

## Architecture

The image is built in two stages:

1. **Builder** – installs a C/C++ toolchain on `postgres:18-alpine`, clones both extension repositories, and compiles them against the PostgreSQL headers already present in the image.
2. **Runtime** – starts from a fresh `postgres:18-alpine`, copies only the compiled `.so` files and SQL/control files, and adds the minimal shared libraries required at runtime.
