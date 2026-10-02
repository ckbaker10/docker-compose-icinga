#!/usr/bin/env bash

set -e
set -o pipefail

if [ ! -f /data/etc/icinga2/conf.d/icingaweb-api-user.conf ]; then
  # Escape backslashes and double quotes for the Icinga 2 string literal, then
  # escape the result for use as a sed replacement.
  password=${ICINGAWEB_ICINGA2_API_USER_PASSWORD:-icingaweb}
  password=${password//\\/\\\\}
  password=${password//\"/\\\"}
  replacement=$(printf '%s' "$password" | sed -e 's/[\/&\\]/\\&/g')
  sed "s/\$ICINGAWEB_ICINGA2_API_USER_PASSWORD/${replacement}/" /config/icingaweb-api-user.conf >/data/etc/icinga2/conf.d/icingaweb-api-user.conf
fi

if [ ! -f /data/etc/icinga2/features-enabled/icingadb.conf ]; then
  mkdir -p /data/etc/icinga2/features-enabled
  cat /config/icingadb.conf >/data/etc/icinga2/features-enabled/icingadb.conf
fi
