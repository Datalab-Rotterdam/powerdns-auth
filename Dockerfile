FROM debian:trixie-slim

# Install dependencies and tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        default-mysql-client \
        postgresql-client \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install subvars (latest release)
RUN set -e; \
    LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/kha7iq/subvars/releases/latest | \
                    grep '"tag_name"' | cut -d'"' -f4 | sed 's/^v//'); \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in \
        amd64)   SUBVARS_ARCH="x86_64" ;; \
        arm64)   SUBVARS_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac; \
    DOWNLOAD_URL="https://github.com/kha7iq/subvars/releases/download/v${LATEST_VERSION}/subvars_Linux_${SUBVARS_ARCH}.tar.gz"; \
    echo "Downloading subvars from: ${DOWNLOAD_URL}"; \
    curl -fsSL "${DOWNLOAD_URL}" | tar -xz -C /usr/local/bin; \
    chmod +x /usr/local/bin/subvars

# Add PowerDNS APT repository
RUN install -d /etc/apt/keyrings && \
    curl -fsSL https://repo.powerdns.com/FD380FBB-pub.asc -o /etc/apt/keyrings/auth-50-pub.asc && \
    CODENAME=$(grep -o 'VERSION_CODENAME=.*' /etc/os-release | cut -d= -f2) && \
    ARCH=$(dpkg --print-architecture) && \
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/auth-50-pub.asc] https://repo.powerdns.com/debian ${CODENAME}-auth-50 main" \
        > /etc/apt/sources.list.d/pdns.list && \
    echo 'Package: pdns-*\nPin: origin repo.powerdns.com\nPin-Priority: 600' \
        > /etc/apt/preferences.d/auth-50

# Install PowerDNS with all backends
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        pdns-server \
        pdns-backend-pgsql \
        pdns-backend-sqlite3 \
        pdns-backend-tinydns \
        pdns-backend-pipe \
        pdns-backend-remote \
        pdns-backend-mysql \
        pdns-backend-odbc \
        pdns-backend-lua2 \
        pdns-backend-lmdb \
        pdns-backend-ldap \
        pdns-backend-geoip \
        pdns-backend-bind \
    && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Runtime directories and permissions
RUN mkdir -p /run/pdns /var/lib/powerdns && \
    chown -R pdns:pdns /etc/powerdns /run/pdns /var/lib/powerdns

# Copy assets
COPY pdns.conf.tpl /pdns.conf.tpl
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Switch to non-root user
USER pdns

# Environment defaults
ENV PDNS_launch=gsqlite3 \
    PDNS_gsqlite3_database=/var/lib/powerdns/pdns.sqlite3 \
    PDNS_guardian=yes \
    PDNS_setuid=pdns \
    PDNS_setgid=pdns

EXPOSE 53 53/udp

HEALTHCHECK --interval=10s --timeout=10s --retries=3 --start-period=2s \
    CMD pdns_control ping

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/sbin/pdns_server"]
