#!/usr/bin/env bash

echo "[INFO] Installing K3s server..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--node-ip=192.168.56.110 --write-kubeconfig-mode 644" sh -

echo "[INFO] Waiting for K3s to finish starting..."
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  sleep 1
done

# need to wait for this one too before changing the permissions
echo "[INFO] Waiting for K3s to finish starting..."
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
  sleep 1
done
sudo chmod 644 /etc/rancher/k3s/k3s.yaml

# Download kubecolor latest release for Linux
# KUBECOLOR_VERSION="0.0.25"
# wget -O /usr/local/bin/kubecolor https://github.com/hidetatz/kubecolor/releases/download/v${KUBECOLOR_VERSION}/kubecolor_Linux_x86_64
# chmod +x /usr/local/bin/kubecolor

# A script in profile.d (like /etc/profile.d/kubectl-alias.sh) is sourced automatically by most login shells (bash, zsh, etc.) 
# every time a user logs in or starts a new shell session.
echo "alias k='kubectl'" > /etc/profile.d/kubectl-alias.sh
chmod +x /etc/profile.d/kubectl-alias.sh

echo "[INFO] Ensuring shared folder exists..."
mkdir -p /vagrant

echo "[INFO] Saving token and server IP..."
cp /var/lib/rancher/k3s/server/node-token /vagrant/token
SERVER_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
echo "$SERVER_IP" > /vagrant/server-ip

echo "[INFO] Done."
echo "[INFO] Persisting eth1 static IP config in /etc/network/interfaces..."
cat <<EOF | sudo tee -a /etc/network/interfaces
auto eth1
iface eth1 inet static
    address 192.168.56.110
    netmask 255.255.255.0
EOF

sudo ifup eth1
