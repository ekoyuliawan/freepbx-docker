#!/usr/bin/env bash



# Detect the primary egress interface (IPv4) by asking the kernel
# how it would reach the Internet
get_default_iface() {
  ip -o -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}'
}

freepbxip="172.18.0.20"
freepbx_network="172.18.0.0/16"
rtp_port_range="16384-32767"
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

# INSTALL FREEPBX
if [[  "$*" == *"--install-freepbx"*  ]]; then
    sudo docker compose exec -it -w /usr/local/src/freepbx freepbx php install -n --dbuser=freepbxuser --dbpass="$(cat freepbxuser_password.txt)" --dbhost=db

# CLEAN
elif [[  "$*" == *"--clean-all"*  ]]; then
  sudo docker container stop freepbx-docker-db-1 && sudo docker container rm freepbx-docker-db-1
  sudo docker container stop freepbx-docker-freepbx-1 && sudo docker container rm freepbx-docker-freepbx-1
  sudo docker volume rm freepbx-docker_var_data
  sudo docker volume rm freepbx-docker_usr_data
  sudo docker volume rm freepbx-docker_etc_data
  sudo docker volume rm freepbx-docker_asterisk_home
  sudo docker volume rm freepbx-docker_mysql_data
  sudo docker network rm freepbx-docker_defaultnet


# UNSUPPORTED HOST CASE
elif [[ "$OSTYPE" == "darwin"* || "$OSTYPE" == "cygwin" || "$OSTYPE" == "msys" || "$OSTYPE" == "MINGW" ]]; then
    echo "$OSTYPE currently not supported, please manually configure your host firewall to allow incoming and outgoing UDP traffic on the RTP port range: $rtp_port_range"

# Configure Iptables for RTP ports on Linux
else
    if [[  "$OSTYPE" == "linux-gnu"*  ]]; then
        echo "Configuring iptables rules for RTP ports"
          # Allow packets belonging to existing or related connections.
        # Check if the rule already exists in the DOCKER-USER chain (-C)
        # If it doesn't, it inserts the rule at the very top of the chain (-I 1).
        sudo iptables -C DOCKER-USER -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
        || sudo iptables -I DOCKER-USER 1 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT \
        && echo "Rule for conntrack packets added!"

        # Allow incoming UDP traffic to container on the RTP port range on the DOCKER-USER chain 
        # to ensure media packets are accepted before other rules are applied.
        sudo iptables -C DOCKER-USER -p udp -d "$freepbxip" --dport "${rtp_port_range/-/:}" -j ACCEPT 2>/dev/null \
        || sudo iptables -I DOCKER-USER 1 -p udp -d "$freepbxip" --dport "${rtp_port_range/-/:}" -j ACCEPT \
        && echo "Rule for incoming RTP traffic added!"

        # Allow outgoing UDP traffic from container using the RTP port range
        sudo iptables -C DOCKER-USER -p udp -s "$freepbxip" --sport "${rtp_port_range/-/:}" -j ACCEPT 2>/dev/null \
            || sudo iptables -I DOCKER-USER 1 -p udp -s "$freepbxip" --sport "${rtp_port_range/-/:}" -j ACCEPT \
            && echo "Rule for outgoing RTP traffic added!"

        # Destination NAT for RTP: forward inbound UDP traffic arriving on the default egress interface
        # and matching the RTP port range to the FreePBX host.
        sudo iptables -t nat -C PREROUTING -i "$DEFAULT_IFACE" -p udp --dport "${rtp_port_range/-/:}" \
            -j DNAT --to-destination "$freepbxip:${rtp_port_range/:/-}" 2>/dev/null \
            || sudo iptables -t nat -A PREROUTING -i "$DEFAULT_IFACE" -p udp --dport "${rtp_port_range/-/:}" \
            -j DNAT --to-destination "$freepbxip:${rtp_port_range/:/-}" && echo "Rule for Destination NAT RTP added!"

        # Enable NAT (masquerading) for all traffic originating from the Docker network,
        # when leaving through host interface by adding a rule to the POSTROUTING chain of the NAT table. 
        # This rewrites the source IP of outgoing packets to match the host's IP, 
        # allowing containers to access external networks.
        sudo iptables -t nat -C POSTROUTING -s "$freepbx_network" -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null \
            || sudo iptables -t nat -A POSTROUTING -s "$freepbx_network" -o "$DEFAULT_IFACE" -j MASQUERADE \
            && echo "Rule for Source NAT added!"

        # Build and start the Compose services
        sudo docker compose up -d --build
    fi

fi
