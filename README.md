# PowerDNS Authoritative Server Docker Image

![Docker Image Version](https://img.shields.io/docker/v/dl010/powerdns-auth)
![Docker Pulls](https://img.shields.io/docker/pulls/dl010/powerdns-auth)
![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/AlexanderSlaa/powerdns-auth/publish.yml)


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

> [!WARNING]
> The provided Docker Compose examples expose database ports on the host machine.  
> **Do not use this configuration in production environments** unless proper firewall rules, network restrictions, and access controls are in place.  
>  
> These examples are intended **for local development and testing only**.

- SQLite3: `docker compose -f docker-compose.sqlite.yml up --build`
- PostgreSQL: `docker compose -f docker-compose.yml up --build`
- MySQL: `docker compose -f docker-compose.mysql.yml up --build`

The compose files publish container port `53` to host port `1053` by default to avoid conflicts with a local DNS service already using `53`.

Use standard DNS port `53` explicitly when needed:

```sh
PDNS_PORT_TCP=53 PDNS_PORT_UDP=53 docker compose -f docker-compose.yml up --build
```

<details>
<summary>PostgreSQL compose example</summary>

```yaml
services:
  pdns-db:
    image: postgres:18
    environment:
      POSTGRES_USER: powerdns
      POSTGRES_PASSWORD: powerdns
      POSTGRES_DB: powerdns
    ports:
      - "5432:5432"
    volumes:
      - pdns_db_data:/var/lib/postgresql

  pdns:
    build: .
    depends_on:
      - pdns-db
    environment:
      PDNS_launch: gpgsql
      PDNS_gpgsql_host: pdns-db
      PDNS_gpgsql_port: 5432
      PDNS_gpgsql_user: powerdns
      PDNS_gpgsql_password: powerdns
      PDNS_gpgsql_dbname: powerdns
    ports:
      - "${PDNS_PORT_TCP:-1053}:53/tcp"
      - "${PDNS_PORT_UDP:-1053}:53/udp"

volumes:
  pdns_db_data:
```

</details>

<details>
<summary>SQLite compose example</summary>

```yaml
services:
  pdns:
    build: .
    environment:
      PDNS_launch: gsqlite3
      PDNS_gsqlite3_database: /var/lib/powerdns/pdns.sqlite3
    ports:
      - "${PDNS_PORT_TCP:-1053}:53/tcp"
      - "${PDNS_PORT_UDP:-1053}:53/udp"
    volumes:
      - ./data:/var/lib/powerdns
```

</details>

<details>
<summary>MySQL compose example</summary>

```yaml
services:
  pdns-db:
    image: mysql:8.4
    environment:
      MYSQL_DATABASE: powerdns
      MYSQL_USER: powerdns
      MYSQL_PASSWORD: powerdns
      MYSQL_ROOT_PASSWORD: rootpassword
    ports:
      - "3306:3306"
    volumes:
      - pdns_mysql_data:/var/lib/mysql

  pdns:
    build: .
    depends_on:
      - pdns-db
    environment:
      PDNS_launch: gmysql
      PDNS_gmysql_host: pdns-db
      PDNS_gmysql_port: 3306
      PDNS_gmysql_user: powerdns
      PDNS_gmysql_password: powerdns
      PDNS_gmysql_dbname: powerdns
    ports:
      - "${PDNS_PORT_TCP:-1053}:53/tcp"
      - "${PDNS_PORT_UDP:-1053}:53/udp"

volumes:
  pdns_mysql_data:
```

</details>

## Security Considerations

- Do not expose database ports directly on public interfaces.
- Use private Docker networks where possible.
- Restrict access using firewalls or reverse proxies.
- Use strong credentials and secret management.

## Building

```sh
docker build -t pdns-authoritative .
```

For multi-arch builds:

```sh
docker buildx build --platform linux/amd64,linux/arm64 -t ghcr.io/alexanderslaa/powerdns-auth:latest --push .
```
