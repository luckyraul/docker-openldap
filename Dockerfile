FROM debian:buster-slim

ENV DEBIAN_FRONTEND noninteractive
ENV SLAPD_TLS_CA=/etc/ldap/tls/ca.pem
ENV SLAPD_TLS_CRT=/etc/ldap/tls/cert.pem
ENV SLAPD_TLS_KEY=/etc/ldap/tls/cert.key

MAINTAINER Nikita Tarasov <nikita@mygento.ru>

RUN echo 'deb http://deb.debian.org/debian buster-backports main' > /etc/apt/sources.list.d/backports.list

RUN apt-get -qqy update && \
    DEBIAN_FRONTEND=noninteractive apt-get -qqy install -t buster-backports slapd ldap-utils && \
    DEBIAN_FRONTEND=noninteractive apt-get -qqy install openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mv /etc/ldap /etc/ldap.dist

COPY config/ /etc/ldap.dist/config
ADD https://raw.githubusercontent.com/sudo-project/sudo/main/doc/schema.olcSudo /etc/ldap.dist/schema/sudo.ldif

COPY entrypoint.sh /entrypoint.sh


VOLUME ["/etc/ldap", "/var/lib/ldap"]
ENTRYPOINT ["/entrypoint.sh"]
EXPOSE 389

CMD ["slapd", "-d", "32768", "-u", "openldap", "-g", "openldap"]
