#!/bin/bash
set -e

echo "🧹 Cleaning up Kubernetes, Docker and Port-Forwards..."

# === Port-Forward Prozesse beenden ===
echo "→ Killing running port-forward processes..."

PORT_FORWARD_PIDS=$(pgrep -f "kubectl port-forward") || true
if [[ -n "$PORT_FORWARD_PIDS" ]]; then
  echo "$PORT_FORWARD_PIDS" | xargs kill -9
  echo "   → kubectl port-forward Prozesse beendet: $PORT_FORWARD_PIDS"
else
  echo "   → Keine laufenden kubectl port-forward Prozesse."
fi

LBRUSAAPP_LOOP_PID=$(pgrep -f "lbrusaapp-portforward.sh") || true
if [[ -n "$LBRUSAAPP_LOOP_PID" ]]; then
  kill -9 $LBRUSAAPP_LOOP_PID
  echo "   → lbrusaapp-PortForward-Loop beendet: $LBRUSAAPP_LOOP_PID"
else
  echo "   → Kein lbrusaapp-PortForward-Loop gefunden."
fi

# === Logs & Hilfsskripte löschen ===
echo "→ Removing log and helper files..."
rm -f lbrusaapp-forward.log lbrusaapp-portforward.sh 2>/dev/null || true

# === Docker Container stoppen ===
RUNNING_CONTAINERS=$(docker ps -q)
if [[ -n "$RUNNING_CONTAINERS" ]]; then
  echo "→ Stopping running Docker containers..."
  docker stop $RUNNING_CONTAINERS
else
  echo "→ No running Docker containers."
fi

# === Docker Container entfernen ===
ALL_CONTAINERS=$(docker ps -aq)
if [[ -n "$ALL_CONTAINERS" ]]; then
  echo "→ Removing Docker containers..."
  docker rm $ALL_CONTAINERS
else
  echo "→ No Docker containers to remove."
fi

# === Docker Images entfernen ===
ALL_IMAGES=$(docker images -q | sort -u)
if [[ -n "$ALL_IMAGES" ]]; then
  echo "→ Removing Docker images..."
  docker rmi -f $ALL_IMAGES || true
else
  echo "→ No Docker images to remove."
fi

# === Docker Volumes entfernen ===
ALL_VOLUMES=$(docker volume ls -q)
if [[ -n "$ALL_VOLUMES" ]]; then
  echo "→ Removing Docker volumes..."
  docker volume rm $ALL_VOLUMES
else
  echo "→ No Docker volumes to remove."
fi

# === Docker Netzwerke entfernen ===
CUSTOM_NETWORKS=$(docker network ls --format '{{.Name}}' | grep -vE 'bridge|host|none')
if [[ -n "$CUSTOM_NETWORKS" ]]; then
  echo "→ Removing custom Docker networks..."
  docker network rm $CUSTOM_NETWORKS
else
  echo "→ No custom Docker networks to remove."
fi

# === k3d Cluster entfernen ===
K3D_CLUSTERS=$(k3d cluster list -o json | jq -r '.[].name') || true
if [[ -n "$K3D_CLUSTERS" ]]; then
  echo "→ Deleting k3d clusters..."
  for cluster in $K3D_CLUSTERS; do
    echo "   - Removing cluster: $cluster"
    k3d cluster delete "$cluster"
  done
else
  echo "→ No k3d clusters to delete."
fi

# === Kubeconfig aufräumen ===
KUBECONFIG_DIR="${HOME}/.k3d/kubeconfig"
if [[ -d "$KUBECONFIG_DIR" ]]; then
  echo "→ Removing kubeconfigs in $KUBECONFIG_DIR..."
  rm -f "$KUBECONFIG_DIR"/*.yaml
else
  echo "→ No kubeconfig dir found at $KUBECONFIG_DIR"
fi

echo "✅ Environment cleanup complete! ✨"
