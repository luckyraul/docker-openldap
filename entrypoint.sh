#!/bin/bash
ulimit -n 8192
set -e

SLAPD_FORCE_RECONFIGURE="${SLAPD_FORCE_RECONFIGURE:-false}"

first_run=true

if [[ -f "/var/lib/ldap/DB_CONFIG" ]]; then
    first_run=false
fi

if [[ ! -d /etc/ldap/slapd.d || "$SLAPD_FORCE_RECONFIGURE" == "true" ]]; then

    if [[ -z "$SLAPD_PASSWORD" ]]; then
        echo -n >&2 "Error: Container not configured and SLAPD_PASSWORD not set. "
        echo >&2 "Did you forget to add -e SLAPD_PASSWORD=... ?"
        exit 1
    fi

    if [[ -z "$SLAPD_DOMAIN" ]]; then
        echo -n >&2 "Error: Container not configured and SLAPD_DOMAIN not set. "
        echo >&2 "Did you forget to add -e SLAPD_DOMAIN=... ?"
        exit 1
    fi

    SLAPD_ORGANIZATION="${SLAPD_ORGANIZATION:-${SLAPD_DOMAIN}}"

    cp -r /etc/ldap.dist/* /etc/ldap

    cat <<-EOF | debconf-set-selections
        slapd slapd/no_configuration boolean false
        slapd slapd/password1 password $SLAPD_PASSWORD
        slapd slapd/password2 password $SLAPD_PASSWORD
        slapd shared/organization string $SLAPD_ORGANIZATION
        slapd slapd/domain string $SLAPD_DOMAIN
        slapd slapd/backend select MDB
        slapd slapd/allow_ldap_v2 boolean false
        slapd slapd/purge_database boolean false
        slapd slapd/move_old_database boolean true
EOF

    dpkg-reconfigure -f noninteractive slapd >/dev/null 2>&1

    dc_string=""

    IFS="."; declare -a dc_parts=($SLAPD_DOMAIN); unset IFS

    for dc_part in "${dc_parts[@]}"; do
        dc_string="$dc_string,dc=$dc_part"
    done

    base_dc="${dc_string:1}"
    base_string="BASE ${base_dc}"

    sed -i "s/^#BASE.*/${base_string}/g" /etc/ldap/ldap.conf

    if [[ -n "$SLAPD_CONFIG_PASSWORD" ]]; then
        password_hash=`slappasswd -s "${SLAPD_CONFIG_PASSWORD}"`

        sed_safe_password_hash=${password_hash//\//\\\/}

        slapcat -n0 -F /etc/ldap/slapd.d -l /tmp/config.ldif
        sed -i "s/\(olcRootDN: cn=admin,cn=config\)/\1\nolcRootPW: ${sed_safe_password_hash}/g" /tmp/config.ldif
        rm -rf /etc/ldap/slapd.d/*
        slapadd -n0 -F /etc/ldap/slapd.d -l /tmp/config.ldif
        rm /tmp/config.ldif
    fi

    if [[ -n "$SLAPD_ADDITIONAL_SCHEMAS" ]]; then
        IFS=","; declare -a schemas=($SLAPD_ADDITIONAL_SCHEMAS); unset IFS

        for schema in "${schemas[@]}"; do
            echo "Applying ${schema} schema..."
            slapadd -n0 -F /etc/ldap/slapd.d -l "/etc/ldap/schema/${schema}.ldif"
        done
    fi

    if [[ -n "$SLAPD_ADDITIONAL_MODULES" ]]; then
        IFS=","; declare -a modules=($SLAPD_ADDITIONAL_MODULES); unset IFS

        for module in "${modules[@]}"; do
            echo "Applying ${module} module..."
            module_file="/etc/ldap/modules/${module}.ldif"
            slapadd -n0 -F /etc/ldap/slapd.d -l "$module_file"
        done
    fi

    # create dir if they not already exists
    [ -d /etc/ldap/tls ] || mkdir -p /etc/ldap/tls

    chown -R openldap:openldap /etc/ldap/tls/ /etc/ldap/slapd.d/ /var/lib/ldap/ /var/run/slapd/

    # start OpenLDAP
    echo "Start OpenLDAP bootstrap process..."
    slapd -h "ldap://localhost ldapi:///" -u openldap -g openldap -d 32768 2>&1 &

    echo "Waiting for OpenLDAP to start..."
    while [ ! -e /run/slapd/slapd.pid ]; do sleep 0.1; done

    if [[ -n "$SLAPD_ADDITIONAL_CONFIG" ]]; then
      IFS=","; declare -a modules=($SLAPD_ADDITIONAL_CONFIG); unset IFS

      for module in "${modules[@]}"; do
          echo "Applying ${module} config..."
          ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f /etc/ldap/config/${module}.ldif
      done
    fi

    if [[ -n "$SLAPD_ANONYM" ]]; then
      echo "Disabling Anonymous..."
      ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f /etc/ldap/config/anonymous.ldif
    fi

    if [[ -n "$SLAPD_TLS" ]]; then

        # gen dhparm
        mkdir -p /etc/ldap/tls
        [ -f /etc/ldap/tls/dhparam.pem ] || openssl dhparam -out /etc/ldap/tls/dhparam.pem 2048
        chmod 600 /etc/ldap/tls/dhparam.pem

        chown -R openldap:openldap /etc/ldap/tls

        sed -i "s|{{ SLAPD_TLS_CA }}|${SLAPD_TLS_CA}|g" /etc/ldap/config/tls.ldif
        sed -i "s|{{ SLAPD_TLS_CRT }}|${SLAPD_TLS_CRT}|g" /etc/ldap/config/tls.ldif
        sed -i "s|{{ SLAPD_TLS_KEY }}|${SLAPD_TLS_KEY}|g" /etc/ldap/config/tls.ldif

        echo "Applying TLS..."
        ldapmodify -Y EXTERNAL -Q -H ldapi:/// -f /etc/ldap/config/tls.ldif
    fi

    # stop OpenLDAP
    echo "Stop OpenLDAP..."

    SLAPD_PID=$(cat /run/slapd/slapd.pid)
    kill -15 $SLAPD_PID

    # wait until slapd is terminated
    while [ -e /proc/$SLAPD_PID ]; do sleep 0.1; done

else
    slapd_configs_in_env=`env | grep 'SLAPD_'`

    if [ -n "${slapd_configs_in_env:+x}" ]; then
        echo "Info: Container already configured, therefore ignoring SLAPD_xxx environment variables and preseed files"
    fi
fi

if [[ "$first_run" == "true" ]]; then
    if [[ -d "/etc/ldap/prepopulate" ]]; then
        for file in `ls /etc/ldap/prepopulate/*.ldif`; do
            slapadd -F /etc/ldap/slapd.d -l "$file"
        done
    fi
fi

chown -R openldap:openldap /etc/ldap/tls/ /etc/ldap/slapd.d/ /var/lib/ldap/ /var/run/slapd/

exec "$@"
