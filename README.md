# docker-compose Icinga stack

docker-compose configuration to start-up an Icinga stack containing
Icinga 2, Icinga Web 2 and Icinga DB.

Ensure you have the latest Docker and docker-compose versions and
then just run `docker-compose -p icinga-playground up` in order to start the Icinga stack.

Icinga Web is provided on port **8080** and you can access the Icinga 2 API on port **5665**.
The default user of Icinga Web is `icingaadmin` with password `icinga` and
the default user of the Icinga 2 API for Web is `icingaweb` with password `icingaweb`.

## Upgrading from v1.1.0 to v1.2.0

**v1.2.0** deploys Icinga Web ≥ 2.11.0, Icinga 2 ≥ 2.13.4, Icinga DB ≥ 1.0.0 and Icinga DB Web ≥ 1.0.0.
The Icinga Director is also set up and its daemon started, all in a separate container.

The easiest way to upgrade is to start over, removing all the volumes and
therefore wiping out any configurations you have changed:

`docker-compose -p icinga-playground down --volumes && docker-compose pull && docker-compose -p icinga-playground up --build -d`


## Upgrading from v1.0.0 to v1.1.0

**v1.1.0** deploys Icinga Web 2.9.0 and snapshots of Icinga 2, Icinga DB and Icinga DB Web.

The easiest way to upgrade is to start over, removing all the volumes and
therefore wiping out any configurations you have changed:

`docker-compose down --volumes && docker-compose build --pull && docker-compose -p icinga-playground up -d`

## Backup your settings

`bash backup.sh`

```
Stopping Docker Compose services for a consistent backup...
[+] Stopping 7/7
Container icinga-playground-icingadb-1        Stopped                                                                                     0.7s
Container icinga-playground-director-1        Stopped                                                                                     1.1s
Container icinga-playground-icingaweb-1       Stopped                                                                                     2.1s
Container icinga-playground-icinga2-1         Stopped                                                                                     0.8s
Container icinga-playground-init-icinga2-1    Stopped                                                                                     0.0s
Container icinga-playground-icingadb-redis-1  Stopped                                                                                     0.5s
Container icinga-playground-mysql-1           Stopped                                                                                     1.2s
Starting backup of volumes: icinga-playground_icinga2, icinga-playground_icingaweb, icinga-playground_mysql
Creating tar archive...
./
./mysql/
./mysql/multi-master.info
./mysql/performance_schema/
./mysql/performance_schema/db.opt
./mysql/aria_log_control
./mysql/mysql/
./mysql/director/
./mysql/icingaweb/
./mysql/sys/
./icinga2/
./icinga2/etc/
./icinga2/etc/icinga2/
./icinga2/var/log/
./icinga2/var/lib/
./icingaweb/
./icingaweb/etc/
./icingaweb/var/
./icingaweb/var/lib/
./icingaweb/var/lib/icingaweb2/
Backup successful! Archive saved to: /opt/icinga-monitoring-main/backups/icinga-playground_volumes_backup_20251025_215119.tar.gz
Starting Docker Compose services back up...
[+] Running 7/7
Container icinga-playground-mysql-1           Healthy                                                                                     8.1s
Container icinga-playground-icingadb-redis-1  Healthy                                                                                     7.2s
Container icinga-playground-init-icinga2-1    Exited                                                                                      1.2s
Container icinga-playground-icingaweb-1       Started                                                                                     0.7s
Container icinga-playground-icingadb-1        Started                                                                                     0.5s
Container icinga-playground-icinga2-1         Healthy                                                                                    10.9s
Container icinga-playground-director-1        Started                                                                                     0.2s
```

## Restore backups

```
bash restore.sh
Enter the full path to the backup TAR.GZ file (e.g., ./backups/icinga-playground_volumes_backup_YYYYMMDD_HHMMSS.tar.gz): ./backups/icinga-playground_volumes_backup_20251025_215119.tar.gz
```
