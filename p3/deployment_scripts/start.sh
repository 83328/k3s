#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# k3d + Argo CD bootstrap + app deploy + stable port-forwards (single file)
# ==============================================================================
# What this script does (in order):
# 1) Installs docker, k3d, kubectl, argocd (if missing).
# 2) Creates/ensures a k3d cluster and sets KUBECONFIG/context.
# 3) Creates namespaces and installs Argo CD.
# 4) Waits for the Argo CD server Pod to be Running.
# 5) Starts an Argo CD port-forward on a free local port (default 8080+).
# 6) Prints Argo CD admin password and external URL.
# 7) Pauses so you can log in and sync in Argo CD.
# 8) Applies your application manifest.
# 9) Waits for the app Service to exist.
# 10) Starts a resilient port-forward to your Service (auto-restarts).
# 11) Prints final access info and the commands to stop the forwards.
#
# NOTE:
# - This preserves your original working behavior (svc/argocd-server:443,
#   svc/lbrusaapp:8888), just consolidated and documented.
# - If your kubectl binds only to localhost, use the localhost URLs.
# ==============================================================================

# --- Configuration (adjust as needed) ----------------------------------------
CLUSTER_NAME="iot-cluster"
K3D_CONFIG="./k3d-cluster.yaml"

ARGO_NS="argocd"
APP_NS="dev"

ARGOCD_SERVICE="argocd-server"
APP_MANIFEST_PATH="../manifests/application.yaml"  # change if your path differs

LBRUSAAPP_SERVICE="lbrusaapp"
LBRUSAAPP_REMOTE_PORT=8888     # remote Service port to forward to
LBRUSAAPP_LOCAL_PORT=9999      # local port to expose

