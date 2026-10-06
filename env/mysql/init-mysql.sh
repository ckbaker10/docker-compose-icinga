#!/bin/sh
# Creates the databases and users for the Icinga stack on first start of the
# MariaDB container. Runs only when the data volume is empty.

set -eu

create_database_and_user() {
    DB=$1
    USER=$2
    # Escape backslashes and single quotes for the SQL string literal.
    PASSWORD=$(printf '%s' "$3" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")

    mariadb --user=root --password="$MYSQL_ROOT_PASSWORD" <<EOS
CREATE DATABASE IF NOT EXISTS \`${DB}\`;
CREATE USER IF NOT EXISTS '${USER}'@'%' IDENTIFIED BY '${PASSWORD}';
GRANT ALL ON \`${DB}\`.* TO '${USER}'@'%';
EOS
    echo "init-mysql: database '${DB}' and user '${USER}' ready"
}

create_database_and_user director director "$ICINGA_DIRECTOR_MYSQL_PASSWORD"
create_database_and_user icingadb icingadb "$ICINGADB_MYSQL_PASSWORD"
create_database_and_user icingaweb icingaweb "$ICINGAWEB_MYSQL_PASSWORD"
