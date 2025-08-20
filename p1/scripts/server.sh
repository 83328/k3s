#!/bin/sh

echo "🌐 Configuring K3s server node..."

# Wait for private interface (eth1)
while ! ip a show eth1 | grep -q 'inet '; do
  echo "⏳ Waiting for eth1 to be ready..."
  sleep 1
done

PRIVATE_IP=$(ip -4 addr show eth1 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')

# Configure K3s with the correct IP/interface
mkdir -p /etc/rancher/k3s
cat <<EOF > /etc/rancher/k3s/config.yaml
node-ip: $PRIVATE_IP
advertise-address: $PRIVATE_IP
flannel-iface: eth1
EOF

# Install K3s server
curl -sfL https://get.k3s.io | sh -

# Wait for token to be generated
while [ ! -f /var/lib/rancher/k3s/server/node-token ]; do
  echo "⌛ Waiting for K3S token to be available..."
  sleep 2
done

# Wait for shared folder
while [ ! -d /vagrant/shared ]; do
  echo "⏳ Waiting for /vagrant/shared to mount..."
  sleep 1
done

# Save token and server IP for worker nodes
echo "💾 Saving K3S token and IP to /vagrant/shared..."
cat /var/lib/rancher/k3s/server/node-token > /vagrant/shared/token
echo "$PRIVATE_IP" > /vagrant/shared/server-ip