# --- Logging helpers ----------------------------------------------------------
log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn(){ echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

# --- Dependency checks/installs ----------------------------------------------
check_bin() {
  command -v "$1" >/dev/null 2>&1 || { err "$1 is not installed"; exit 1; }
}

install_tools() {
  log "Installing required tools (if missing)..."

  if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | bash
  fi

  if ! command -v k3d &>/dev/null; then
    log "Installing k3d..."
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  fi

  if ! command -v kubectl &>/dev/null; then
    log "Installing kubectl..."
    curl -LO "https://dl.k8s.io/release/$(curl -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
  fi

  if ! command -v argocd &>/dev/null; then
    log "Installing Argo CD CLI..."
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 || echo "Are you using sudo?"
    chmod +x /usr/local/bin/argocd
  fi
}

# --- Cluster + Argo CD setup --------------------------------------------------
create_cluster() {
  log "Creating k3d cluster '${CLUSTER_NAME}' (idempotent)..."
  if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
    k3d cluster create --config "${K3D_CONFIG}"
  else
    log "Cluster '${CLUSTER_NAME}' already exists – skipping creation."
  fi

  # Set kubeconfig + context
  export KUBECONFIG="$(k3d kubeconfig write "${CLUSTER_NAME}")"
  kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
  log "KUBECONFIG set: $KUBECONFIG"

  # Quick connectivity check
  if ! kubectl cluster-info >/dev/null 2>&1; then
    err "Cannot access cluster '${CLUSTER_NAME}'"
    exit 1
  fi
  log "Current context: $(kubectl config current-context)"
}

install_argocd() {
  log "Creating namespaces..."
  kubectl create namespace "$ARGO_NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace "$APP_NS"  --dry-run=client -o yaml | kubectl apply -f -

  log "Installing Argo CD..."
  kubectl apply -n "$ARGO_NS" -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
}

wait_for_argocd() {
  log "Waiting for Argo CD server Pod to be Running..."
  until kubectl get pods -n "$ARGO_NS" -l "app.kubernetes.io/name=${ARGOCD_SERVICE}" \
        -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; do
    echo "   ...waiting for '${ARGOCD_SERVICE}' Pod"
    sleep 5
  done
  log "Argo CD server Pod is Running."
}

# --- Helpers ------------------------------------------------------------------
find_free_port() {
  local port=$1
  while lsof -i ":$port" >/dev/null 2>&1; do
    port=$((port + 1))
  done
  echo "$port"
}

# --- Main flow ---------------------------------------------------------------
main() {
  log "Starting stack setup..."

  # Essentials we use below
  check_bin curl
  check_bin grep

  # 1) Tools
  install_tools

  # 2) Cluster & context
  create_cluster

  # 3) Argo CD install + wait
  install_argocd
  wait_for_argocd

  # 4) Choose local ports
  local PORT_ARGOCD
  PORT_ARGOCD="$(find_free_port 8080)"
  log "Ports:"
  echo "   → Argo CD: $PORT_ARGOCD"
  echo "   → ${LBRUSAAPP_SERVICE}: $LBRUSAAPP_LOCAL_PORT"

  # 5) Start Argo CD port-forward (Service 443 → local free port)
  log "Starting Argo CD port-forward (https://<VM>:${PORT_ARGOCD})..."
  # If your kubectl only binds to localhost, the IP URL won't respond—use localhost URL below.
  kubectl port-forward svc/"$ARGOCD_SERVICE" -n "$ARGO_NS" "${PORT_ARGOCD}:443" --address 0.0.0.0 >/dev/null 2>&1 &
  PORT_FORWARD_ARGOCD_PID=$!
  echo "   → Argo CD port-forward PID: $PORT_FORWARD_ARGOCD_PID"

  # 6) Show Argo CD credentials
  local VM_IP
  VM_IP="$(hostname -I | awk '{print $1}')"
  echo ""
  log "Argo CD is up!"
  echo "👉 Web UI (IP):       https://${VM_IP}:${PORT_ARGOCD}"
  echo "👉 Web UI (localhost): https://localhost:${PORT_ARGOCD}"
  echo "👉 User:              admin"
  echo -n "👉 Password:          "
  kubectl -n "$ARGO_NS" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo ""

  # 7) Manual pause for Argo CD login/sync
  echo ""
  read -p "⏸️  Press [ENTER] after you've logged into Argo CD and synced your apps..."

  # 8) Deploy application manifest
  log "Applying application manifest..."
  if [[ -f "$APP_MANIFEST_PATH" ]]; then
    kubectl apply -f "$APP_MANIFEST_PATH" --validate=false
  else
    err "File not found: '$APP_MANIFEST_PATH'"
    exit 1
  fi

  # 9) Wait for app Service
  log "Waiting for Service '${LBRUSAAPP_SERVICE}' in namespace '${APP_NS}'..."
  until kubectl get svc "$LBRUSAAPP_SERVICE" -n "$APP_NS" >/dev/null 2>&1; do
    echo "   ...waiting for Service"
    sleep 5
  done

  # 10) Stable port-forward for your app (auto-restarts on failure)
  log "Starting resilient port-forward for ${LBRUSAAPP_SERVICE} (http://${VM_IP}:${LBRUSAAPP_LOCAL_PORT} → ${LBRUSAAPP_REMOTE_PORT})..."
  cat <<EOF > lbrusaapp-portforward.sh
#!/usr/bin/env bash
set -e
while true; do
  echo "[\$(date)] starting port-forward..." >> lbrusaapp-forward.log
  kubectl port-forward svc/${LBRUSAAPP_SERVICE} -n ${APP_NS} ${LBRUSAAPP_LOCAL_PORT}:${LBRUSAAPP_REMOTE_PORT} --address 0.0.0.0 >> lbrusaapp-forward.log 2>&1 || true
  echo "[\$(date)] port-forward crashed. restarting in 3s..." >> lbrusaapp-forward.log
  sleep 3
done
EOF
  chmod +x lbrusaapp-portforward.sh
  nohup ./lbrusaapp-portforward.sh >/dev/null 2>&1 &
  PORT_FORWARD_LBRUSAAPP_PID=$!
  echo "   → ${LBRUSAAPP_SERVICE} port-forward PID: $PORT_FORWARD_LBRUSAAPP_PID"

  # 11) Quick probe
  sleep 2
  log "Probe: http://${VM_IP}:${LBRUSAAPP_LOCAL_PORT}"
  curl "http://${VM_IP}:${LBRUSAAPP_LOCAL_PORT}" || warn "${LBRUSAAPP_SERVICE} has not responded yet (may be normal right after deploy)."

  # 12) Final info
  echo ""
  log "All set! ✅"
  echo "👉 Argo CD Web UI:     https://${VM_IP}:${PORT_ARGOCD}   (or https://localhost:${PORT_ARGOCD})"
  echo "👉 ${LBRUSAAPP_SERVICE}:        http://${VM_IP}:${LBRUSAAPP_LOCAL_PORT}"
  echo ""
  echo "💡 Port-forwards are running in the background."
  echo "💡 ${LBRUSAAPP_SERVICE} forward auto-restarts if it crashes (logs: lbrusaapp-forward.log)."
  echo ""
  echo "🛑 Stop port-forwards with:"
  echo "   kill ${PORT_FORWARD_ARGOCD_PID} ${PORT_FORWARD_LBRUSAAPP_PID}"
  echo ""
}

main "$@"
