#!/usr/bin/env bash
set -euo pipefail

# WireGuard Hub installer for OpenCloudOS / OpenAnolis-like servers.
# Run as root on the public server.
# This script installs WireGuard tooling, enables IPv4 forwarding, and prepares
# /etc/wireguard. It does NOT overwrite an existing /etc/wireguard/wg0.conf.

WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/wg0.conf"
SYSCTL_FILE="/etc/sysctl.d/99-remote-pc-bridge.conf"
WG_PORT="${WG_PORT:-51820}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root" >&2
  exit 1
fi

echo "==> Installing WireGuard packages"
if command -v dnf >/dev/null 2>&1; then
  dnf install -y epel-release || true
  dnf install -y wireguard-tools iptables iproute
elif command -v yum >/dev/null 2>&1; then
  yum install -y epel-release || true
  yum install -y wireguard-tools iptables iproute
elif command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y wireguard iptables iproute2
else
  echo "ERROR: unsupported package manager. Install wireguard-tools manually." >&2
  exit 1
fi

echo "==> Enabling IPv4 forwarding"
cat > "${SYSCTL_FILE}" <<'EOF'
net.ipv4.ip_forward = 1
EOF
sysctl --system >/dev/null

echo "==> Preparing ${WG_DIR}"
install -d -m 700 "${WG_DIR}"

if [[ ! -f "${WG_DIR}/server_private.key" ]]; then
  echo "==> Generating server WireGuard keypair"
  umask 077
  wg genkey | tee "${WG_DIR}/server_private.key" | wg pubkey > "${WG_DIR}/server_public.key"
else
  echo "==> Existing server keypair found; not regenerating"
fi

if [[ ! -f "${WG_CONF}" ]]; then
  echo "==> Creating placeholder ${WG_CONF}"
  SERVER_PRIVATE_KEY="$(cat "${WG_DIR}/server_private.key")"
  cat > "${WG_CONF}" <<EOF
[Interface]
Address = 10.66.0.1/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
SaveConfig = false

# Add peers after generating A/B public keys.
# Example:
# [Peer]
# PublicKey = <A_PUBLIC_KEY>
# AllowedIPs = 10.66.0.2/32
# PersistentKeepalive = 25
#
# [Peer]
# PublicKey = <B_PUBLIC_KEY>
# AllowedIPs = 10.66.0.3/32
# PersistentKeepalive = 25
EOF
  chmod 600 "${WG_CONF}"
else
  echo "==> Existing ${WG_CONF} found; not overwriting"
fi

echo "==> Server public key:"
cat "${WG_DIR}/server_public.key"

echo "==> Next steps:"
echo "1. Open UDP ${WG_PORT} in Tencent Cloud security group."
echo "2. Generate client keys on A/B Windows clients."
echo "3. Add A/B public keys as [Peer] sections in ${WG_CONF}."
echo "4. Start WireGuard: systemctl enable --now wg-quick@wg0"
