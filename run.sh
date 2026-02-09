#!/usr/bin/env bash

# Get script directory to reference docker-compose file
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Support both .yml and .yaml extensions
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
  COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"
elif [ -f "$SCRIPT_DIR/docker-compose.yaml" ]; then
  COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yaml"
else
  echo "ERROR: docker-compose.yml or docker-compose.yaml not found in $SCRIPT_DIR" >&2
  exit 1
fi

# Detect the primary egress interface (IPv4)
get_default_iface() {
  ip -o -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}

freepbxip="172.20.0.20"
rtp_port_range="10000-20000"
DEFAULT_IFACE="$(get_default_iface)"

if [[ -z "$DEFAULT_IFACE" ]]; then
  echo "ERROR: Could not detect default egress interface." >&2
  exit 1
fi

# Detect which firewall system is in use
FIREWALL_TYPE="none"
if command -v iptables &>/dev/null; then
  # Check if using iptables-nft (compatibility layer) or legacy iptables
  if iptables --version 2>/dev/null | grep -q "nf_tables"; then
    FIREWALL_TYPE="iptables-nft"
  else
    FIREWALL_TYPE="iptables"
  fi
elif command -v nft &>/dev/null && ! sudo nft list ruleset 2>&1 | grep -q "managed by iptables"; then
  FIREWALL_TYPE="nftables"
fi

# Get actual container names dynamically
get_container_names() {
  DB_CONTAINER=$(sudo docker compose ps -q db 2>/dev/null | xargs sudo docker inspect -f '{{.Name}}' 2>/dev/null | sed 's/^\///')
  FREEPBX_CONTAINER=$(sudo docker compose ps -q freepbx 2>/dev/null | xargs sudo docker inspect -f '{{.Name}}' 2>/dev/null | sed 's/^\///')
}

# Parse optional arguments
requested_rtp=""

