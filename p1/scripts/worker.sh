#!/bin/sh

echo "🌐 Configuring K3s worker node..."

# Wait for eth1 (private network)
while ! ip a show eth1 | grep -q 'inet '; do
  echo "⏳ Waiting for eth1 to be ready..."
  sleep 1
done

PRIVATE_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Wait for shared token and server IP
while [ ! -f /vagrant/shared/token ] || [ ! -f /vagrant/shared/server-ip ]; do
  echo "🔄 Waiting for /vagrant/shared/token and /server-ip..."
  sleep 2
done

K3S_TOKEN=$(cat /vagrant/shared/token)
K3S_URL="https://$(cat /vagrant/shared/server-ip):6443"

# Configure node IP and flannel interface
mkdir -p /etc/rancher/k3s
cat <<EOF > /etc/rancher/k3s/config.yaml
node-ip: $PRIVATE_IP
flannel-iface: eth1
EOF

# Join the cluster
echo "🚀 Joining cluster at $K3S_URL with IP $PRIVATE_IP"
curl -sfL https://get.k3s.io | K3S_URL=$K3S_URL K3S_TOKEN=$K3S_TOKEN sh -
