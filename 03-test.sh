#!/bin/bash

# Script de Validación Iterativa e Incremental para Kubernetes
# Valida namespace, deployment, service, ingress y certificados

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="nginx-namespace"
DEPLOYMENT="nginx"
SERVICE="nginx"
INGRESS="nginx"
CLUSTERISSUER="letsencrypt-prod"

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}  VALIDACIÓN ITERATIVA DE RECURSOS KUBERNETES${NC}"
echo -e "${BLUE}==================================================${NC}\n"

# Función para pausar entre validaciones
pausar() {
    echo -e "\n${YELLOW}Presiona ENTER para continuar...${NC}"
    read
}

# =================================================
# 1. VALIDACIÓN DEL NAMESPACE
# =================================================
echo -e "${BLUE}[1/8] Validando Namespace: ${NAMESPACE}${NC}"
echo "---------------------------------------------------"

if kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓ Namespace existe${NC}"
    kubectl get namespace $NAMESPACE
else
    echo -e "${RED}✗ Namespace NO existe${NC}"
    echo "Ejecuta: kubectl apply -f manifiesto-nginx.yml"
    exit 1
fi

pausar

# =================================================
# 2. VALIDACIÓN DEL DEPLOYMENT
# =================================================
echo -e "\n${BLUE}[2/8] Validando Deployment: ${DEPLOYMENT}${NC}"
echo "---------------------------------------------------"

if kubectl get deployment $DEPLOYMENT -n $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓ Deployment existe${NC}"
    kubectl get deployment $DEPLOYMENT -n $NAMESPACE

    echo -e "\n${YELLOW}Estado detallado del Deployment:${NC}"
    kubectl describe deployment $DEPLOYMENT -n $NAMESPACE | grep -A 5 "Replicas:"

    # Verificar réplicas listas
    DESIRED=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment $DEPLOYMENT -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')

    echo -e "\n${YELLOW}Réplicas deseadas: ${DESIRED} | Réplicas listas: ${READY}${NC}"

    if [ "$DESIRED" == "$READY" ]; then
        echo -e "${GREEN}✓ Todas las réplicas están listas${NC}"
    else
        echo -e "${RED}✗ No todas las réplicas están listas${NC}"
    fi
else
    echo -e "${RED}✗ Deployment NO existe${NC}"
    exit 1
fi

pausar

# =================================================
# 3. VALIDACIÓN DE PODS
# =================================================
echo -e "\n${BLUE}[3/8] Validando Pods del Deployment${NC}"
echo "---------------------------------------------------"

kubectl get pods -n $NAMESPACE -l app=nginx -o wide

echo -e "\n${YELLOW}Estado detallado de los Pods:${NC}"
for pod in $(kubectl get pods -n $NAMESPACE -l app=nginx -o jsonpath='{.items[*].metadata.name}'); do
    echo -e "\n${YELLOW}Pod: $pod${NC}"
    STATUS=$(kubectl get pod $pod -n $NAMESPACE -o jsonpath='{.status.phase}')
    echo "Estado: $STATUS"

    if [ "$STATUS" != "Running" ]; then
        echo -e "${RED}⚠ Pod no está en Running${NC}"
        echo -e "${YELLOW}Eventos del pod:${NC}"
        kubectl describe pod $pod -n $NAMESPACE | tail -20
    else
        echo -e "${GREEN}✓ Pod está Running${NC}"
    fi
done

pausar

# =================================================
# 4. VALIDACIÓN DEL SERVICE
# =================================================
echo -e "\n${BLUE}[4/8] Validando Service: ${SERVICE}${NC}"
echo "---------------------------------------------------"

