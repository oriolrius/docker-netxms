# NetXMS Docker Deployment

A production-ready Docker deployment for NetXMS network monitoring system, including both server and agent components.

## Overview

This project provides a complete NetXMS setup using Docker containers:

- **NetXMS Server**: Core monitoring server with SQLite database
- **NetXMS Agent**: System monitoring agent running in privileged mode
- **Docker Network**: Isolated network for secure communication

## Quick Start

1. **Clone and Setup**:
   ```bash
   git clone <your-repo>
   cd netxms-docker
   cp .env.example .env
   ```

2. **Configure Environment**:
   Edit `.env` file to match your network setup:
   ```bash
   # Example configuration
   NETXMS_SERVER_PORT=4701
   NETXMS_WEB_PORT=4703
   NETXMS_SERVER_IP=172.20.0.2
   NETXMS_MASTER_SERVERS=172.20.0.0/16
   NETXMS_DEBUG_LEVEL=1
   DOCKER_SUBNET=172.20.0.0/16
   DOCKER_GATEWAY=172.20.0.1
   HOST_CONFIG_PATH=./config
   ```

3. **Deploy**:
   ```bash
   docker compose up -d
   ```

## Architecture

### NetXMS Server Container
- **Image**: `oriolrius/netxms-server:latest`
- **Ports**: 4701 (server), 4703 (web UI)
- **Database**: SQLite (stored in `./var` volume)
- **Network**: Static IP in custom bridge network

### NetXMS Agent Container
- **Image**: `oriolrius/netxms-agent:latest`
- **Mode**: Host network with privileged access
- **Capabilities**: Full system monitoring access
- **Volumes**: Host system directories mounted for monitoring

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETXMS_SERVER_PORT` | 4701 | NetXMS server port |
| `NETXMS_WEB_PORT` | 4703 | Web interface port |
| `NETXMS_SERVER_IP` | 172.20.0.2 | Server IP in Docker network |
| `NETXMS_MASTER_SERVERS` | 172.20.0.0/16 | Allowed master servers CIDR |
| `NETXMS_DEBUG_LEVEL` | 1 | Debug level (1-9) |
| `DOCKER_SUBNET` | 172.20.0.0/16 | Docker network subnet |
| `DOCKER_GATEWAY` | 172.20.0.1 | Docker network gateway |
| `HOST_CONFIG_PATH` | ./config | Host path for config files |

### Volumes

- `./var`: NetXMS server data and database
- `./agent`: NetXMS agent data and configuration
- `./config`: Custom configuration files (optional)

## Management Commands

### Start Services
```bash
docker compose up -d
```

### Stop Services
```bash
docker compose down
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f netxms-server
docker compose logs -f netxms-agent
```

### Check Status
```bash
docker compose ps
```

### Rebuild Images
```bash
docker compose build --no-cache
docker compose up -d
```

## Troubleshooting

### Server Issues

1. **Check server health**:
   ```bash
   docker compose exec netxms-server netstat -ln | grep :4701
   ```

2. **Database issues**:
   ```bash
   docker compose exec netxms-server ls -la /var/lib/netxms/
   ```

3. **View server logs**:
   ```bash
   docker compose logs netxms-server
   ```

### Agent Issues

1. **Check agent process**:
   ```bash
   docker compose exec netxms-agent pgrep nxagentd
   ```

2. **View agent configuration**:
   ```bash
   docker compose exec netxms-agent cat /etc/netxms/nxagentd.conf
   ```

3. **Network connectivity**:
   ```bash
   docker compose exec netxms-agent ping 172.20.0.2
   ```

### Common Issues

- **Permission denied**: Ensure agent runs in privileged mode
- **Network unreachable**: Check Docker network configuration
- **Database locked**: Stop all containers and restart
- **Port conflicts**: Modify ports in `.env` file

## Security Considerations

- Agent runs in privileged mode for system monitoring
- Custom Docker network isolates NetXMS traffic
- Consider using external database for production
- Regular backup of `./var` directory recommended
- Change default admin password after first login

## File Structure

```
netxms-docker/
├── .env                    # Environment configuration
├── .env.example           # Environment template
├── compose.yaml           # Docker Compose configuration
├── Dockerfile.server      # Server container build
├── Dockerfile.agent       # Agent container build
├── var/                   # Server data (auto-created)
├── agent/                 # Agent data (auto-created)
└── config/                # Custom configurations (optional)
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with your environment
5. Submit a pull request

## License

This project is licensed under the MIT License. NetXMS itself is licensed under the GNU General Public License v2.0.

## Support

- NetXMS Documentation: https://www.netxms.org/documentation/
- NetXMS Community: https://forum.netxms.org/
- Docker Hub: https://hub.docker.com/u/oriolrius

## Version Information

- NetXMS Version: Latest from official repository
- Docker Compose Version: 27.0.3+
- Base Image: Ubuntu 24.04
- Supported Architectures: x86_64
