# Validator-Statistik in Icinga, InfluxDB und Grafana

Stand: 2026-10-04. Der Validator läuft auf `ratemymail.eu`, der Monitoring-
Master unter `/opt/icinga-monitoring-main` auf `ckprog.de`. Die zugehörige
SQLite-Migration, der lokale JSON-Endpunkt und die zwei Agent-Skripte liegen
im Repository `incoming-email-validator-go`.

## Datenfluss und Vertrag

1. Der Validator erhöht beim erfolgreichen neuen Report-Commit anonyme UTC-
   Stunden-, Tages- und Monats-Buckets. Ein Retry erhöht nichts.
2. Icinga fragt auf `ratemymail.eu` drei lokale Werte ab. `iev_statistics`
   liegt unter `global-zone/validator-statistics.conf`, der Agent-Sensor
   `/usr/local/libexec/iev-check-statistics` stammt aus dem Validator-Repo.
   Director verwaltet `iev-stats-hour`, `iev-stats-day` und `iev-stats-month`.
   Ausfall oder inkonsistente Summe ist UNKNOWN; null Testmails ist OK.
3. Icinga 2 schreibt Poll-Perfdata über `influxdb2` in `icinga_perfdata` mit
   90 Tagen Aufbewahrung. Ein Poll ist kein exakter UTC-Bucketwert.
4. `scripts/validator-bucket-export.py` holt die begrenzte Bucket-Serie über
   SSH von `ievstats@ratemymail.eu` und schreibt Punkte mit dem tatsächlichen
   Bucketbeginn als Zeitstempel. Messung, Periodentag und Zeitstempel sind
   stabil; ein Retry ersetzt denselben Punkt. Der aktuelle Bucket wird bei
   jedem Lauf erneut geschrieben, damit sein Wert bis zum Abschluss wächst.
   Der Cursor bleibt bei der laufenden Periode stehen. Nach einem Ausfall
   werden alle versäumten Intervalle bis zur aktuellen Grenze in Blöcken von
   höchstens 256 Buckets nachgeholt.
5. Grafana bezieht die drei exakten Buckets mit einem eigenen Lesetoken.
   `scripts/provision-validator-grafana.py` aktualisiert die Datenquelle und
   drei Dashboards mit Gesamt-, Modus-, Status- und Datenqualitätsfeldern. Die Icinga-Services
   verlinken die passenden UIDs.

Die drei exakten Influx-Buckets haben feste Retention von 90, 732 und 1830
Tagen. Die beiden längeren Fristen decken 24 Kalendermonate bzw. fünf Jahre
der SQLite-Buckets auch über Schaltjahre ab. Die Label enthalten nur
Periode, Modus und Status; weder Absender noch Domain, IP, Token oder
Einzelbefund werden exportiert. `known=0` bezeichnet die im Migrationsintervall
unvollständige Vorgeschichte, `complete=0` den laufenden Bucket.

## Deployment und Zugriff

- Die drei Influx-Buckets und je ein Token mit Schreib- bzw. Leserechten nur
  auf diese Buckets wurden erstellt. Token liegen root-only unter
  `/opt/icinga-monitoring-main/validator-stats/{write-token,read-token}`.
  `icinga_perfdata` nutzt einen separaten nur dort schreibberechtigten Token.
  Die Icinga-Feature-Datei enthält diesen Token als Secret im privaten
  persistenten Volume; `icinga2.conf.d/influxdb2-validator.example.conf` ist
  nur eine redigierte Vorlage und wird nicht direkt importiert.
