#!/usr/bin/env bash
set -euo pipefail

# Always use a known kubeconfig path
export KUBECONFIG="${HOME}/.kube/config"

NS_ING="ingress-nginx"
NS_GL="gitlab"
NS_ARGO="argocd"

K3D_CLUSTER_NAME="iot-cluster"
K3D_CFG_BONUS="$(dirname "$0")/../confs/k3d-cluster-bonus.yaml"

log() { echo -e "\033[1;32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
err() { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; }

require() { command -v "$1" >/dev/null 2>&1 || { err "$1 not found"; exit 1; }; }

ensure_kubecontext() {
  mkdir -p "${HOME}/.kube"
  local backup="${HOME}/.kube/config.$(date +%Y%m%d-%H%M%S).bak"
  if [ -f "${HOME}/.kube/config" ]; then
    cp "${HOME}/.kube/config" "${backup}" || true
    warn "Backed up existing kubeconfig to ${backup}"
  fi
  # Fetch fresh kubeconfig from k3d
  k3d kubeconfig get "${K3D_CLUSTER_NAME}" > "${HOME}/.kube/config"
  # Switch context if present
  kubectl config use-context "k3d-${K3D_CLUSTER_NAME}" >/dev/null 2>&1 || true
  # Sanity checks
  kubectl cluster-info >/dev/null
  kubectl get nodes >/dev/null
  log "Kubernetes context is ready: $(kubectl config current-context || echo 'unknown')"
}

write_overrides_and_ingresses() {
  # Localhost overrides (force external host to localhost + disable cert-manager pieces)
  cat > "$(dirname "$0")/../confs/gitlab-overrides.yaml" <<'YAML'
# Force "localhost" externally and keep TLS/cert-manager off
global:
  hosts:
    gitlab:
      name: localhost
      https: false
    https: false
  ingress:
    configureCertmanager: false
    tls:
      enabled: false
  minio:
    enabled: true

installCertmanager: false
certmanager-issuer:
  enabled: false
  email: admin@example.com
YAML

  # Hostless GitLab Ingress that talks to webservice on 8181 and presents Host: localhost
  cat > "$(dirname "$0")/../confs/gitlab-hostless-ingress.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitlab-hostless
  namespace: gitlab
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "0"
    nginx.ingress.kubernetes.io/upstream-vhost: "localhost"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gitlab-webservice-default
                port:
                  number: 8181
YAML

  # Argo CD under /argocd (avoid path clash)
  cat > "$(dirname "$0")/../confs/argocd-hostless-ingress.yaml" <<'YAML'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-hostless
  namespace: argocd
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
    - http:
        paths:
          - path: /argocd
            pathType: Prefix
            backend:
              service:
                name: argocd-server
                port:
                  number: 80
YAML
}

main() {
  require kubectl
  require helm
  require k3d

  # 0) Ensure cluster exists
  if ! k3d cluster list | grep -q "^${K3D_CLUSTER_NAME}\b"; then
    log "Creating k3d cluster with bonus config (80/443 + 8888 mappings)..."
    k3d cluster create --config "${K3D_CFG_BONUS}"
  else
    log "Using existing k3d cluster '${K3D_CLUSTER_NAME}'"
  fi

  # 0.1) Ensure kube context
  ensure_kubecontext

  # 0.2) Ensure our overrides/ingresses are present (write/overwrite)
  write_overrides_and_ingresses

  # 1) Helm repos
  log "Adding/Updating Helm repos..."
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null 2>&1 || true
  helm repo add gitlab https://charts.gitlab.io --force-update >/dev/null 2>&1 || true
  helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null 2>&1 || true
  helm repo update >/dev/null

  # 2) Ingress NGINX
  log "Installing ingress-nginx..."
  kubectl create ns "${NS_ING}" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n "${NS_ING}" -f "$(dirname "$0")/../confs/ingress-nginx-values.yaml" >/dev/null
  kubectl wait --namespace ${NS_ING} --for=condition=available deploy/ingress-nginx-controller --timeout=240s >/dev/null

  # 3) GitLab
  log "Installing GitLab (this may take a few minutes)..."
  kubectl create ns "${NS_GL}" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install gitlab gitlab/gitlab \
    -n "${NS_GL}" \
    -f "$(dirname "$0")/../confs/gitlab-values.yaml" \
    -f "$(dirname "$0")/../confs/gitlab-overrides.yaml"

  kubectl rollout status deploy/gitlab-webservice-default -n "${NS_GL}" --timeout=20m

  # 4) Argo CD (with CRDs), under /argocd
  log "Installing Argo CD (with CRDs)..."
  kubectl create ns "${NS_ARGO}" --dry-run=client -o yaml | kubectl apply -f -
  helm upgrade --install argocd argo/argo-cd -n ${NS_ARGO} \
    --set installCRDs=true \
    --set server.extraArgs[0]=--insecure \
    --set server.extraArgs[1]=--basehref=/argocd \
    --set server.extraArgs[2]=--rootpath=/argocd >/dev/null
  kubectl -n ${NS_ARGO} rollout status deploy/argocd-server --timeout=10m

  # 5) Apply ingresses
  log "Applying hostless ingresses for GitLab & Argo CD ..."
  kubectl -n ${NS_GL} apply -f "$(dirname "$0")/../confs/gitlab-hostless-ingress.yaml"
  kubectl -n ${NS_ARGO} apply -f "$(dirname "$0")/../confs/argocd-hostless-ingress.yaml"

  # 6) Apply Argo CD Application pointing to local GitLab (repoURL expected to be localhost)
  if [ -f "$(dirname "$0")/../confs/argocd-app-from-gitlab.yaml" ]; then
    log "Applying Argo CD Application (repo -> local GitLab)..."
    kubectl apply -f "$(dirname "$0")/../confs/argocd-app-from-gitlab.yaml" || warn "Could not apply Argo CD Application (check CRDs/values)."
  fi

  # 7) Print root password robustly
  log "Reading GitLab initial root password..."
  for i in $(seq 1 60); do
    SEC=$(kubectl -n ${NS_GL} get secret -o name 2>/dev/null | grep -m1 "initial-root-password" || true)
    if [ -n "${SEC:-}" ]; then break; fi
    sleep 5
  done
  if [ -n "${SEC:-}" ]; then
    ROOT_PW=$(kubectl -n ${NS_GL} get "$SEC" -o jsonpath="{.data.password}" | base64 -d || true)
  fi

  cat <<EOF

✅ GitLab (in VM):      http://localhost
👤 Username:            root
🔑 Initial Password:    ${ROOT_PW:-<unbekannt>}

🔌 VirtualBox NAT-Forwarding (Port forwarding on the host machine):
  GitLab : Host 7777 -> Guest 80
  ArgoCD : Host 9090 -> Guest 80

🌍 Access from the host:
  GitLab : http://localhost:7777/
  Argo CD: http://localhost:9090/argocd
EOF
}

main "$@"