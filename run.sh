#!/usr/bin/env bash

# Detect the primary egress interface (IPv4) by asking the kernel
# how it would reach the Internet

get_default_iface() {
  ip -o -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}

freepbxip="172.20.0.20"
rtp_port_range="10000-20000" #16384-32767
DEFAULT_IFACE="$(get_default_iface)"
if [[ -z "$DEFAULT_IFACE" ]]; then
  echo "ERROR: Could not detect default egress interface." >&2
  exit 1
fi

# Parse optional --rtp RANGE argument without affecting other flags
# Supports only "--rtp 10000-20000"
requested_rtp=""
prev=""
for arg in "$@"; do
  if [[ "$prev" == "--rtp" ]]; then
    requested_rtp="$arg"
    prev=""
    continue
  fi
  case "$arg" in
    --rtp)
      prev="--rtp"
      ;;
  esac
done

if [[ -n "$prev" ]]; then
  echo "ERROR: --rtp requires a value like 10000-20000" >&2
  exit 1
fi

if [[ -n "$requested_rtp" ]]; then
  if [[ "$requested_rtp" =~ ^[0-9]+-[0-9]+$ ]]; then
    start_port="${requested_rtp%%-*}"
    end_port="${requested_rtp##*-}"
    if (( end_port > start_port )); then
      rtp_port_range="$requested_rtp"
    else
      echo "ERROR: Invalid --rtp value '$requested_rtp'. The right number must be greater than the left (e.g., 10000-20000)." >&2
      exit 1
    fi
  else
    echo "ERROR: Invalid --rtp value '$requested_rtp'. Use two integers separated by '-' (e.g., 10000-20000)." >&2
    exit 1
  fi
fi

