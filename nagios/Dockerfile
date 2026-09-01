FROM ubuntu:24.04

ARG NAGIOS_VERSION=4.5.14
ARG NAGIOS_PLUGINS_VERSION=2.5

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    NAGIOS_VERSION=${NAGIOS_VERSION} \
    NAGIOS_PLUGINS_VERSION=${NAGIOS_PLUGINS_VERSION}

COPY scripts/install_nagios.sh scripts/install_nagios_plugins.sh /usr/local/bin/

RUN chmod 0755 /usr/local/bin/install_nagios.sh /usr/local/bin/install_nagios_plugins.sh \
    && /usr/local/bin/install_nagios.sh \
    && /usr/local/bin/install_nagios_plugins.sh

# Monitoring configuration is baked into the image deliberately.
# Changing a *.cfg therefore requires a new image build/deployment.
COPY nagios/conf.d/ /usr/local/nagios/etc/conf.d/
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod 0755 /usr/local/bin/entrypoint.sh \
    && chown -R root:nagios /usr/local/nagios/etc/conf.d \
    && find /usr/local/nagios/etc/conf.d -type d -exec chmod 0755 {} \; \
    && find /usr/local/nagios/etc/conf.d -type f -name '*.cfg' -exec chmod 0644 {} \; \
    && /usr/local/nagios/bin/nagios -v /usr/local/nagios/etc/nagios.cfg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
