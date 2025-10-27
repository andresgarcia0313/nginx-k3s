#! /bin/bash
# 1. Ver detalles del challenge para saber qué está fallando
kubectl describe challenge -n nginx-namespace

# 2. Ver logs del pod solver de ACME
kubectl logs cm-acme-http-solver-xrtvh -n nginx-namespace

# 3. Ver logs de cert-manager para errores
kubectl logs -n cert-manager -l app=cert-manager --tail=100

# 4. Verificar que el ingress temporal del solver esté funcionando
kubectl describe ingress cm-acme-http-solver-qsv9q -n nginx-namespace

# 5. Probar si el endpoint del challenge es accesible desde fuera
# Let's Encrypt intentará acceder a esta URL:
curl -v http://nginx.negociapp.com/.well-known/acme-challenge/test
