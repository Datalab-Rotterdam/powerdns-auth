FROM debian:trixie-slim

ARG SUBVARS_VERSION=0.1.5
ARG SUBVARS_SHA256_AMD64=2426c7ac07831bdf8d410ee9d6cea73db447b0314842dbb7c0c80a0a425af86c
ARG SUBVARS_SHA256_ARM64=80385062c52c45a7b5905adde7abb070c0b9d835638d2667a4142781e02f9250
ARG IMAGE_VERSION=dev
ARG IMAGE_REPOSITORY=https://github.com/Datalab-Rotterdam/powerdns-auth

# Install dependencies and tools
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ca-certificates \
        curl \
        default-mysql-client \
        postgresql-client \
        sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Install subvars with an explicit version and checksum verification
RUN set -e; \
    ARCH=$(dpkg --print-architecture); \
    case "$ARCH" in \
        amd64) \
            SUBVARS_ARCH="x86_64"; \
            SUBVARS_SHA256="${SUBVARS_SHA256_AMD64:-}"; \
            ;; \
        arm64) \
            SUBVARS_ARCH="arm64"; \
            SUBVARS_SHA256="${SUBVARS_SHA256_ARM64:-}"; \
            ;; \
        *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;; \
    esac; \
    [ -n "$SUBVARS_SHA256" ] || { echo "Missing subvars checksum for $ARCH" >&2; exit 1; }; \
    DOWNLOAD_URL="https://github.com/kha7iq/subvars/releases/download/v${SUBVARS_VERSION}/subvars_Linux_${SUBVARS_ARCH}.tar.gz"; \
    TMP_ARCHIVE="$(mktemp)"; \
    echo "Downloading subvars ${SUBVARS_VERSION} from: ${DOWNLOAD_URL}"; \
    curl -fsSL "$DOWNLOAD_URL" -o "$TMP_ARCHIVE"; \
    echo "${SUBVARS_SHA256}  ${TMP_ARCHIVE}" | sha256sum -c -; \
    tar -xzf "$TMP_ARCHIVE" -C /usr/local/bin; \
    rm -f "$TMP_ARCHIVE"; \
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
    PDNS_setgid=pdns \
    IMAGE_VERSION=${IMAGE_VERSION} \
    IMAGE_REPOSITORY=${IMAGE_REPOSITORY}

EXPOSE 53 53/udp

HEALTHCHECK --interval=10s --timeout=10s --retries=3 --start-period=2s \
    CMD pdns_control ping

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["/usr/sbin/pdns_server"]