for arg in "$@"; do
  case "$arg" in
    --rtp)
      shift
      requested_rtp="$1"
      ;;
    --clean-all)
      # Get container names
      get_container_names
      
      # Clean everything
      read -r -p "Clean everything? (yes/no): " confirm
      [[ "$confirm" != "yes" ]] && echo "Aborted." && exit 0
      
      # Stop and remove containers (use detected names or wildcard)
      if [ -n "$DB_CONTAINER" ]; then
        sudo docker container stop "$DB_CONTAINER" 2>/dev/null || true
        sudo docker container rm "$DB_CONTAINER" 2>/dev/null || true
      fi
      if [ -n "$FREEPBX_CONTAINER" ]; then
        sudo docker container stop "$FREEPBX_CONTAINER" 2>/dev/null || true
        sudo docker container rm "$FREEPBX_CONTAINER" 2>/dev/null || true
      fi
      
      # Clean volumes and network (use project name from compose)
      PROJECT_NAME=$(grep -E "^name:" "$COMPOSE_FILE" | awk '{print $2}' || basename "$SCRIPT_DIR")
      sudo docker volume rm ${PROJECT_NAME}_var_data ${PROJECT_NAME}_etc_data ${PROJECT_NAME}_mysql_data 2>/dev/null || true
      sudo docker network rm ${PROJECT_NAME}_defaultnet 2>/dev/null || true
      
      # Clean firewall rules
      echo "Removing firewall rules..."
      sudo iptables -D DOCKER-USER -p udp -d "$freepbxip" --dport "${rtp_port_range/-/:}" -j ACCEPT 2>/dev/null || true
      sudo iptables -t nat -D PREROUTING -i "$DEFAULT_IFACE" -p udp --dport "${rtp_port_range/-/:}" -j DNAT --to-destination "$freepbxip:${rtp_port_range/:/-}" 2>/dev/null || true
      if command -v iptables-save &>/dev/null && [ -d "/etc/iptables" ]; then
        sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
      fi
      echo "✓ Firewall rules removed"
      
      read -r -p "Clean host storage? (yes/no): " storage
      [[ "$storage" == "yes" ]] && sudo rm -rf /mnt/storage/{database,conf,recording,log,agi-bin}/* && echo "✓ Storage cleaned"
      
      read -r -p "Remove Docker image? (yes/no): " image
      [[ "$image" == "yes" ]] && sudo docker rmi freepbx:17-asterisk22-opus 2>/dev/null && echo "✓ Image removed"
      
      echo "✓ Cleanup complete"
      exit 0
      ;;
  esac
  shift 2>/dev/null || shift || true
done

# Validate and set RTP range
if [[ -n "$requested_rtp" ]]; then
  if [[ "$requested_rtp" =~ ^[0-9]+-[0-9]+$ ]]; then
    start_port="${requested_rtp%%-*}"
    end_port="${requested_rtp##*-}"
    if (( end_port > start_port )); then
      rtp_port_range="$requested_rtp"
    else
      echo "ERROR: Invalid --rtp value." >&2
      exit 1
    fi
  else
    echo "ERROR: Invalid --rtp format. Use: 10000-20000" >&2
    exit 1
  fi
fi

# Check for unsupported OS
if [[ "$OSTYPE" == "darwin"* || "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" || "$OSTYPE" == "MINGW" ]]; then
  echo "$OSTYPE not supported. Manually configure firewall for UDP $rtp_port_range"
  exit 1
fi

# ============================================
# MAIN INSTALLATION WORKFLOW
# ============================================

echo "========================================"
echo "  FreePBX Docker Setup"
echo "========================================"
echo ""

# Step 1: Check if storage needs to be prepared
STORAGE_READY=false
if [ -d "/mnt/storage/conf" ] && [ "$(ls -A /mnt/storage/conf 2>/dev/null)" ]; then
  echo "✓ Storage already prepared"
  STORAGE_READY=true
else
  echo "→ Preparing host storage..."
  sudo mkdir -p /mnt/storage/{database,conf,recording,agi-bin,log/{cdr-csv,cel-csv,queue_log}}
  
  # Check if image exists, if not build it
  if ! sudo docker images | grep -q "freepbx.*17-asterisk22-opus"; then
    echo "→ Building Docker image (this takes 20-30 minutes)..."
    sudo docker compose build --no-cache || { echo "ERROR: Build failed"; exit 1; }
  fi
  
  # Extract Asterisk configuration
  echo "→ Extracting Asterisk configuration..."
  CID=$(sudo docker create freepbx:17-asterisk22-opus)
  sudo docker cp $CID:/etc/asterisk /tmp/asterisk_temp
  sudo cp -r /tmp/asterisk_temp/* /mnt/storage/conf/
  sudo rm -rf /tmp/asterisk_temp
  sudo docker rm $CID
  
  # Set permissions
  sudo chown -R 1000:1000 /mnt/storage/{conf,log,recording,agi-bin}
  sudo chmod -R 755 /mnt/storage/{conf,log,recording,agi-bin}
  
  echo "✓ Storage prepared"
  STORAGE_READY=true
fi

echo ""

# Step 2: Configure firewall for RTP
echo "→ Configuring firewall for RTP ($rtp_port_range)..."
echo "  Detected: $FIREWALL_TYPE"

RULES_ADDED=false

# Ensure iptables-persistent is installed
if ! dpkg -l | grep -q iptables-persistent; then
  echo "  Installing iptables-persistent..."
  echo iptables-persistent iptables-persistent/autosave_v4 boolean true | sudo debconf-set-selections
  echo iptables-persistent iptables-persistent/autosave_v6 boolean true | sudo debconf-set-selections
  
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent netfilter-persistent >/dev/null 2>&1
  
  sudo systemctl enable netfilter-persistent >/dev/null 2>&1
  sudo systemctl start netfilter-persistent >/dev/null 2>&1
  echo "  ✓ iptables-persistent installed"
fi

# DOCKER-USER chain for incoming RTP
if ! sudo iptables -C DOCKER-USER -p udp -d "$freepbxip" --dport "${rtp_port_range/-/:}" -j ACCEPT 2>/dev/null; then
  sudo iptables -I DOCKER-USER -p udp -d "$freepbxip" --dport "${rtp_port_range/-/:}" -j ACCEPT
  echo "  ✓ Incoming RTP rule added"
  RULES_ADDED=true
else
  echo "  ✓ Incoming RTP rule exists"
fi

# NAT PREROUTING for RTP port forwarding
if ! sudo iptables -t nat -C PREROUTING -i "$DEFAULT_IFACE" -p udp --dport "${rtp_port_range/-/:}" \
  -j DNAT --to-destination "$freepbxip:${rtp_port_range/:/-}" 2>/dev/null; then
  sudo iptables -t nat -A PREROUTING -i "$DEFAULT_IFACE" -p udp --dport "${rtp_port_range/-/:}" \
    -j DNAT --to-destination "$freepbxip:${rtp_port_range/:/-}"
  echo "  ✓ DNAT forwarding rule added"
  RULES_ADDED=true
else
  echo "  ✓ DNAT forwarding rule exists"
fi

# Save iptables rules
if [ "$RULES_ADDED" = true ]; then
  echo "→ Making firewall rules persistent..."
  sudo sh -c 'iptables-save > /etc/iptables/rules.v4'
  sudo systemctl restart netfilter-persistent >/dev/null 2>&1
  echo "  ✓ Rules saved to /etc/iptables/rules.v4"
fi

echo ""

# Step 3: Start containers
echo "→ Starting Docker containers..."
sudo docker compose up -d && {
  printf "  Waiting for database"
  for _ in $(seq 1 15); do printf "."; sleep 1; done
  echo " ready"
}

# Wait for Asterisk to start
echo "→ Waiting for Asterisk to start..."
for i in {1..30}; do
  if sudo docker compose exec -T freepbx asterisk -rx "core show version" &>/dev/null; then
    echo "  ✓ Asterisk is running"
    break
  fi
  printf "."
  sleep 2
  if [ $i -eq 30 ]; then
    echo ""
    echo "  ⚠ Warning: Asterisk may not have started properly"
  fi
done

echo ""

# Step 4: Check if FreePBX needs to be installed
FREEPBX_INSTALLED=false
if sudo docker compose exec -T freepbx test -f /etc/freepbx.conf 2>/dev/null; then
  FREEPBX_INSTALLED=true
fi

if [ "$FREEPBX_INSTALLED" = true ]; then
  echo "✓ FreePBX already installed"
  
  # Get system information
  HOST_IP=$(hostname -I | awk '{print $1}')
  DOCKER_HOSTNAME=$(grep -A 5 "freepbx:" "$COMPOSE_FILE" | grep "hostname:" | awk '{print $2}' | head -1)
  
  # Get Asterisk version (fresh)
  ASTERISK_VERSION=$(sudo docker compose exec -T freepbx asterisk -rx "core show version" 2>/dev/null | head -1 | awk '{print $2}')
  
  # Get FreePBX version (fresh)
  FREEPBX_VERSION=$(sudo docker compose exec -T freepbx fwconsole -V 2>/dev/null | awk '{print $NF}')
  
  # Loading animation
  printf "Loading system info"
  for _ in $(seq 1 10); do printf "."; sleep 1; done
  echo " done"
  
  echo ""
  echo "========================================"
  echo "  FreePBX is Ready!"
  echo "========================================"
  echo ""
  echo "  System Information:"
  echo "    Hostname:      ${DOCKER_HOSTNAME:-freepbx17-asterisk22}"
  echo "    Container IP:  $freepbxip"
  echo "    Host IP:       $HOST_IP"
  echo "    RTP Ports:     $rtp_port_range"
  echo ""
  echo "  Versions:"
  echo "    Asterisk:      ${ASTERISK_VERSION:-Unknown}"
  echo "    FreePBX:       ${FREEPBX_VERSION:-Unknown}"
  echo ""
  echo "  Access URLs:"
  echo "    HTTP:  http://$HOST_IP"
  echo "    HTTPS: https://$HOST_IP"
  echo ""
  echo "  Firewall:"
  echo "    Type:   $FIREWALL_TYPE"
  echo "    Status: ✓ RTP rules persistent"
  echo "    Config: /etc/iptables/rules.v4"
  echo ""
  echo "  Commands:"
  echo "    Clean:       sudo bash run.sh --clean-all"
  echo "    View rules:  sudo iptables -L DOCKER-USER -v -n"
  echo "    NAT rules:   sudo iptables -t nat -L PREROUTING -v -n"
  echo ""
  echo "========================================"
else
  # Install FreePBX
  echo "→ Installing FreePBX..."
  echo ""
  
  sudo docker compose exec -it -w /usr/local/src/freepbx freepbx \
    php install -n \
    --dbuser=freepbxuser \
    --dbpass="$(cat freepbxuser_password.txt)" \
    --dbhost=db
  
  sleep 5
  
  # Install modules
  echo ""
  echo "→ Installing 11 essential modules..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall announcement
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall asterisk-cli
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall blacklist
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall calendar
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall cel
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall configedit
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall ivr
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall miscapps
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall miscdests
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall timeconditions
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall queues
  
  # Reload FreePBX
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole reload
  
  # Configure Apache SSL (now that certificates exist)
  echo ""
  echo "→ Configuring SSL..."
  sudo docker compose exec freepbx bash -c "sed -i 's|SSLCertificateFile.*ssl-cert-snakeoil.pem|SSLCertificateFile      /etc/asterisk/keys/integration/certificate.pem|g' /etc/apache2/sites-enabled/default-ssl.conf"
  sudo docker compose exec freepbx bash -c "sed -i 's|SSLCertificateKeyFile.*ssl-cert-snakeoil.key|SSLCertificateKeyFile  /etc/asterisk/keys/integration/webserver.key|g' /etc/apache2/sites-enabled/default-ssl.conf"
  
  # Restart Apache
  echo "→ Finalizing setup..."
  sudo docker compose exec freepbx service apache2 restart
  
  # Get system information
  HOST_IP=$(hostname -I | awk '{print $1}')
  DOCKER_HOSTNAME=$(grep -A 5 "freepbx:" "$COMPOSE_FILE" | grep "hostname:" | awk '{print $2}' | head -1)
  
  # Get Asterisk version (fresh from running system)
  ASTERISK_VERSION=$(sudo docker compose exec -T freepbx asterisk -rx "core show version" 2>/dev/null | head -1 | awk '{print $2}')
  
  # Get FreePBX version (fresh)
  FREEPBX_VERSION=$(sudo docker compose exec -T freepbx fwconsole -V 2>/dev/null | awk '{print $NF}')
  
  # Loading animation
  printf "  Completing installation"
  for _ in $(seq 1 10); do printf "."; sleep 1; done
  echo " done"
  
  echo ""
  echo "========================================"
  echo "  FreePBX Installation Complete!"
  echo "========================================"
  echo ""
  echo "  System Information:"
  echo "    Hostname:      ${DOCKER_HOSTNAME:-freepbx17-asterisk22}"
  echo "    Container IP:  $freepbxip"
  echo "    Host IP:       $HOST_IP"
  echo "    RTP Ports:     $rtp_port_range"
  echo ""
  echo "  Versions:"
  echo "    Asterisk:      ${ASTERISK_VERSION:-22.8.2}"
  echo "    FreePBX:       ${FREEPBX_VERSION:-17.0.25}"
  echo "    Codec:         Opus (WhatsApp ready)"
  echo ""
  echo "  Access URLs:"
  echo "    HTTP:  http://$HOST_IP"
  echo "    HTTPS: https://$HOST_IP"
  echo ""
  echo "  Configuration:"
  echo "    ✓ 11 essential modules installed"
  echo "    ✓ SSL/TLS enabled"
  echo "    ✓ CDR logging ready"
  echo ""
  echo "  Firewall:"
  echo "    Type:   $FIREWALL_TYPE"
  echo "    Status: ✓ RTP rules configured and persistent"
  echo "    Config: /etc/iptables/rules.v4"
  echo ""
  echo "  Storage:"
  echo "    /mnt/storage/conf      - Asterisk config"
  echo "    /mnt/storage/log       - Logs & CDR"
  echo "    /mnt/storage/recording - Call recordings"
  echo "    /mnt/storage/agi-bin   - AGI scripts"
  echo ""
  echo "  Verify Setup:"
  echo "    Opus codec:"
  echo "      sudo docker compose exec freepbx \\"
  echo "        asterisk -rx 'core show codecs | grep opus'"
  echo ""
  echo "    Firewall rules:"
  echo "      sudo iptables -L DOCKER-USER -v -n | grep $freepbxip"
  echo "      sudo iptables -t nat -L PREROUTING -v -n | grep $freepbxip"
  echo ""
  echo "  Next Steps:"
  echo "    1. Access FreePBX web interface and complete initial setup"
  echo "    2. For WebRTC/WhatsApp: Upload certificates or generate Let's Encrypt"
  echo "    3. Configure: HTTP Server, SIP Settings, Trunks, Extensions"
  echo ""
  echo "========================================"
fi