if kubectl get service $SERVICE -n $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓ Service existe${NC}"
    kubectl get service $SERVICE -n $NAMESPACE

    echo -e "\n${YELLOW}Endpoints del Service:${NC}"
    kubectl get endpoints $SERVICE -n $NAMESPACE

    ENDPOINTS=$(kubectl get endpoints $SERVICE -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
    echo -e "\n${YELLOW}Número de endpoints: ${ENDPOINTS}${NC}"

    if [ "$ENDPOINTS" -gt 0 ]; then
        echo -e "${GREEN}✓ Service tiene endpoints activos${NC}"
    else
        echo -e "${RED}✗ Service NO tiene endpoints (pods no están listos)${NC}"
    fi
else
    echo -e "${RED}✗ Service NO existe${NC}"
    exit 1
fi

pausar

# =================================================
# 5. VALIDACIÓN DEL INGRESS
# =================================================
echo -e "\n${BLUE}[5/8] Validando Ingress: ${INGRESS}${NC}"
echo "---------------------------------------------------"

if kubectl get ingress $INGRESS -n $NAMESPACE &>/dev/null; then
    echo -e "${GREEN}✓ Ingress existe${NC}"
    kubectl get ingress $INGRESS -n $NAMESPACE

    echo -e "\n${YELLOW}Detalles del Ingress:${NC}"
    kubectl describe ingress $INGRESS -n $NAMESPACE

    # Verificar IP/ADDRESS asignada
    ADDRESS=$(kubectl get ingress $INGRESS -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$ADDRESS" ]; then
        ADDRESS=$(kubectl get ingress $INGRESS -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    fi

    if [ -n "$ADDRESS" ]; then
        echo -e "${GREEN}✓ Ingress tiene dirección asignada: ${ADDRESS}${NC}"
    else
        echo -e "${YELLOW}⚠ Ingress aún no tiene dirección asignada (puede tomar tiempo)${NC}"
    fi
else
    echo -e "${RED}✗ Ingress NO existe${NC}"
    exit 1
fi

pausar

# =================================================
# 6. VALIDACIÓN DEL CLUSTERISSUER
# =================================================
echo -e "\n${BLUE}[6/8] Validando ClusterIssuer: ${CLUSTERISSUER}${NC}"
echo "---------------------------------------------------"

if kubectl get clusterissuer $CLUSTERISSUER &>/dev/null; then
    echo -e "${GREEN}✓ ClusterIssuer existe${NC}"
    kubectl get clusterissuer $CLUSTERISSUER

    echo -e "\n${YELLOW}Estado del ClusterIssuer:${NC}"
    kubectl describe clusterissuer $CLUSTERISSUER

    # Verificar estado Ready
    READY=$(kubectl get clusterissuer $CLUSTERISSUER -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    if [ "$READY" == "True" ]; then
        echo -e "${GREEN}✓ ClusterIssuer está Ready${NC}"
    else
        echo -e "${RED}✗ ClusterIssuer NO está Ready${NC}"
        echo -e "${YELLOW}Verifica que cert-manager esté instalado correctamente${NC}"
    fi
else
    echo -e "${RED}✗ ClusterIssuer NO existe${NC}"
    echo "Ejecuta: kubectl apply -f clusterissuer.yml"
    exit 1
fi

pausar

# =================================================
# 7. VALIDACIÓN DEL CERTIFICADO
# =================================================
echo -e "\n${BLUE}[7/8] Validando Certificado TLS${NC}"
echo "---------------------------------------------------"

echo -e "${YELLOW}Buscando Certificate resources...${NC}"
kubectl get certificate -n $NAMESPACE

if kubectl get certificate -n $NAMESPACE &>/dev/null; then
    for cert in $(kubectl get certificate -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
        echo -e "\n${YELLOW}Certificado: $cert${NC}"
        kubectl describe certificate $cert -n $NAMESPACE

        READY=$(kubectl get certificate $cert -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [ "$READY" == "True" ]; then
            echo -e "${GREEN}✓ Certificado está Ready${NC}"
        else
            echo -e "${YELLOW}⚠ Certificado aún no está Ready (puede tomar tiempo)${NC}"
        fi
    done
else
    echo -e "${YELLOW}⚠ No se encontraron certificados (se crearán automáticamente)${NC}"
fi

echo -e "\n${YELLOW}Verificando CertificateRequests...${NC}"
kubectl get certificaterequest -n $NAMESPACE

echo -e "\n${YELLOW}Verificando Orders (ACME)...${NC}"
kubectl get order -n $NAMESPACE

echo -e "\n${YELLOW}Verificando Challenges (ACME)...${NC}"
kubectl get challenge -n $NAMESPACE

pausar

# =================================================
# 8. VALIDACIÓN DE CONECTIVIDAD
# =================================================
echo -e "\n${BLUE}[8/8] Validando Conectividad${NC}"
echo "---------------------------------------------------"

echo -e "${YELLOW}Probando conectividad interna al servicio...${NC}"
kubectl run test-curl --image=curlimages/curl:latest --rm -it --restart=Never -n $NAMESPACE -- curl -s -o /dev/null -w "%{http_code}" http://nginx.nginx-namespace.svc.cluster.local

echo -e "\n${YELLOW}Información del host configurado:${NC}"
HOST=$(kubectl get ingress $INGRESS -n $NAMESPACE -o jsonpath='{.spec.rules[0].host}')
echo "Host: $HOST"

echo -e "\n${YELLOW}Probando resolución DNS externa (si está configurado):${NC}"
nslookup $HOST || echo -e "${YELLOW}DNS no resuelve aún (normal si acabas de configurar)${NC}"

echo -e "\n${YELLOW}Para probar el acceso HTTPS externo, ejecuta:${NC}"
echo -e "curl -I https://${HOST}"
echo -e "o abre en navegador: https://${HOST}"

# =================================================
# RESUMEN FINAL
# =================================================
echo -e "\n${BLUE}==================================================${NC}"
echo -e "${BLUE}  RESUMEN DE VALIDACIÓN${NC}"
echo -e "${BLUE}==================================================${NC}"

echo -e "\n${GREEN}Recursos creados correctamente:${NC}"
kubectl get all,ingress -n $NAMESPACE

echo -e "\n${YELLOW}Para monitorear la emisión del certificado en tiempo real:${NC}"
echo "kubectl describe certificate -n $NAMESPACE"
echo "kubectl logs -n cert-manager -l app=cert-manager -f"

echo -e "\n${BLUE}Validación completada.${NC}"
