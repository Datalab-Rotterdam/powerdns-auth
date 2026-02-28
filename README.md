# PowerDNS Authoritative Server Docker Image

A flexible Docker image for PowerDNS Authoritative Server with runtime backend selection via `PDNS_launch`.

Built on `debian:trixie-slim`, the image runs as the `pdns` user and includes the official PowerDNS auth repository plus the main backend packages.

## Features

- Includes the common official backends: `gpgsql`, `gmysql`, `gsqlite3`, `bind`, `lmdb`, `ldap`, `geoip`, `lua2`, `pipe`, `remote`, `tinydns`, and `godbc`
- Initializes PostgreSQL, MySQL, and SQLite3 schemas automatically
- Generates `pdns.conf` from `PDNS_` environment variables using `subvars`
- Defaults to SQLite3 with `PDNS_gsqlite3_database=/var/lib/powerdns/pdns.sqlite3`
- Runs as the `pdns` user

## Usage

### Basic SQLite3

```sh
docker run -d \
  --name pdns \
  -p 53:53 \
  -p 53:53/udp \
  -v ./data:/var/lib/powerdns \
  ghcr.io/alexanderslaa/powerdns-auth:latest
```

### PostgreSQL

```sh
docker run -d \
  --name pdns \
  -p 53:53 \
  -p 53:53/udp \
  -e PDNS_launch=gpgsql \
  -e PDNS_gpgsql_host=postgres \
  -e PDNS_gpgsql_port=5432 \
  -e PDNS_gpgsql_user=pdns \
  -e PDNS_gpgsql_password=secret \
  -e PDNS_gpgsql_dbname=pdns \
  --network my-net \
  ghcr.io/alexanderslaa/powerdns-auth:latest
```

### MySQL

```sh
docker run -d \
  --name pdns \
  -p 53:53 \
  -p 53:53/udp \
  -e PDNS_launch=gmysql \
  -e PDNS_gmysql_host=mysql \
  -e PDNS_gmysql_port=3306 \
  -e PDNS_gmysql_user=pdns \
  -e PDNS_gmysql_password=secret \
  -e PDNS_gmysql_dbname=pdns \
  --network my-net \
  ghcr.io/alexanderslaa/powerdns-auth:latest
```

## Configuration

Any PowerDNS setting can be passed as an environment variable prefixed with `PDNS_`.

Examples:

- `launch=gpgsql,gsqlite3` becomes `PDNS_launch=gpgsql,gsqlite3`
- `allow-axfr-ips=10.0.0.1` becomes `PDNS_allow_axfr_ips=10.0.0.1`
- `gsqlite3-database=/var/lib/powerdns/pdns.sqlite3` becomes `PDNS_gsqlite3_database=/var/lib/powerdns/pdns.sqlite3`

Common defaults:

| Variable | Default |
| --- | --- |
| `PDNS_launch` | `gsqlite3` |
| `PDNS_gsqlite3_database` | `/var/lib/powerdns/pdns.sqlite3` |
| `PDNS_guardian` | `yes` |
| `PDNS_setuid` | `pdns` |
| `PDNS_setgid` | `pdns` |

Reference: https://doc.powerdns.com/authoritative/

## Database Initialization

Set `SKIP_DB_INIT=true` to skip schema setup entirely.

Set `SKIP_DB_CREATE=true` to skip only database creation for PostgreSQL or MySQL.

## Volumes

Mounted paths must be writable by the `pdns` user inside the container.

- SQLite3 and LMDB data: mount `/var/lib/powerdns`
- BIND backend files: mount the relevant config and zone paths under `/etc/powerdns`

## Compose Examples

- SQLite3: `docker compose -f docker-compose.sqlite.yml up --build`
- PostgreSQL: `docker compose -f docker-compose.yml up --build`
- MySQL: `docker compose -f docker-compose.mysql.yml up --build`

## Building

```sh
docker build -t pdns-authoritative .
```

For multi-arch builds:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/alexanderslaa/powerdns-auth:latest --push .
```
