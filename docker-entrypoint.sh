#!/bin/sh
set -eu

: "${DEBUG:=0}"
if [ "$DEBUG" -eq 1 ]; then
    set -x
fi

: "${IMAGE_VERSION:=dev}"
: "${IMAGE_REPOSITORY:=https://github.com/Datalab-Rotterdam/powerdns-auth}"
: "${PDNS_DB_INIT:=true}"
: "${PDNS_DB_CREATE:=false}"

SUPPORTED_BACKENDS="bind gmysql godbc gpgsql gsqlite3 geoip ldap lmdb lua2 pipe random remote tinydns"

print_banner() {
    cat <<EOF
============================================================
 PowerDNS Authoritative Server Docker Image
 Version    : ${IMAGE_VERSION}
 Repository : ${IMAGE_REPOSITORY}
 Maintainer : Datalab Rotterdam
============================================================
EOF
}

backend_enabled() {
    case ",$(echo "$PDNS_launch" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ',')," in
        *",$1,"*) return 0 ;;
        *) return 1 ;;
    esac
}

validate_backends() {
    list=$(echo "$PDNS_launch" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]*,[[:space:]]*/,/g;s/^,*//;s/,*$//')
    [ -n "$list" ] || { echo "ERROR: PDNS_launch is empty or unset" >&2; exit 1; }

    IFS=','
    set -- $list
    unset IFS

    for be; do
        [ -z "$be" ] && continue
        case " $SUPPORTED_BACKENDS " in
            *" $be "*) ;;
            *)
                echo "ERROR: Unsupported backend: '$be'" >&2
                echo "Supported: $SUPPORTED_BACKENDS" >&2
                exit 1
                ;;
        esac
    done
}

ensure_writable_dir() {
    dir="$1"
    if [ -d "$dir" ]; then
        return
    fi

    if ! mkdir -p "$dir"; then
        echo "ERROR: Could not create directory: $dir" >&2
        echo "Ensure the path exists and is writable by the pdns user." >&2
        exit 1
    fi
}

mysql_client_ssl_args() {
    case "${PDNS_gmysql_ssl_mode:-}" in
        DISABLED|disabled|OFF|off|NO|no|FALSE|false|0)
            printf '%s\n' "--skip-ssl"
            ;;
    esac
}

validate_backends
print_banner

prune_backend_env() {
    while IFS='=' read -r name _; do
        case "$name" in
            PDNS_bind_*)
                backend_enabled "bind" || unset "$name"
                ;;
            PDNS_geoip_*)
                backend_enabled "geoip" || unset "$name"
                ;;
            PDNS_gmysql_*)
                backend_enabled "gmysql" || unset "$name"
                ;;
            PDNS_godbc_*)
                backend_enabled "godbc" || unset "$name"
                ;;
            PDNS_gpgsql_*)
                backend_enabled "gpgsql" || unset "$name"
                ;;
            PDNS_gsqlite3_*)
                backend_enabled "gsqlite3" || unset "$name"
                ;;
            PDNS_ldap_*)
                backend_enabled "ldap" || unset "$name"
                ;;
            PDNS_lmdb_*)
                backend_enabled "lmdb" || unset "$name"
                ;;
            PDNS_lua2_*)
                backend_enabled "lua2" || unset "$name"
                ;;
            PDNS_pipe_*)
                backend_enabled "pipe" || unset "$name"
                ;;
            PDNS_remote_*)
                backend_enabled "remote" || unset "$name"
                ;;
            PDNS_tinydns_*)
                backend_enabled "tinydns" || unset "$name"
                ;;
        esac
    done <<EOF
$(env)
EOF
}

prune_backend_env

