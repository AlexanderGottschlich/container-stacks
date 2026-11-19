# syntax=docker/dockerfile:1

ARG UBUNTU_IMAGE=ubuntu:24.04

# ------------------------------------------------------------
# Stage 1: compile Nagios Core and Nagios Plugins
# ------------------------------------------------------------
FROM ${UBUNTU_IMAGE} AS builder

ARG NAGIOS_VERSION=4.5.14
ARG NAGIOS_PLUGINS_VERSION=2.5

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    NAGIOS_VERSION=${NAGIOS_VERSION} \
    NAGIOS_PLUGINS_VERSION=${NAGIOS_PLUGINS_VERSION}

# The original install scripts are intentionally reused, unchanged.
# This step contains the expensive APT setup + source compilation and
# is independent of runtime monitoring configuration and web assets.
COPY scripts/install_nagios.sh scripts/install_nagios_plugins.sh /usr/local/bin/
RUN chmod 0755 /usr/local/bin/install_nagios.sh /usr/local/bin/install_nagios_plugins.sh \
    && /usr/local/bin/install_nagios.sh \
    && /usr/local/bin/install_nagios_plugins.sh \
    && getent passwd nagios | cut -d: -f3 > /tmp/nagios-uid \
    && getent group nagios | cut -d: -f3 > /tmp/nagios-gid

# ------------------------------------------------------------
# Stage 2: minimal application runtime (without build toolchain)
# ------------------------------------------------------------
FROM ${UBUNTU_IMAGE} AS runtime

ARG NAGIOS_VERSION=4.5.14
ARG NAGIOS_PLUGINS_VERSION=2.5

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    NAGIOS_VERSION=${NAGIOS_VERSION} \
    NAGIOS_PLUGINS_VERSION=${NAGIOS_PLUGINS_VERSION}

# Only runtime packages. No gcc/make/autoconf/automake/build-essential.
# Includes DNS tools and iproute2 needed by existing checks and routing.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       apache2 \
       apache2-utils \
       ca-certificates \
       dnsutils \
       iproute2 \
       iputils-ping \
       libapache2-mod-php \
       libcurl4t64 \
       libgd3 \
       libssl3t64 \
       perl \
       bc \
       php \
    && rm -rf /var/lib/apt/lists/*

# Preserve the numeric Nagios user/group IDs from the build stage.
# This is important because /usr/local/nagios/var is a persistent volume.
COPY --from=builder /tmp/nagios-uid /tmp/nagios-uid
COPY --from=builder /tmp/nagios-gid /tmp/nagios-gid
RUN groupadd --system --gid "$(cat /tmp/nagios-gid)" nagios \
    && useradd --system --uid "$(cat /tmp/nagios-uid)" --gid nagios \
         --home-dir /usr/local/nagios --shell /usr/sbin/nologin nagios \
    && usermod -a -G nagios www-data \
    && rm -f /tmp/nagios-uid /tmp/nagios-gid

# Core, plugins, web assets, configuration, ownership, and executable bits.
COPY --from=builder /usr/local/nagios/ /usr/local/nagios/

# install-webconf generated the Nagios Apache site in the builder stage.
COPY --from=builder /etc/apache2/sites-enabled/nagios.conf /etc/apache2/sites-enabled/nagios.conf

RUN a2enmod cgi \
    && sed -i 's#AuthUserFile .*htpasswd.users#AuthUserFile /run/nagios/htpasswd.users#g' \
         /etc/apache2/sites-enabled/nagios.conf \
    && printf '\nServerName localhost\n' >> /etc/apache2/apache2.conf

# The following files change frequently; keep them AFTER compilation.
COPY nagios/conf.d/ /usr/local/nagios/etc/conf.d/
COPY nagios/web/upzilla.css nagios/web/upzilla.js /tmp/nagios-web/
COPY scripts/entrypoint.sh scripts/configure_egress_route.sh /usr/local/bin/

RUN cat /tmp/nagios-web/upzilla.css >> /usr/local/nagios/share/stylesheets/common.css \
    && cat /tmp/nagios-web/upzilla.js >> /usr/local/nagios/share/js/nag_funcs.js \
    && rm -rf /tmp/nagios-web \
    && chmod 0755 /usr/local/bin/entrypoint.sh /usr/local/bin/configure_egress_route.sh \
    && chown -R root:nagios /usr/local/nagios/etc/conf.d \
    && find /usr/local/nagios/etc/conf.d -type d -exec chmod 0755 {} \; \
    && find /usr/local/nagios/etc/conf.d -type f -name '*.cfg' -exec chmod 0644 {} \; \
    && test -x /usr/local/nagios/libexec/check_http \
    && test -x /usr/local/nagios/libexec/check_dns \
    && test -x /usr/local/nagios/libexec/check_dig \
    && /usr/local/nagios/libexec/check_http --version >/dev/null \
    && /usr/local/nagios/libexec/check_dns --version >/dev/null \
    && /usr/local/nagios/libexec/check_dig --version >/dev/null \
    && /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg \
    && apache2ctl -t \
    && rm -rf /tmp/* /var/tmp/*

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
