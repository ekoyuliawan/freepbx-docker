## Introduction

This is MVP [Docker Compose](https://docs.docker.com/compose/) application for having [FreePBX](https://www.freepbx.org) - A Voice over IP manager for [Asterisk](https://www.asterisk.org), running in containers.

Upon starting this multi-container application, it will give you a turnkey PBX system for SIP calling.

* FreePBX 17.0.21
* PHP 8.2.29
* Asterisk 21.10.2
* MariaDB 10.11.14
* Fail2ban pre-configured with restrictive enforcement rules
* Supports data persistence
* Base image Debian [debian:bookworm-slim](https://hub.docker.com/_/debian/)
* Apache 2.4.65
* NodeJS v18.20.4

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
So, `run.sh` will take care of iptables configuration, besides building and running the image.

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

- If containers can ping a public IP (e.g., ping 8.8.8.8 works), but fail when pinging a domain name (e.g., ping google.com fails), you have to configure a valid DNS server for Docker containers by adding the following to `/etc/docker/daemon.json` (restart Docker after saving the file):
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

2. OPTION A: build the image from scratch:\
**Important**: the Dockerfile installs "linux-headers-`uname -r`".\
During docker build, `uname -r` resolves to the host kernel version.\
That means that you need to build on a Debian host running a Debian kernel that matches the image’s release.\
On non-Debian hosts (or mismatched kernels), the `apt` install will fail.\
Those Kernel headers are only required if you want to compile kernel modules like DAHDI driver. 
If you don’t need DAHDI, simply remove that package line from the [Dockerfile](source/Dockerfile). In case you need it, prefer building/loading DAHDI on the host and exposing `/dev/dahdi` to the container; building kernel modules inside the image tightly couples the build to the host kernel and is fragile.
```bash
# Build it
cd source && sudo docker build -t freepbx:your-tag .

# Then edit the value of services.freepbx.image in the docker-compose.yaml by setting the proper image version and tag
sed -i '/image: escomputers\/freepbx:latest/ {
    s/^/    #/
    a\
    image: freepbx:your-tag
}' docker-compose.yaml
```

2. Option B: if you want to use the pre-built image on Docker Hub, jump to the next step directly

3. Configure RTP ports on the host and build + run the Compose project:
```bash
# If you want to override the default RTP port range (16384-32767):
sudo bash run.sh --rtp 10000-20000
# otherwise simply run:
sudo bash run.sh

# Install Freepbx
sudo bash run.sh --install-freepbx

# Optional, clean up containers, network and volumes
sudo bash run.sh --clean-all
```

Login to the web server's admin URL, enter your admin username, admin password and email address and start configuring the system!
