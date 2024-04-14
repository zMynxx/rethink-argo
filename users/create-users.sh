#!/bin/sh set -ex
#
kubectl port-forward svc/argocd-server -n argocd 8081:80 &
argocd login localhost:8081 --username admin --grpc-web-root-path / --insecure --password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

# Create users
argocd account update-password --account developer --current-password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --new-password dev12345
argocd account update-password --account devops --current-password $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d) --new-password ops12345
