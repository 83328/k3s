#!/usr/bin/env bash
set -euo pipefail

NS_ING="ingress-nginx"
NS_GL="gitlab"
NS_ARGO="argocd"
K3D_CLUSTER_NAME="iot-cluster"

echo "[*] Deleting Argo Application (optional)…"
kubectl delete -f "$(dirname "$0")/../confs/argocd-app-from-gitlab.yaml" --ignore-not-found || true

echo "[*] Deleting hostless ingresses…"
kubectl -n gitlab delete ingress gitlab-hostless --ignore-not-found || true
kubectl -n argocd delete ingress argocd-hostless --ignore-not-found || true

echo "[*] Uninstalling Argo CD…"
helm uninstall argocd -n "${NS_ARGO}" || true
kubectl delete ns "${NS_ARGO}" --wait || true

echo "[*] Uninstalling GitLab…"
helm uninstall gitlab -n "${NS_GL}" || true
kubectl delete ns "${NS_GL}" --wait || true

echo "[*] Uninstalling ingress-nginx…"
helm uninstall ingress-nginx -n "${NS_ING}" || true
kubectl delete ns "${NS_ING}" --wait || true

echo "[*] Removing /etc/hosts entry (in VM guest) for gitlab.iot.local (manually, if desired)."

read -p "Should the k3d cluster '${K3D_CLUSTER_NAME}' also be deleted? [y/N]: " yn
if [[ "${yn:-N}" =~ ^[Yy]$ ]]; then
  k3d cluster delete "${K3D_CLUSTER_NAME}" || true
  echo "✅ k3d cluster deleted."
else
  echo "ℹ️  k3d cluster retained."
fi

echo "✅ Bonus teardown complete."