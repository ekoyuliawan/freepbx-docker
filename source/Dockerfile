FROM debian:bookworm-slim AS asterisk-builder

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /usr/src

# Versions and checksums (override with --build-arg for reproducible builds)
ARG ASTERISK_VERSION=21.10.2
ARG ASTERISK_SHA256=

# Build-time dependencies for compiling Asterisk only
RUN apt-get update && apt-get -y --no-install-recommends install \
  build-essential pkg-config bison flex libnewt-dev libssl-dev libncurses5-dev \
  subversion libsqlite3-dev libjansson-dev libxml2-dev uuid uuid-dev \
  libsrtp2-dev libspandsp-dev libasound2-dev libogg-dev libvorbis-dev \
  sox autoconf automake libtool libtool-bin unixodbc-dev libedit-dev \
  curl wget ca-certificates tar xz-utils \
  lame ffmpeg mpg123 expect \
  && rm -rf /var/lib/apt/lists/*

# Download and build Asterisk (no sources kept in final image)
RUN set -eux && \
  AST_URL="https://downloads.asterisk.org/pub/telephony/asterisk/asterisk-${ASTERISK_VERSION}.tar.gz" && \
  curl -fsSL "$AST_URL" -o asterisk.tar.gz && \
  [ -z "$ASTERISK_SHA256" ] || echo "$ASTERISK_SHA256  asterisk.tar.gz" | sha256sum -c - && \
  tar -xzf asterisk.tar.gz && \
  cd "asterisk-${ASTERISK_VERSION}" && \
  contrib/scripts/get_mp3_source.sh && \
  ./configure --with-astmoddir=/usr/lib/asterisk/modules --with-pjproject-bundled --with-jansson-bundled && \
  make menuselect.makeopts && \
  menuselect/menuselect --disable BUILD_NATIVE --enable format_mp3 menuselect.makeopts && \
  make -j"$(nproc)" && \
  make install && \
  ldconfig && \
  mkdir -p /opt/ast-dist/usr/sbin /opt/ast-dist/usr/lib /opt/ast-dist/usr/lib/asterisk \
           /opt/ast-dist/etc /opt/ast-dist/var/lib /opt/ast-dist/var/log /opt/ast-dist/var/spool && \
  cp -a /usr/sbin/asterisk /usr/sbin/safe_asterisk /opt/ast-dist/usr/sbin/ && \
  cp -a /usr/lib/asterisk /opt/ast-dist/usr/lib/ && \
  if [ -d /etc/asterisk ]; then cp -a /etc/asterisk /opt/ast-dist/etc/; fi && \
  if [ -d /var/lib/asterisk ]; then cp -a /var/lib/asterisk /opt/ast-dist/var/lib/; fi && \
  if [ -d /var/spool/asterisk ]; then cp -a /var/spool/asterisk /opt/ast-dist/var/spool/; fi && \
  if [ -d /var/log/asterisk ]; then cp -a /var/log/asterisk /opt/ast-dist/var/log/; fi && \
  for d in /usr/lib /usr/local/lib /usr/lib/x86_64-linux-gnu /usr/lib64; do \
    [ -d "$d" ] || continue; \
    find "$d" -maxdepth 1 -type f \
      \( -name 'libasterisk*.so*' -o -name 'libpj*.so*' -o -name 'libjansson*.so*' \) \
      -exec cp --parents -a {} /opt/ast-dist \; ; \
  done


# Final runtime image
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

# Runtime dependencies only (no build tools), and cleanup for smaller image
RUN apt-get update && apt-get -y --no-install-recommends install \
  cron curl wget ca-certificates libicu-dev libical-dev libneon27-dev \
  apache2 mariadb-client php8.2 php8.2-curl php8.2-cli \
  php8.2-common php8.2-mysql php8.2-gd php8.2-mbstring php8.2-intl php8.2-xml php-pear php-soap \
  sox sqlite3 unixodbc odbc-mariadb \
  nodejs npm fail2ban \
  libasound2 libogg0 libvorbis0a libvorbisenc2 libsrtp2-1 libspandsp2 libxml2 libsqlite3-0 libssl3 libedit2 \
  ipset iptables \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Bring in compiled Asterisk from the builder stage (binaries, modules, libs, configs)
COPY --from=asterisk-builder /opt/ast-dist/ /

# Create asterisk user and set permissions
RUN groupadd asterisk \
  && useradd -r -d /var/lib/asterisk -g asterisk asterisk \
  && usermod -aG audio,dialout asterisk \
  && chown -R asterisk:asterisk /etc/asterisk \
  && chown -R asterisk:asterisk /var/lib/asterisk /var/log/asterisk /var/spool/asterisk \
  && chown -R asterisk:asterisk /usr/lib/asterisk \
  && sed -i 's|#AST_USER|AST_USER|' /etc/default/asterisk || true \
  && sed -i 's|#AST_GROUP|AST_GROUP|' /etc/default/asterisk || true \
  && sed -i 's|;runuser|runuser|' /etc/asterisk/asterisk.conf || true \
  && sed -i 's|;rungroup|rungroup|' /etc/asterisk/asterisk.conf || true \
  && ldconfig

# Apache/PHP tuning
RUN sed -i 's/\(^upload_max_filesize = \).*/\120M/' /etc/php/8.2/apache2/php.ini \
  && sed -i 's/\(^memory_limit = \).*/\1256M/' /etc/php/8.2/apache2/php.ini \
  && sed -i 's/^\(User\|Group\).*/\1 asterisk/' /etc/apache2/apache2.conf \
  && sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf \
  && a2enmod rewrite \
  && apache2ctl -t \
  && echo "ServerName localhost" >> /etc/apache2/apache2.conf \
  && rm -f /var/www/html/index.html

# ODBC configs
COPY odbc/odbcinst.ini /etc/odbcinst.ini
COPY odbc/odbc.ini /etc/odbc.ini

WORKDIR /usr/local/src

# Download FreePBX sources at build time; verify optionally with SHA and remove tarball
ARG FREEPBX_TGZ=https://mirror.freepbx.org/modules/packages/freepbx/freepbx-17.0-latest-EDGE.tgz
ARG FREEPBX_SHA256=

RUN mkdir -p /usr/local/src/freepbx && \
  curl -fsSL "$FREEPBX_TGZ" -o /tmp/freepbx.tgz && \
  [ -z "$FREEPBX_SHA256" ] || echo "$FREEPBX_SHA256  /tmp/freepbx.tgz" | sha256sum -c - && \
  tar -xzf /tmp/freepbx.tgz -C /usr/local/src/freepbx --strip-components=1 && \
  rm -f /tmp/freepbx.tgz

COPY entrypoint.sh entrypoint.sh

CMD ["/usr/bin/env", "bash", "/usr/local/src/entrypoint.sh"]
