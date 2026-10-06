# Icinga InfluxDB Grafana Stack with Docker Compose

## Architecture

- **`docker-compose.yml`** - Core Icinga stack (Icinga 2, Icinga Web 2, Icinga DB, Director)
- **`docker-compose-influx-grafana.yml`** - Time-series Graphing Stack (InfluxDB 2.9, Chronograf, Grafana)
- **Intelligent Backup/Restore** - Unified backup system supporting both stacks with legacy compatibility
- **Flexible Networking** - Run stacks independently or connected via shared bridge network

Both stacks can run independently or together, with automatic volume detection and cross-compatible backup/restore functionality.

### Images

Pinned to minor versions; `docker compose pull` picks up patch releases only.

| Service | Image |
|---|---|
| icinga2, init-icinga2 | `icinga/icinga2:2.16` |
| icingadb | `icinga/icingadb:1.5` |
| icingadb-redis | `redis:8.10` |
| icingaweb, director | `icinga/icingaweb2:2.14` |
| mysql | `mariadb:10.7` |
| influxdb | `influxdb:2.9` |
| chronograf | `chronograf:1.11` |
| grafana | `grafana/grafana:13.2` |

### Monitoring plugins

The check commands for the agents come from two companion repositories; put
their command files into `global-zone/` and run the Director kickstart (see
[Global Zone Configuration](#global-zone-configuration)):

| Repository | File | Commands |
|---|---|---|
| [nagios-plugins-general](https://github.com/ckbaker10/nagios-plugins-general) | `icinga-commands/commands-nagios-plugins.conf` | `git_check_*` for the standard nagios-plugins (same build on all hosts) |
| [nagios-plugins-custom](https://github.com/ckbaker10/nagios-plugins-custom) | `icinga-custom-commands/commands-custom.conf` | own plugins (`check_p110`, `check_lte_router`, …) and the SMS notification command |

Both repositories install the plugins on the agents with Ansible.

## Quick Start

### Prerequisites

- Docker Engine 20.10+
- Docker Compose v2.0+

### Basic Setup

1. **Configure Environment Variables** (Optional)
   ```bash
   cp .env.example .env
   # Edit .env with your desired passwords and settings
   # If no .env file exists, defaults will be used
   ```

2. **Choose Your Deployment Strategy**

   **Option A: Independent Stacks (Default)**
   ```bash
   # Start Icinga stack only
   docker compose up -d
   
   # OR start Graphing Stack only
   docker compose -f docker-compose-influx-grafana.yml up -d
   
   # OR start both independently (no cross-communication)
   docker compose up -d
   docker compose -f docker-compose-influx-grafana.yml up -d
   ```

   **Option B: Connected Stacks (Shared Network)**
   ```bash
   # Create shared network and enable cross-stack communication
   docker network create monitoring_bridge
   echo "USE_EXTERNAL_NETWORK=true" >> .env
   
   # Start both stacks (order doesn't matter)
   docker compose up -d
   docker compose -f docker-compose-influx-grafana.yml up -d
   ```

3. **Verify Deployment**
   ```bash
   # Check service health
   docker compose ps
   docker compose -f docker-compose-influx-grafana.yml ps
   ```

## Network Configuration

The stacks support flexible networking modes through the `USE_EXTERNAL_NETWORK` environment variable:

### Independent Mode (Default)
- **`USE_EXTERNAL_NETWORK=false`** or unset
- Each stack creates its own isolated `monitoring_bridge` network
- Stacks cannot communicate with each other
- Ideal for: Single-stack deployments, testing, isolated environments

### Connected Mode 
- **`USE_EXTERNAL_NETWORK=true`**
- Both stacks share a single external `monitoring_bridge` network
- Services can communicate across stacks (e.g., Icinga → InfluxDB)
- Ideal for: Integrated graphing pipelines, data forwarding

### Network Management Examples

**Switch from Independent to Connected:**
```bash
# Stop stacks
docker compose down
docker compose -f docker-compose-influx-grafana.yml down

# Enable shared networking
echo "USE_EXTERNAL_NETWORK=true" >> .env
docker network create monitoring_bridge

# Restart in connected mode
docker compose up -d
docker compose -f docker-compose-influx-grafana.yml up -d
```

**Switch from Connected to Independent:**
```bash
# Stop stacks and remove shared network
docker compose down
docker compose -f docker-compose-influx-grafana.yml down
docker network rm monitoring_bridge

# Disable shared networking
sed -i '/USE_EXTERNAL_NETWORK=true/d' .env  # Linux
# or edit .env manually to remove the line

# Restart in independent mode
docker compose up -d
docker compose -f docker-compose-influx-grafana.yml up -d
```

## Service Access Points

All ports are published on `127.0.0.1` only. To let remote agents connect
to the API, publish port 5665 on a reachable address (e.g. a VPN address)
in `docker-compose.yml` or put a proxy/tunnel in front.

### Icinga Stack
- **Icinga Web 2**: http://localhost:3065 (default: `icingaadmin` / `icinga`)
- **Icinga 2 API**: https://localhost:3070 (default: `icingaweb` / `icingaweb`)

### Graphing Stack
- **InfluxDB**: http://localhost:8086 (default: `admin` / `adminpassword`)
- **Chronograf**: http://localhost:8888 (connects to InfluxDB automatically)
- **Grafana**: http://localhost:3075 (default: `admin` / `grafanapassword`)

## Environment Configuration

All passwords and settings are configurable via environment variables. See `.env.example` for available options:

```bash
# Network Configuration
USE_EXTERNAL_NETWORK=false

# Icinga Authentication
ICINGAWEB_ADMIN_PASSWORD=secure_password
ICINGAWEB_ICINGA2_API_USER_PASSWORD=api_password

# Database Passwords
MYSQL_ROOT_PASSWORD=root_password
ICINGADB_MYSQL_PASSWORD=icingadb_password
ICINGAWEB_MYSQL_PASSWORD=icingaweb_password
ICINGA_DIRECTOR_MYSQL_PASSWORD=director_password

# InfluxDB Configuration
INFLUXDB_USERNAME=admin
INFLUXDB_PASSWORD=secure_password
INFLUXDB_ADMIN_TOKEN=secure_token

# Grafana Configuration
GRAFANA_USERNAME=admin
GRAFANA_PASSWORD=secure_password
```

## Configuration Management

### Global Zone Configuration

The Icinga2 service includes a volume mount for global zone configurations:

```yaml
- ./global-zone/:/etc/icinga2/zones.d/global-templates
```

#### Purpose
The `global-zone/` directory contains configuration files that are automatically synchronized to all Icinga agents connected to this master. This is useful for:

- Host and service templates
- Command definitions
- Notification configurations
- Check commands that should be available on all agents

#### Usage Workflow

1. **Add Configuration Files**
   ```bash
   # Place your .conf files in the global-zone directory
   mkdir -p global-zone
   cp my-template.conf global-zone/
   ```

2. **Restart Icinga2 Container**
   ```bash
   docker compose restart icinga2
   ```

3. **Verify Configuration Health**
   ```bash
   # Check if container is healthy (configuration is valid)
   docker compose ps icinga2
   
   # If unhealthy, check logs for configuration errors
   docker compose logs icinga2
   ```

4. **Import Changes via Director**
   - Navigate to **Director → Infrastructure → Kickstart**
   - Click **Import** to sync the new configurations

#### Troubleshooting Configuration Issues

If the container becomes unhealthy after adding configurations:
- Review configuration syntax in your `.conf` files
- Check container logs for specific error messages
- Remove problematic files and restart the container
- Validate configuration syntax before deployment

## Default Credentials

When no `.env` file is present, the following default credentials are used:

### Icinga Stack
- **Icinga Web 2 Admin**: `icingaadmin` / `icinga`
- **Icinga 2 API User**: `icingaweb` / `icingaweb`
- **MySQL Root**: `root` / `rootpassword`
- **Database Users**: 
  - IcingaDB: `icingadb` / `icingadb`
  - IcingaWeb: `icingaweb` / `icingaweb`
  - Director: `director` / `director`

### Graphing Stack
- **InfluxDB**: `admin` / `adminpassword` (token: `mytoken`)
- **Grafana**: `admin` / `grafanapassword`
- **Chronograf**: No authentication (connects to InfluxDB with above credentials)

**Security Note**: Change all default passwords in production by copying `.env.example` to `.env` and setting secure values.

**Changing passwords later**: The database users and the Icinga 2 API user are created only on the first start, when the volumes are still empty. Changing `MYSQL_ROOT_PASSWORD`, `ICINGADB_MYSQL_PASSWORD`, `ICINGAWEB_MYSQL_PASSWORD`, `ICINGA_DIRECTOR_MYSQL_PASSWORD` or `ICINGAWEB_ICINGA2_API_USER_PASSWORD` in `.env` afterwards does not update the existing accounts. Change them in the running services as well:

```bash
# Database user, e.g. icingaweb (repeat for icingadb, director)
docker compose exec mysql mariadb -u root -p -e "ALTER USER 'icingaweb'@'%' IDENTIFIED BY 'NEW_PASSWORD';"

# Icinga 2 API user: remove the generated file, re-run the init container, restart icinga2
docker compose run --rm --no-deps icinga2 rm /data/etc/icinga2/conf.d/icingaweb-api-user.conf
docker compose up -d --force-recreate init-icinga2 icinga2 icingaweb director
```

## Data Persistence & Backup

### Volume Structure

All service data persists in named Docker volumes with automatic project-based naming:

**Icinga Stack:**
- `{project}_icinga2` - Icinga 2 configuration and state  
- `{project}_icingaweb` - Icinga Web 2 configuration
- `{project}_mysql` - Database storage (IcingaDB, Director, Users)

**Graphing Stack:**
- `{project}_influxdb-storage` - Time-series data and InfluxDB configuration
- `{project}_chronograf-storage` - Chronograf dashboards and settings
- `{project}_grafana-storage` - Grafana dashboards, datasources, and configuration

*Note: `{project}` is automatically derived from the directory name (e.g., `icinga-monitoring-main`)*

### Backup System

The repository includes intelligent backup and restore scripts with the following features:

- **Unified Backups**: Single backup file containing both Icinga and Graphing Stack data
- **Selective Restore**: Only the stacks contained in the backup are stopped and restored
- **Legacy Compatibility**: Older Icinga-only backups and volumes named `icinga-playground_*` or without prefix are recognised
- **Project-aware**: Volume names follow the Compose project name (directory name or `COMPOSE_PROJECT_NAME`)
- **Safe Operations**: Nothing is stopped or changed before the restore is confirmed; any error aborts with a non-zero exit code

Both scripts can be called from any directory; they work relative to their own location.

#### Creating Backups

```bash
./backup.sh
```

Running services are stopped for a consistent copy and exactly those services are started again afterwards, also when the backup fails. The archive is written to `backups/` together with a metadata file; an incomplete archive is removed.

#### Restoring from Backup

```bash
./restore.sh backups/monitoring_stack_backup_20241027_143022.tar.gz
# or without argument to be asked for the path
```

The script shows which volume each backup entry is restored to and asks for confirmation. It then stops the affected stacks, empties the target volumes (missing volumes are created), extracts the archive and starts the stacks again. If extraction fails, the stacks stay stopped.

#### Backup Example

```bash
$ ./backup.sh
Discovering existing volumes (project: icinga-monitoring-main)...
  Found volume: icinga-monitoring-main_icinga2
  Found volume: icinga-monitoring-main_icingaweb
  Found volume: icinga-monitoring-main_mysql
  Found volume: icinga-monitoring-main_grafana-storage
Stopping services from docker-compose.yml for a consistent backup...
Creating archive monitoring_stack_backup_20241027_143022.tar.gz...
Backup successful!
  Archive: /opt/icinga-monitoring-main/backups/monitoring_stack_backup_20241027_143022.tar.gz
```

## Maintenance Operations

### Backup Operations
```bash
# Create backup before maintenance
./backup.sh

# Restore from backup if needed
./restore.sh
```

### Service Management
```bash
# Clean restart (preserves data)
docker compose down
docker compose up -d

# Restart specific stack
docker compose -f docker-compose-influx-grafana.yml restart

# Check service health
docker compose ps
```

### Data Management
```bash
# Full reset - Icinga stack only (destroys all Icinga data)
docker compose down --volumes
docker compose up -d

# Full reset - Both stacks (destroys all data)
docker compose down --volumes  
docker compose -f docker-compose-influx-grafana.yml down --volumes
docker compose up -d
docker compose -f docker-compose-influx-grafana.yml up -d

# Selective reset - Remove specific volumes
docker volume rm icinga-monitoring-main_grafana-storage
docker compose -f docker-compose-influx-grafana.yml up -d
```

### Updates and Upgrades
```bash
# Update container images
docker compose pull
docker compose -f docker-compose-influx-grafana.yml pull

# Restart with new images
docker compose up -d
docker compose -f docker-compose-influx-grafana.yml up -d

# Check for any issues after update
docker compose ps
docker compose logs
```

**InfluxDB 2.7 → 2.9:** take a backup first (`./backup.sh`). On the first
start, 2.9 migrates the metadata store (it keeps
`influxd.bolt.pre-v2.9.x-upgrade.backup` in the volume) and stores API tokens
only as hashes from then on. Existing tokens such as `INFLUXDB_ADMIN_TOKEN`
keep working, but their plaintext can no longer be read back from InfluxDB,
and going back below 2.8 deletes all tokens. To roll back, restore the
backup taken before the upgrade.

**MariaDB:** stays on `mariadb:10.7` (end of life since 2023-02) until a
major-version upgrade has been tested with a copy of the real database. With
a freshly created test database, 10.7 → 11.8 (LTS) worked as follows:

1. `./backup.sh`
2. In `docker-compose.yml` set `image: mariadb:11.8` and add
   `MARIADB_AUTO_UPGRADE: "1"` to the `mysql` environment.
3. `docker compose up -d` – the entrypoint saves the system tables to
   `system_mysql_backup_*.sql.zst` in the volume and runs `mariadb-upgrade`;
   Icinga DB, Icinga Web and the Director keep their data.

From 11.0 on, the image only ships `mariadb`/`mariadb-admin`, no
`mysql`/`mysqladmin`; the health check and `env/mysql/init-mysql.sh` already
use the new names.

### Environment Changes
```bash
# Switch networking modes (see Network Configuration section)
# Update passwords (requires container restart)
vim .env
docker compose down && docker compose up -d

# Add new environment variables
echo "NEW_SETTING=value" >> .env
docker compose up -d  # Only affects containers that use the variable
```

## Troubleshooting

### Service Health Checks
```bash
# Check all services status
docker compose ps
docker compose -f docker-compose-influx-grafana.yml ps

# View service logs  
docker compose logs [service_name]
docker compose logs -f icinga2  # Follow logs in real-time

# Check resource usage
docker stats
```

### Common Issues

#### Network Configuration Problems
```bash
# External network not found error
docker network ls | grep monitoring_bridge
# If missing: docker network create monitoring_bridge

# Check network configuration
docker network inspect monitoring_bridge

# Reset networking (when USE_EXTERNAL_NETWORK=true)
docker compose down
docker compose -f docker-compose-influx-grafana.yml down  
docker network rm monitoring_bridge
docker network create monitoring_bridge
docker compose up -d
docker compose -f docker-compose-influx-grafana.yml up -d
```

#### Database Connection Issues
```bash
# Check MySQL health and logs
docker compose ps mysql
docker compose logs mysql

# Verify database initialization
docker exec -it $(docker compose ps -q mysql) mariadb -u root -p
# Use password from MYSQL_ROOT_PASSWORD (default: rootpassword)

# Reset MySQL data (destroys all data)
docker compose down
docker volume rm icinga-monitoring-main_mysql
docker compose up -d
```

#### Volume and Backup Issues
```bash
# List all project volumes
docker volume ls | grep $(basename $(pwd))

# Check volume usage and sizes
docker system df

# Backup/restore troubleshooting
ls -la backups/  # Check backup files exist
tar -tzf backups/backup_file.tar.gz | head -20  # Check backup contents

# Manual volume cleanup (dangerous - destroys data)
docker compose down --volumes
docker volume prune
```

#### Permission and Access Issues
```bash
# Reset Icinga Web admin password
# Edit .env file, then restart
echo "ICINGAWEB_ADMIN_PASSWORD=newpassword" >> .env
docker compose restart icingaweb

# Check default credentials (see Default Credentials section)
# Verify service accessibility
curl -I http://localhost:3065  # Icinga Web 2
curl -I http://localhost:3075  # Grafana  
curl -I http://localhost:8086/ping  # InfluxDB
```

#### Performance and Resource Issues
```bash
# Check container resource usage
docker stats --no-stream

# Check available disk space
df -h
docker system df

# Clean up unused resources
docker system prune -a  # Removes unused containers, networks, images

# Monitor container logs for errors
docker compose logs --tail=50
```