if backend_enabled "gpgsql"; then
    echo "-> PostgreSQL (gpgsql) backend enabled."
    if [ "${SKIP_DB_INIT:-false}" = "true" ] || [ "$PDNS_DB_INIT" != "true" ]; then
        echo "  Skipping PostgreSQL initialization."
    else
        echo "  Waiting for PostgreSQL at ${PDNS_gpgsql_host}:${PDNS_gpgsql_port}..."
        until pg_isready -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d "$PDNS_gpgsql_dbname" >/dev/null 2>&1; do
            sleep 2
        done

        export PGPASSWORD="$PDNS_gpgsql_password"

        if [ "${SKIP_DB_CREATE:-false}" = "true" ] || [ "$PDNS_DB_CREATE" != "true" ]; then
            echo "  Skipping PostgreSQL database creation."
        else
            if ! psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '${PDNS_gpgsql_dbname}'" | grep -q '^1$'; then
                echo "  Creating database: ${PDNS_gpgsql_dbname}"
                psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d postgres -c "CREATE DATABASE ${PDNS_gpgsql_dbname};"
            else
                echo "  Database already exists."
            fi
        fi

        if psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d "$PDNS_gpgsql_dbname" -c "SELECT 1 FROM domains LIMIT 1;" >/dev/null 2>&1; then
            echo "  PostgreSQL schema already present. Skipping init."
        else
            echo "  Initializing PostgreSQL schema..."
            psql -h "$PDNS_gpgsql_host" -p "$PDNS_gpgsql_port" -U "$PDNS_gpgsql_user" -d "$PDNS_gpgsql_dbname" < /usr/share/doc/pdns-backend-pgsql/schema.pgsql.sql
        fi

        unset PGPASSWORD
    fi
fi

if backend_enabled "gmysql"; then
    echo "-> MySQL (gmysql) backend enabled."
    if [ "${SKIP_DB_INIT:-false}" = "true" ] || [ "$PDNS_DB_INIT" != "true" ]; then
        echo "  Skipping MySQL initialization."
    else
        MYSQL_SSL_ARGS="$(mysql_client_ssl_args)"
        echo "  Waiting for MySQL at ${PDNS_gmysql_host}:${PDNS_gmysql_port}..."
        until mysqladmin $MYSQL_SSL_ARGS -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" ping >/dev/null 2>&1; do
            sleep 2
        done

        if [ "${SKIP_DB_CREATE:-false}" = "true" ] || [ "$PDNS_DB_CREATE" != "true" ]; then
            echo "  Skipping MySQL database creation."
        else
            mysql $MYSQL_SSL_ARGS -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" \
                -e "CREATE DATABASE IF NOT EXISTS \`${PDNS_gmysql_dbname}\`;"
        fi

        if mysql $MYSQL_SSL_ARGS -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" \
            -D "$PDNS_gmysql_dbname" -e "SELECT 1 FROM domains LIMIT 1;" >/dev/null 2>&1; then
            echo "  MySQL schema already present. Skipping init."
        else
            echo "  Initializing MySQL schema..."
            mysql $MYSQL_SSL_ARGS -h "$PDNS_gmysql_host" -P "$PDNS_gmysql_port" -u "$PDNS_gmysql_user" --password="$PDNS_gmysql_password" \
                "$PDNS_gmysql_dbname" < /usr/share/doc/pdns-backend-mysql/schema.mysql.sql
        fi
    fi
fi

if backend_enabled "gsqlite3"; then
    DB_PATH="${PDNS_gsqlite3_database:-/var/lib/powerdns/pdns.sqlite3}"
    echo "-> SQLite3 (gsqlite3) backend enabled. DB: $DB_PATH"

    if [ "${SKIP_DB_INIT:-false}" = "true" ] || [ "$PDNS_DB_INIT" != "true" ]; then
        echo "  Skipping SQLite3 initialization."
    else
        DIR="$(dirname "$DB_PATH")"
        ensure_writable_dir "$DIR"

        if [ -f "$DB_PATH" ] && sqlite3 "$DB_PATH" "SELECT 1 FROM domains LIMIT 1;" >/dev/null 2>&1; then
            echo "  SQLite3 schema already present."
        else
            echo "  Initializing SQLite3 schema..."
            sqlite3 "$DB_PATH" ".read /usr/share/doc/pdns-backend-sqlite3/schema.sqlite3.sql"
            if [ -f "$DB_PATH" ]; then
                chmod 600 "$DB_PATH" 2>/dev/null || true
            fi
        fi
    fi
fi

for be in bind geoip ldap lmdb lua2 pipe random remote tinydns; do
    if backend_enabled "$be"; then
        echo "-> Non-initializing backend enabled: $be"
    fi
done

echo "-> Generating /etc/powerdns/pdns.conf from template..."
subvars --prefix 'PDNS_' < /pdns.conf.tpl > /etc/powerdns/pdns.conf

echo "-> Starting PowerDNS..."
exec "$@"
