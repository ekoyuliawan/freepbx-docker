## Introduction

This is a production-ready [Docker Compose](https://docs.docker.com/compose/) application for running [FreePBX](https://www.freepbx.org) - a powerful Voice over IP manager for [Asterisk](https://www.asterisk.org) - in containers.

This turnkey PBX system provides **full WebRTC support and WhatsApp SIP Calling capabilities** with the latest FreePBX 17 running on Asterisk 22 LTS with Opus codec.

### Features

* **FreePBX 17.0.25** (EDGE) with Asterisk 22.8.2 LTS
* **Opus codec pre-installed** for high-quality WebRTC and WhatsApp calls
* **WebRTC ready** with secure WebSocket (WSS) support
* **WhatsApp Business SIP calling** with Meta integration (TLS SIP on port 50633)
* PHP 8.2 and Apache 2.4
* MariaDB 10.11 for reliable database backend
* Fail2ban pre-configured with restrictive enforcement rules
* Email notifications via Postfix
* Logrotate configured for Asterisk and FreePBX logs
* Full data persistence with volume mounts
* Base image: Debian Bookworm (slim)
* NodeJS v18 for modern FreePBX features
* DAHDI hardware channels not supported (software-only)

### Ports

The following ports are exposed via Docker:

| Port              | Description |
| ----------------- | ----------- |
| `80/tcp`          | HTTP (Web GUI) |
| `443/tcp`         | HTTPS (Secure Web GUI) |
| `8088/tcp`        | WebSocket (WS) for WebRTC |
| `8089/tcp`        | Secure WebSocket (WSS) for WebRTC |
| `50633/tcp+udp`   | **PJSIP TLS** (custom port for WhatsApp - connects to Meta's port 5061) |

**RTP Ports (Default: 10000-20000/udp)**

RTP ports require special configuration due to a [known Docker limitation](https://github.com/moby/moby/issues/11185) with exposing large port ranges. The installation script automatically configures `iptables` rules to handle RTP traffic efficiently without loading excessive processes into memory.

### Host Requirements

- **Commands**: `ip`, `iptables`, `awk`, `docker`, `docker-compose`
- **Important**: iptables rules inside Docker chains will bypass system firewall rules
- **Firewall persistence**: The script automatically installs and configures `iptables-persistent` to make rules survive reboots
- **DNS**: Ensure Docker has valid DNS resolution by adding to `/etc/docker/daemon.json`:
  ```json
  {
    "dns": ["1.1.1.1", "8.8.8.8"]
  }
  ```
  Then restart Docker: `sudo systemctl restart docker`

- **Fail2ban**: Customize preferences in `fail2ban/jail.local`. Default: bans 2 consecutive failed SIP attempts within 30 seconds for 1 week.

## Installation

### 1. Create Required Credentials

```bash
# MySQL root password
printf "yourStrongPassword" > mysql_root_password.txt

# FreePBX database user password
printf "yourStrongPassword" > freepbxuser_password.txt

# Postfix SMTP credentials (even if not using email notifications)
printf "[smtp.gmail.com]:587 your-email@gmail.com:yourAppPassword" > sasl_passwd.txt

# Secure the files
chmod 600 mysql_root_password.txt freepbxuser_password.txt sasl_passwd.txt
```

### 2. Configure Email Notifications (Optional)

Edit `source/postfix/main.cf` and set the `relayhost` to match your SMTP server defined in `sasl_passwd.txt`.

### 3. Customize Configuration

Edit `docker-compose.yml`:
- Set `hostname:` to your FreePBX domain (required for WebRTC)
- Adjust network settings if needed
- Review volume mounts in `/mnt/storage/`

### 4. Install FreePBX

The installation script handles everything automatically:

```bash
# Simple one-command installation
sudo bash run.sh

# Custom RTP port range (optional)
sudo bash run.sh --rtp 16384-32767
```

The script will:
- ✅ Build Docker image (20-30 minutes first time)
- ✅ Configure persistent iptables rules for RTP
- ✅ Start database and FreePBX containers
- ✅ Install FreePBX with 11 essential modules
- ✅ Configure SSL certificates
- ✅ Set up Opus codec for WebRTC/WhatsApp

### 5. Access FreePBX

After installation completes, access the web interface:
- HTTP: `http://YOUR_SERVER_IP`
- HTTPS: `https://YOUR_SERVER_IP`

Complete the initial setup wizard and create your admin credentials.

## TLS/SSL Certificate Configuration

### For WebRTC and WhatsApp SIP Calling

**FreePBX requires valid TLS certificates** for secure WebSocket (WSS) connections and WhatsApp integration.

#### Recommended: Use FreePBX Certificate Management

1. Log in to FreePBX web interface
2. Navigate to **Admin → Certificate Management**
3. Choose one of these options:

   **Option A: Let's Encrypt (Recommended)**
   - Click "Generate Let's Encrypt Certificate"
   - Enter your domain name
   - Complete DNS validation
   - Auto-renewal is configured

   **Option B: Upload Custom Certificate**
   - Upload your certificate files (.crt, .key, .pem)
   - Assign to services (HTTP, PJSIP TLS)

4. Navigate to **Settings → Asterisk SIP Settings**
5. Under **CHAN PJSIP Settings** tab:
   - Set **TLS Bind Port**: `50633` (for WhatsApp)
   - Select your certificate from dropdown
   - Enable TLS for appropriate transports

6. Apply Config and reload

### Certificate Requirements for WhatsApp
- Must be a valid certificate from a recognized CA (Let's Encrypt works)
- Domain must match your FreePBX hostname
- Certificate must be assigned to PJSIP TLS service
- Port 50633 must be open and accessible from Meta's servers

## WhatsApp Business API Setup

This setup includes **port 50633** specifically configured for **WhatsApp Business SIP calling**, which communicates with Meta's TLS SIP endpoint on port 5061.

**Requirements:**
1. Valid TLS certificate (see above)
2. WhatsApp Business Account with API access
3. Meta Business verification
4. PJSIP trunk configured to Meta's SIP endpoint

**Note**: Port 50633 is a custom TLS port for better security segregation. You can change this in `docker-compose.yml` if needed.

## WebRTC Configuration

1. **Certificate**: Install valid TLS certificate (see above)
2. **HTTP Settings**: 
   - Admin → System Admin → Port Management
   - Ensure ports 8088 (WS) and 8089 (WSS) are configured
3. **PJSIP Settings**:
   - Settings → Asterisk SIP Settings
   - Enable WebRTC transports (WSS)
   - Configure appropriate codecs (Opus is pre-installed)
4. **Extensions**:
   - Create extensions with WebRTC support enabled
   - Test with UCP (User Control Panel)

## Maintenance Commands

```bash
# Check system status
sudo docker compose ps

# View logs
sudo docker compose logs -f freepbx

# Restart containers
sudo docker compose restart

# Stop all containers
sudo docker compose down

# Complete cleanup (removes all data!)
sudo bash run.sh --clean-all

# Verify Opus codec
sudo docker compose exec freepbx asterisk -rx 'core show codecs | grep opus'

# Check iptables rules
sudo iptables -L DOCKER-USER -v -n
sudo iptables -t nat -L PREROUTING -v -n
```

## Storage Locations

All persistent data is stored in `/mnt/storage/`:

| Path | Contents |
| ---- | -------- |
| `/mnt/storage/conf` | Asterisk configuration files |
| `/mnt/storage/log` | Asterisk and FreePBX logs |
| `/mnt/storage/recording` | Call recordings |
| `/mnt/storage/agi-bin` | AGI scripts |
| `/mnt/storage/database` | MariaDB data files |

## Troubleshooting

**FreePBX web interface not loading:**
- Check containers: `sudo docker compose ps`
- View logs: `sudo docker compose logs freepbx`
- Verify Apache: `sudo docker compose exec freepbx service apache2 status`

**No audio in calls:**
- Verify RTP iptables rules: `sudo iptables -L DOCKER-USER -v -n | grep 10000`
- Check Asterisk: `sudo docker compose exec freepbx asterisk -rx 'core show version'`

**WebRTC not connecting:**
- Ensure valid TLS certificate is installed
- Check WSS port 8089 is accessible
- Verify browser console for errors

**WhatsApp SIP not working:**
- Verify port 50633 is open and accessible
- Confirm certificate is valid and assigned to PJSIP
- Check Meta dashboard for connection status

## Support

Need help setting up **WebRTC** or **WhatsApp SIP calling**? 

Feel free to reach out:
- 📧 Email: *[ekoyuliawan26@gmail.com]*
- 💬 Open an issue on GitHub
- 🌐 Website: *[aidoforyou.com]*

I offer consultation and configuration services for:
- WebRTC implementation and optimization
- WhatsApp Business API integration
- Custom Asterisk/FreePBX solutions
- Enterprise VoIP deployments

---

**If you find this project useful, please consider dropping a ⭐ on GitHub!**

## License

This project is provided as-is. FreePBX and Asterisk have their own respective licenses.

## Credits

Based on community contributions and optimized for modern WebRTC and WhatsApp integration.