# PREPARE STORAGE - Extract /etc/asterisk from image to host BEFORE mounting
if [[ "$*" == *"--prepare-storage"* ]]; then
  echo "========================================="
  echo "Preparing host storage for FreePBX..."
  echo "========================================="
  
  # Create directories
  sudo mkdir -p /mnt/storage/{database,conf,recording,log}
  
  # Check if /mnt/storage/conf is empty
  if [ -z "$(ls -A /mnt/storage/conf 2>/dev/null)" ]; then
    echo "Extracting Asterisk configuration from image..."
    
    # Create temporary container WITHOUT starting it
    CID=$(sudo docker create escomputers/freepbx:17)
    echo "Created temporary container: $CID"
    
    # Copy /etc/asterisk from image to host
    sudo docker cp $CID:/etc/asterisk /tmp/asterisk_temp
    sudo mv /tmp/asterisk_temp/* /mnt/storage/conf/
    sudo rmdir /tmp/asterisk_temp
    
    # Remove temporary container
    sudo docker rm $CID
    echo "✓ Configuration extracted successfully"
  else
    echo "✓ /mnt/storage/conf already contains files, skipping extraction"
  fi
  
  # Set proper ownership
  sudo chown -R $(id -u):$(id -g) /mnt/storage
  
  echo ""
  echo "========================================="
  echo "Storage preparation complete!"
  echo "========================================="
  echo "Now you can start containers with:"
  echo "  sudo bash run.sh"
  echo "Then install FreePBX with:"
  echo "  sudo bash run.sh --install-freepbx"
  echo "========================================="
  exit 0
fi

# INSTALL FREEPBX
if [[ "$*" == *"--install-freepbx"* ]]; then
  # Run FreePBX installation
  sudo docker compose exec -it -w /usr/local/src/freepbx freepbx php install -n --dbuser=freepbxuser --dbpass="$(cat freepbxuser_password.txt)" --dbhost=db
  
  # Wait for installation to complete
  echo "Waiting for FreePBX installation to complete..."
  sleep 10
  
  # Install essential modules
  echo "========================================="
  echo "Installing FreePBX Modules..."
  echo "========================================="
  
  echo "[1/11] Installing Announcements module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall announcement
  
  echo "[2/11] Installing Asterisk CLI module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall asterisk-cli
  
  echo "[3/11] Installing Blacklist module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall blacklist
  
  echo "[4/11] Installing Calendar module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall calendar
  
  echo "[5/11] Installing Call Event Logging module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall cel
  
  echo "[6/11] Installing Config Edit module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall configedit
  
  echo "[7/11] Installing IVR module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall ivr
  
  echo "[8/11] Installing Misc Applications module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall miscapps
  
  echo "[9/11] Installing Misc Destinations module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall miscdests
  
  echo "[10/11] Installing Time Conditions module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall timeconditions
  
  echo "[11/11] Installing Queues module..."
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole ma downloadinstall queues
  
  # Reload FreePBX configuration
  echo "========================================="
  echo "Reloading FreePBX configuration..."
  echo "========================================="
  sudo docker compose exec -w /usr/local/src/freepbx freepbx fwconsole reload
  
  # Install text editors
  echo "========================================="
  echo "Installing text editors (nano, vim)..."
  echo "========================================="
  sudo docker compose exec freepbx bash -c "apt-get update && apt-get install -y nano vim && apt-get clean && rm -rf /var/lib/apt/lists/*"
  echo "✓ Text editors installed"
  
  # Configure Apache SSL for WebRTC
  echo ""
  echo "========================================="
  echo "Configuring Apache SSL for WebRTC..."
  echo "========================================="
  
  echo "[1/4] Enabling Apache SSL module..."
  sudo docker compose exec freepbx a2enmod ssl
  echo "✓ SSL module enabled"
  
  echo "[2/4] Enabling default SSL site..."
  sudo docker compose exec freepbx a2ensite default-ssl
  echo "✓ Default SSL site enabled"
  
  echo "[3/4] Updating SSL certificate paths..."
  sudo docker compose exec freepbx bash -c "sed -i 's|SSLCertificateFile.*ssl-cert-snakeoil.pem|SSLCertificateFile      /etc/asterisk/keys/integration/certificate.pem|g' /etc/apache2/sites-enabled/default-ssl.conf"
  sudo docker compose exec freepbx bash -c "sed -i 's|SSLCertificateKeyFile.*ssl-cert-snakeoil.key|SSLCertificateKeyFile  /etc/asterisk/keys/integration/webserver.key|g' /etc/apache2/sites-enabled/default-ssl.conf"
  echo "✓ SSL certificate paths updated"
  
  echo "[4/4] Restarting Apache service..."
  sudo docker compose exec freepbx service apache2 restart
  echo "✓ Apache restarted successfully"
  
  echo ""
  echo "========================================="
  echo "FreePBX installation complete!"
  echo "========================================="
  echo "✓ All modules installed successfully"
  echo "✓ Text editors (nano, vim) available"
  echo "✓ Apache SSL configured for WebRTC"
  echo "✓ Configuration persisted to /mnt/storage/conf"
  echo ""
  echo "Access FreePBX:"
  echo "  HTTP:  http://$(hostname -I | awk '{print $1}')"
  echo "  HTTPS: https://$(hostname -I | awk '{print $1}')"
  echo "========================================="

# CLEAN
elif [[ "$*" == *"--clean-all"* ]]; then
  read -r -p "Are you sure you want to clean up everything? (yes/no)? " confirmation
  if [[ "$confirmation" != "yes" ]]; then
    echo "Cleanup aborted."
    exit 0
  fi
  
  sudo docker container stop freepbx-docker-db-1 && sudo docker container rm freepbx-docker-db-1
  sudo docker container stop freepbx-docker-freepbx-1 && sudo docker container rm freepbx-docker-freepbx-1
  sudo docker volume rm freepbx-docker_var_data 2>/dev/null || true
  sudo docker volume rm freepbx-docker_etc_data 2>/dev/null || true
  sudo docker volume rm freepbx-docker_mysql_data 2>/dev/null || true
  sudo docker network rm freepbx-docker_defaultnet 2>/dev/null || true
  
  # Ask about host storage cleanup
  read -r -p "Do you also want to clean host storage (/mnt/storage/*)? (yes/no)? " storage_confirm
  if [[ "$storage_confirm" == "yes" ]]; then
    echo "Cleaning host storage..."
    sudo rm -rf /mnt/storage/database/*
    sudo rm -rf /mnt/storage/conf/*
    sudo rm -rf /mnt/storage/recording/*
    sudo rm -rf /mnt/storage/log/*
    echo "✓ Host storage cleaned"
  fi

# UNSUPPORTED HOST CASE
elif [[ "$OSTYPE" == "darwin"* || "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" || "$OSTYPE" == "MINGW" ]]; then
  echo "$OSTYPE currently not supported, please manually configure your host firewall to allow incoming and outgoing UDP traffic on the RTP port range: $rtp_port_range"

# Configure Iptables for RTP ports on Linux
else
  if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Build and start the Compose services
    sudo docker compose up -d && {
      printf "Waiting for database readiness"
      for _ in $(seq 1 10); do printf "."; sleep 1; done
      echo " done"
    }
  fi
fi
