#!/usr/bin/env bash

# FreePBX Docker - Restore RTP Rules
# Usage: sudo bash /opt/freepbx-docker/restore-rtp-rules.sh

FREEPBX_IP="172.20.0.20"
RTP_START="10000"
RTP_END="20000"
EGRESS_IFACE=$(ip -o -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')

if [[ -z "$EGRESS_IFACE" ]]; then
  echo "ERROR: Could not detect network interface"
  exit 1
fi

echo "========================================"
echo "  Restoring FreePBX RTP Rules"
echo "========================================"
echo "  FreePBX IP:  $FREEPBX_IP"
echo "  RTP Ports:   $RTP_START-$RTP_END"
echo "  Interface:   $EGRESS_IFACE"
echo "========================================"
echo ""

# Check if nftables is active
if systemctl is-active --quiet nftables; then
  echo "Using nftables..."
  
  # Check if chains exist
  if ! sudo nft list chain ip filter DOCKER-USER &>/dev/null; then
    echo "Creating DOCKER-USER chain..."
    sudo nft add chain ip filter DOCKER-USER '{ type filter hook forward priority -1; policy accept; }'
  fi
  
  # Add rules (remove duplicates first)
  sudo nft delete rule ip filter DOCKER-USER udp dport $RTP_START-$RTP_END ip daddr $FREEPBX_IP accept 2>/dev/null || true
  sudo nft add rule ip filter DOCKER-USER udp dport $RTP_START-$RTP_END ip daddr $FREEPBX_IP accept
  echo "✓ DOCKER-USER rule added"
  
  # NAT rule
  if ! sudo nft list chain ip nat PREROUTING &>/dev/null; then
    echo "Creating PREROUTING chain..."
    sudo nft add chain ip nat PREROUTING '{ type nat hook prerouting priority -100; policy accept; }'
  fi
  
  sudo nft delete rule ip nat PREROUTING iifname "$EGRESS_IFACE" udp dport $RTP_START-$RTP_END dnat to $FREEPBX_IP 2>/dev/null || true
  sudo nft add rule ip nat PREROUTING iifname "$EGRESS_IFACE" udp dport $RTP_START-$RTP_END dnat to $FREEPBX_IP
  echo "✓ NAT PREROUTING rule added"
  
else
  echo "Using iptables..."
  
  # Remove existing rules
  sudo iptables -D DOCKER-USER -p udp -d $FREEPBX_IP --dport $RTP_START:$RTP_END -j ACCEPT 2>/dev/null || true
  sudo iptables -t nat -D PREROUTING -i $EGRESS_IFACE -p udp --dport $RTP_START:$RTP_END -j DNAT --to-destination $FREEPBX_IP:$RTP_START-$RTP_END 2>/dev/null || true
  
  # Add rules
  sudo iptables -I DOCKER-USER -p udp -d $FREEPBX_IP --dport $RTP_START:$RTP_END -j ACCEPT
  echo "✓ DOCKER-USER rule added"
  
  sudo iptables -t nat -A PREROUTING -i $EGRESS_IFACE -p udp --dport $RTP_START:$RTP_END -j DNAT --to-destination $FREEPBX_IP:$RTP_START-$RTP_END
  echo "✓ NAT PREROUTING rule added"
fi

echo ""
echo "✓ RTP rules restored successfully"
echo ""
echo "Verify with:"
if systemctl is-active --quiet nftables; then
  echo "  sudo nft list ruleset | grep -A2 -B2 10000"
else
  echo "  sudo iptables -L DOCKER-USER -v -n"
  echo "  sudo iptables -t nat -L PREROUTING -v -n"
fi
