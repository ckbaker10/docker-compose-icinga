# Icinga Monitoring Stack with Docker Compose

Complete monitoring solution combining Icinga with time-series databases and visualization tools.

## Architecture

This repository provides two Docker Compose configurations:

- **`docker-compose.yml`** - Core Icinga stack (Icinga 2, Icinga Web 2, Icinga DB, Director)
- **`docker-compose-influx-grafana.yml`** - Time-series monitoring stack (InfluxDB, Chronograf, Grafana)

Both stacks can run independently or together via a shared monitoring bridge network.

## Quick Start

### Prerequisites

- Docker Engine 20.10+
- Docker Compose v2.0+

### Basic Setup

1. **Configure Environment Variables**
   ```bash
   cp .env.example .env
   # Edit .env with your desired passwords and settings
   ```

2. **Start the Icinga Stack**
   ```bash
   docker-compose up -d
   ```

3. **Start the Monitoring Stack** (optional)
   ```bash
   docker-compose -f docker-compose-influx-grafana.yml up -d
   ```

## Network Configuration

The stacks support flexible networking through the `USE_EXTERNAL_NETWORK` environment variable:

- **`USE_EXTERNAL_NETWORK=false`** (default) - Creates networks locally
- **`USE_EXTERNAL_NETWORK=true`** - Uses external shared network

For shared networking between stacks:
```bash
# Create shared network
docker network create monitoring_bridge

# Set environment variable
echo "USE_EXTERNAL_NETWORK=true" >> .env

# Start both stacks
docker-compose up -d
docker-compose -f docker-compose-influx-grafana.yml up -d
```

## Service Access Points

### Icinga Stack
- **Icinga Web 2**: http://localhost:3065 (admin: `icingaadmin`)
- **Icinga 2 API**: https://localhost:3070 (api user: `icingaweb`)

### Monitoring Stack
- **InfluxDB**: http://localhost:8086
- **Chronograf**: http://localhost:8888
- **Grafana**: http://localhost:3075 (admin configurable via env)

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

## Maintenance Operations

### Clean Restart
```bash
docker-compose down
docker-compose up -d
```

### Full Reset (destroys all data)
```bash
docker-compose down --volumes
docker-compose up -d
```

### Update Images
```bash
docker-compose pull
docker-compose up -d
```

## Troubleshooting

### Check Service Health
```bash
docker-compose ps
```

### View Service Logs
```bash
docker-compose logs [service_name]
```

### Database Connection Issues
Ensure MySQL is healthy before dependent services start. Check logs for initialization errors.

### Network Connectivity
Verify the monitoring bridge network exists if using external networking:
```bash
docker network ls | grep monitoring_bridge
```