- Der Master besitzt unter `validator-stats/` einen eigenen SSH-Schlüssel und
  eine separate `known_hosts`-Datei. Der ED25519-Fingerprint von
  `ratemymail.eu:25565` wurde vor dem Eintrag gegen den Zielhost geprüft:
  `SHA256:yF9YPUWuaaRvjWp2wKtQTYP1WPC5jVstuqHgXp5c8JA`. Auf dem Ziel darf
  dieser Schlüssel als `ievstats` ausschließlich das feste Kommando
  `/usr/local/libexec/iev-stats-pull` ausführen (`restrict,command=...`).
  Das Konto hat keine Datenbankrechte. Der ursprüngliche SSH-Befehl wird
  geprüft; eine freie Shell und Portweiterleitung sind gesperrt.
- Die private `/opt/icinga-monitoring-main/validator-stats/config.json`
  benennt Schlüssel, Host, Token-Datei, Cursor-Datei und die UTC-Anfänge der
  Statistikmigration. Die Datei und `state.json` sind 0600 im 0700-Verzeichnis.
  `systemd/validator-bucket-export.service` und `.timer` laufen alle fünf
  Minuten; `Persistent=true` holt nach einer ausgefallenen Timer-Ausführung
  nach. Eine länger als die SQLite-Retention ausgefallene Quelle schlägt
  sichtbar fehl und erfordert eine bewusste neue Startgrenze.
- Grafana bindet zusätzlich zu `127.0.0.1:3075` ausschließlich
  `10.200.200.1:3075` im WireGuard-Netz. Die Dashboard-Links lauten
  `http://10.200.200.1:3075/d/iev-stats-{hour,day,month}?orgId=1`;
  Grafana verlangt Login. Der Compose-Stand auf dem Master hat zusätzlich
  `monitoring_bridge.external=true`; diese lokale Eigenschaft bei Updates
  beibehalten. `docker compose config -q` vor einem Containerwechsel prüfen.

## Kontrolle und Wiederherstellung

```sh
docker exec icinga-monitoring-main-icinga2-1 icinga2 daemon -C
ssh ratemymail.eu icinga2 daemon -C
systemctl start validator-bucket-export.service
systemctl show validator-bucket-export.service -p Result -p ExecMainStatus
systemctl list-timers --all validator-bucket-export.timer
docker exec icinga-monitoring-main-icinga2-1 icinga2 feature list
```

Für numerische Gegenprüfung SQLite-`mail_statistics` nach Periode und
`bucket_start` summieren und in InfluxDB dieselbe `mail_test_count`-Messung
mit `_field == "total"` und identischem UTC-Zeitpunkt abfragen. Die drei
Grafana-Dashboards per API `/api/dashboards/uid/iev-stats-{period}` und die
Panels über `/api/ds/query` prüfen. Beim Rollout vom 2026-10-03 lieferte
die Stundenserie für 21:00 UTC den Wert 1 wie SQLite, Tag und Monat ebenso;
ein zweiter Export erzeugte keine doppelten Zeitpunkte. Die Grafana-Abfrage-
API lieferte 2/1/1 Punkte für Stunde/Tag/Monat ohne Fehler.

Private Snapshots auf dem Master: Director/Templates unter
`backups/pre-validator-stats-1791063329/`, Grafana-SQLite und Compose-Stand
unter `backups/pre-iev-grafana-1791065292/`, ursprüngliche Icinga-Feature-
Datei unter `backups/pre-iev-influx-1791063950/`. Influx-Token im privaten
`validator-stats/`-Verzeichnis gehören zum Backup; nie in Git oder Logs
kopieren. Das Validator-Repo dokumentiert die gepaarte Sicherung von
`reports.sqlite` und `reply-limit.key` für Schema 7. Für einen Rückweg
jeweils Dienst/Timer stoppen, Datenbank und Konfiguration aus dem passenden
Snapshot wiederherstellen, Syntax prüfen und Dienste gezielt starten.

Die lokalen Tests für Export und Provisionierung laufen mit:

```sh
python3 -m unittest discover -s tests -p 'test_validator_*.py' -v
ruff check scripts/validator-bucket-export.py scripts/provision-validator-grafana.py tests/
systemd-analyze verify systemd/validator-bucket-export.service systemd/validator-bucket-export.timer
```
