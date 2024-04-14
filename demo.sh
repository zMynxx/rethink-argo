#!/bin/sh set -ex

# Apply the prerequisites (e.g. namespace, repository)
kubectl apply -f preq/

# Apply the sops key for ksops to work properly
cat ksops/secrets/keys.txt | kubectl create secret generic sops-age --namespace=argocd --from-file=keys.txt=/dev/stdin

# Apply the ArgoCD manifests using kustomize and kubectl
kustomize build bootstrap/argo-cd | kubectl apply -f -

# Wait for the ArgoCD server to be ready
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=300s

# Update the password for the developer and devops accounts
kubectl port-forward svc/argocd-server -n argocd 8081:80 &
argocd login localhost:8081 --username admin --grpc-web-root-path / --insecure --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
argocd account update-password --account developer --current-password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --new-password dev12345
argocd account update-password --account devops --current-password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --new-password ops12345

# Disable the admin account
kubectl patch cm argocd-cm -n argocd --type merge --patch '{"data": {"accounts.admin.enabled": "false"}}'

# Delete the port-forward process
kill $(lsof -t -i:8081)

# Create the applications
kubectl apply -f bootstrap/
