FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND noninteractive
ENV SLAPD_TLS_CA /etc/ldap/tls/ca.pem
ENV SLAPD_TLS_CRT /etc/ldap/tls/cert.pem
ENV SLAPD_TLS_KEY /etc/ldap/tls/cert.key
ENV SLAPD_ADDITIONAL_SCHEMAS ppolicy,dyngroup,sudo
ENV SLAPD_ADDITIONAL_MODULES memberof,refint,ppolicy
ENV SLAPD_ADDITIONAL_CONFIG sudo,posix
ENV SLAPD_LOGLEVEL 32768

MAINTAINER Nikita Tarasov <nikita@mygento.ru>

RUN echo 'deb http://deb.debian.org/debian bullseye-backports main' > /etc/apt/sources.list.d/backports.list

RUN apt-get -qqy update && \
    DEBIAN_FRONTEND=noninteractive apt-get -qqy install -t bullseye-backports slapd ldap-utils && \
    DEBIAN_FRONTEND=noninteractive apt-get -qqy install openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mv /etc/ldap /etc/ldap.dist

COPY modules/ /etc/ldap.dist/modules
COPY config/ /etc/ldap.dist/config
ADD https://raw.githubusercontent.com/sudo-project/sudo/main/doc/schema.olcSudo /etc/ldap.dist/schema/sudo.ldif

COPY entrypoint.sh /entrypoint.sh


VOLUME ["/etc/ldap", "/var/lib/ldap"]
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 389

# CMD ["slapd", "-d", "32768", "-u", "openldap", "-g", "openldap"]
CMD ["sh", "-c", "slapd -d $SLAPD_LOGLEVEL -u openldap -g openldap"]
