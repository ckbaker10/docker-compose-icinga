# Icinga Monitoring Stack with Docker Compose

Complete monitoring solution combining Icinga with time-series databases and visualization tools, featuring intelligent backup/restore capabilities and flexible networking.

## Architecture

This repository provides a comprehensive dual-stack monitoring solution:

- **`docker-compose.yml`** - Core Icinga stack (Icinga 2, Icinga Web 2, Icinga DB, Director)
- **`docker-compose-influx-grafana.yml`** - Time-series monitoring stack (InfluxDB 2.7.12, Chronograf, Grafana)
- **Intelligent Backup/Restore** - Unified backup system supporting both stacks with legacy compatibility
- **Flexible Networking** - Run stacks independently or connected via shared bridge network

Both stacks can run independently or together, with automatic volume detection and cross-compatible backup/restore functionality.

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
   
   # OR start monitoring stack only
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
- Ideal for: Integrated monitoring pipelines, data forwarding

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

### Icinga Stack
- **Icinga Web 2**: http://localhost:3065 (default: `icingaadmin` / `icinga`)
- **Icinga 2 API**: https://localhost:3070 (default: `icingaweb` / `icingaweb`)

### Monitoring Stack
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

### Monitoring Stack
- **InfluxDB**: `admin` / `adminpassword` (token: `mytoken`)
- **Grafana**: `admin` / `grafanapassword`
- **Chronograf**: No authentication (connects to InfluxDB with above credentials)

**Security Note**: Change all default passwords in production by copying `.env.example` to `.env` and setting secure values.

## Data Persistence & Backup

### Volume Structure

All service data persists in named Docker volumes with automatic project-based naming:

**Icinga Stack:**
- `{project}_icinga2` - Icinga 2 configuration and state  
- `{project}_icingaweb` - Icinga Web 2 configuration
- `{project}_mysql` - Database storage (IcingaDB, Director, Users)

**Monitoring Stack:**
- `{project}_influxdb-storage` - Time-series data and InfluxDB configuration
- `{project}_chronograf-storage` - Chronograf dashboards and settings
- `{project}_grafana-storage` - Grafana dashboards, datasources, and configuration

*Note: `{project}` is automatically derived from the directory name (e.g., `icinga-monitoring-main`)*

### Backup System

The repository includes intelligent backup and restore scripts with the following features:

- **Unified Backups**: Single backup file containing both Icinga and monitoring stack data
- **Selective Restore**: Restore only the stacks you need
- **Legacy Compatibility**: Automatically detects and migrates old Icinga-only backups
- **Smart Detection**: Auto-discovers volume naming patterns
- **Safe Operations**: Confirms destructive actions and provides warnings

#### Creating Backups

```bash
# Create backup of all existing volumes
./backup.sh

# Backup includes:
# - Auto-discovery of existing volumes
# - Consistent snapshots (services temporarily stopped)
# - Compressed archive with metadata
# - Automatic service restart
```

#### Restoring from Backup

```bash
# Restore from backup (interactive)
./restore.sh

# Features:
# - Backup content analysis and preview
# - Legacy backup detection and migration
# - Selective restoration based on available compose files
# - Volume cleanup and recreation
# - Intelligent service startup
```

#### Backup Examples

**Full Stack Backup:**
```bash
$ ./backup.sh
Discovering existing volumes...
  Found Icinga volume: icinga-monitoring-main_icinga2
  Found Icinga volume: icinga-monitoring-main_icingaweb  
  Found Icinga volume: icinga-monitoring-main_mysql
  Found monitoring volume: icinga-monitoring-main_influxdb-storage
  Found monitoring volume: icinga-monitoring-main_chronograf-storage
  Found monitoring volume: icinga-monitoring-main_grafana-storage
Backup successful!
  Archive: ./backups/monitoring_stack_backup_20241027_143022.tar.gz
```

**Legacy Restore (Icinga-only to current structure):**
```bash
$ ./restore.sh
Enter backup path: ./backups/icinga-playground_volumes_backup_20241025_120000.tar.gz

Detected LEGACY backup format (Icinga-only with icinga2/icingaweb/mysql directories)
LEGACY BACKUP DETECTED:
  This backup will be restored to current volume naming convention:
  icinga2 -> icinga-monitoring-main_icinga2
  icingaweb -> icinga-monitoring-main_icingaweb  
  mysql -> icinga-monitoring-main_mysql
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
docker exec -it $(docker compose ps -q mysql) mysql -u root -p
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
