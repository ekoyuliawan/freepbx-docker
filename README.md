## Introduction

This is MVP [Docker Compose](https://docs.docker.com/compose/) application for having [FreePBX](https://www.freepbx.org) - A Voice over IP manager for [Asterisk](https://www.asterisk.org), running in containers.

Upon starting this multi-container application, it will give you a turnkey PBX system for SIP calling.

* FreePBX 17.0.21
* PHP 8.2.29
* Asterisk 21.10.2
* MariaDB 10.11.14
* Fail2ban pre-configured with restrictive enforcement rules
* Email notifications
* Supports data persistence
* Base image Debian [debian:bookworm-slim](https://hub.docker.com/_/debian/)
* Apache 2.4.65
* NodeJS v18.20.4
* DAHDI channel not supported

### Volumes
| Directories        | Service |              
| ----------------   | ------- |          
| `/etc`             | freepbx |         
| `/usr`             | freepbx |            
| `/home/asterisk`   | freepbx |     
| `/var`             | freepbx | 
| `/var/lib`         | mysql   |  


### Ports
The following ports are exposed via Docker.

| Port              | Description |
| ----------------- | ----------- |
| `80/tcp`          | HTTP        |
| `5060/udp`        | PJSIP       |

RTP ports e.g. `16384-32767/udp` require a particular configuration in order to be
properly exposed.\
There's a [known issue](https://github.com/moby/moby/issues/11185) about Docker and its way to expose a large range of ports, since each port exposed loads another process into memory and you may be experiencing a low memory condition.\
As a trade-off, those ports are going to be exposed via Docker host `iptables` manually.\
So [run.sh](run.sh) will take care of iptables configuration, besides building and running the image.

### Host requirements
- `ip`, `iptables` and `awk` commands
- 64-bit Intel/AMD (x86_64) platform. Arm architecture is not supported since Asterisk needs to be compiled differently.
- Docker iptables rules will bypass any firewall rule on the system.
- Iptables rules are temporary, unless you make them persistent in this way:
```bash
sudo apt-get update
sudo apt-get install -y iptables-persistent
sudo systemctl enable netfilter-persistent
sudo systemctl restart netfilter-persistent
sudo systemctl status netfilter-persistent

# Everytime you make a change to iptables, remember to save to disk
sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
```
- Customize Fail2ban preferences by editing the file `fail2ban/jail.local`. Currently it bans 2 consecutive failed SIP registration attempts within 30 seconds for 1 week.

- Make sure to configure a valid DNS server for Docker containers by adding the following to `/etc/docker/daemon.json` (restart Docker after saving the file):
  ```json
  {
    "dns": ["1.1.1.1"]
  }
  ```

## Usage
1. Create a password for MySQL root user:
```bash
printf "your-mysql-root-password" > mysql_root_password.txt
printf "yourstrongmysqlfreepbxuserpassword" > freepbxuser_password.txt

# Set proper file permissions
chmod 600 mysql_root_password.txt
chmod 600 freepbxuser_password.txt
```

2. If you want to enable email notifications, configure the following:
- set the `relayhost` in [postfix/main.cf](source/postfix/main.cf) to match your SMTP server. 
- fill in [postfix/sasl_passwd](source/postfix/sasl_passwd) with your SMTP server again and your email credentials\
Example configurations for Gmail accounts are included in those files.

3. OPTION A: build the image from scratch:\
```bash
# Build it
cd source && sudo docker build -t freepbx:your-tag .
```
Then edit the value of services.freepbx.image in the docker-compose.yaml by setting the proper image version and tag.

3. OPTION B: if you want to use the pre-built image on Docker Hub, jump to the next step directly

4. Configure RTP ports on the host and build + run the Compose project:
```bash
sudo bash run.sh
# If you want to override the default RTP port range (16384-32767):
sudo bash run.sh --rtp 10000-20000
# NOTE
# If you run the script with the default RTP range 16384-32767 and later rerun it with a different range, the iptables rules from the previous range remain in place and you have to delete those rules manually before or after applying the new range.

# Install Freepbx
sudo bash run.sh --install-freepbx

# Optional, clean up containers, network and volumes
sudo bash run.sh --clean-all
```

Login to the web server's admin URL and start configuring the system!
