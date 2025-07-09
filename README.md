# NetXMS Docker Deployment
A production-ready Docker deployment for NetXMS network monitoring system, including both server and agent components with advanced proxy capabilities.

## Overview
This project provides a complete NetXMS setup using Docker containers:
- **NetXMS Server**: Core monitoring server with SQLite database
- **NetXMS Agent**: System monitoring agent with proxy capabilities for gateway functionality
- **Docker Network**: Isolated network for secure communication

## Quick Start
1. **Clone and Setup**:
   ```bash
   git clone <your-repo>
   cd netxms
   cp .env.example .env
   ```

2. **Configure Environment**:
   Edit `.env` file to match your network setup:
   ```bash
   # Example configuration
   NETXMS_SERVER_PORT=4701      # client connections
   NETXMS_TUNNEL_PORT=4703      # agent tunnel port
   NETXMS_SERVER_IP=172.20.0.2
   NETXMS_MASTER_SERVERS=172.20.0.0/16
   NETXMS_DEBUG_LEVEL=1
   DOCKER_SUBNET=172.20.0.0/16
   DOCKER_GATEWAY=172.20.0.1
   PROXY_AGENT=yes              # Enable agent proxy functionality
   PROXY_SNMP=yes               # Enable SNMP proxy functionality
   HOST_CONFIG_PATH=./config
   ```

3. **Deploy**:
   ```bash
   docker compose up -d
   ```

## Architecture
### NetXMS Server Container
- **Image**: `ghcr.io/oriolrius/docker-netxms-server:latest`
- **Ports**: 4701 (client connections), 4703 (agent tunnel)
- **Database**: SQLite (stored in `./data` volume)
- **Network**: Static IP in custom bridge network

### NetXMS Agent Container
- **Image**: `ghcr.io/oriolrius/docker-netxms-agent:latest`
- **Mode**: Host network with privileged access
- **Capabilities**: Full system monitoring access + proxy functionality
- **Volumes**: Host system directories mounted for monitoring
- **Proxy Features**: Agent and SNMP proxy capabilities for gateway operations

## Proxy Functionality

The NetXMS agent can operate as a gateway to monitor devices that are not directly accessible from the NetXMS server. This is particularly useful for:

### Agent Proxy (`PROXY_AGENT=yes`)

- Allows the agent to act as a gateway for other NetXMS agents
- Enables monitoring of systems behind firewalls or in isolated network segments
- The NetXMS server connects through this agent to reach other agents

### SNMP Proxy (`PROXY_SNMP=yes`)

- Enables forwarding of SNMP requests to SNMP-enabled devices
- Useful for monitoring printers, switches, routers, and other network devices
- Allows monitoring devices behind NAT or firewalls

### Use Case Example

```
NetXMS Server (192.168.11.22) 
    ↓
Agent Gateway (192.168.41.61) [PROXY_SNMP=yes]
    ↓
Printer (10.131.111.200) - not directly reachable from server
```

In this scenario, the NetXMS server can monitor the printer through the agent gateway using SNMP proxy functionality.

## Configuration
### Environment Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `NETXMS_SERVER_PORT` | 4701 | Client connection port |
| `NETXMS_TUNNEL_PORT` | 4703 | Agent tunnel port |
| `NETXMS_SERVER_IP` | 172.20.0.2 | Server IP in Docker network |
| `NETXMS_MASTER_SERVERS` | 172.20.0.0/16 | Allowed master servers CIDR |
| `NETXMS_DEBUG_LEVEL` | 1 | Debug level (1-9) |
| `DOCKER_SUBNET` | 172.20.0.0/16 | Docker network subnet |
| `DOCKER_GATEWAY` | 172.20.0.1 | Docker network gateway |
| `PROXY_AGENT` | yes | Enable agent proxy functionality |
| `PROXY_SNMP` | yes | Enable SNMP proxy functionality |
| `HOST_CONFIG_PATH` | ./config | Host path for config files |

### Proxy Configuration Details

- **PROXY_AGENT**: Set to `yes` to enable NetXMS agent proxy functionality. This allows the agent to forward connections to other NetXMS agents that are not directly reachable from the server.
- **PROXY_SNMP**: Set to `yes` to enable SNMP proxy functionality. This allows the agent to forward SNMP requests to devices that are not directly accessible from the NetXMS server.

### Server-Side Proxy Configuration

After enabling proxy functionality on the agent, you must configure the NetXMS server to use the proxy:

1. **For SNMP Proxy**: In the NetXMS management client, go to the target device properties → Communications tab → SNMP section → Set "SNMP Proxy" to the proxy agent node.

2. **For Agent Proxy**: In the target node properties → Communications tab → Set "NetXMS Agent Proxy" to the proxy agent node.

### Volumes

- `./data`: NetXMS server data and database
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

4. **Verify proxy configuration**:

   ```bash
   docker compose exec netxms-agent grep -E "(EnableProxy|EnableSNMPProxy)" /etc/netxms/nxagentd.conf
   ```

### Proxy-Specific Issues

- **SNMP proxy not working**: Ensure both `PROXY_SNMP=yes` in the agent and SNMP proxy is configured in the NetXMS server for the target device
- **Agent proxy not working**: Verify `PROXY_AGENT=yes` and that the proxy agent is set in the target node's communication properties
- **Network routing**: Ensure the proxy agent can reach both the NetXMS server and the target devices

### Common Issues

- **Permission denied**: Ensure agent runs in privileged mode
- **Network unreachable**: Check Docker network configuration and proxy routing
- **Database locked**: Stop all containers and restart
- **Port conflicts**: Modify ports in `.env` file
- **Proxy authentication**: Check that proxy agent has proper access to target devices

## Security Considerations

- Agent runs in privileged mode for system monitoring
- Custom Docker network isolates NetXMS traffic
- Proxy functionality requires careful network security planning
- Consider using external database for production
- Regular backup of `./data` directory recommended
- Change default admin password after first login
- Review proxy access permissions for security compliance

## File Structure

```
netxms/
├── .env                    # Environment configuration
├── .env.example           # Environment template with proxy examples
├── compose.yaml           # Docker Compose configuration
├── Dockerfile.server      # Server container build
├── Dockerfile.agent       # Agent container build with proxy support
├── data/                   # Server data (auto-created)
├── agent/                 # Agent data (auto-created)
└── config/                # Custom configurations (optional)
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with your environment, especially proxy functionality
5. Submit a pull request

## License

This project is licensed under the MIT License. NetXMS itself is licensed under the GNU General Public License v2.0.

## Support

- NetXMS Documentation: https://www.netxms.org/documentation/
- NetXMS Community: https://forum.netxms.org/
- Proxy Configuration: https://www.netxms.org/documentation/adminguide/agent-management.html

## Version Information

- NetXMS Version: Latest from official repository
- Docker Compose Version: 27.0.3+
- Base Image: Ubuntu 24.04
- Supported Architectures: x86_64
- Proxy Features: Agent and SNMP proxy support included
