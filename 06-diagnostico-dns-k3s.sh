#!/bin/bash

# Script de diagnóstico DNS para k3s
# No realiza ningún cambio en el sistema
# Autor: Claude
# Fecha: 2025-10-24

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "   DIAGNÓSTICO DNS K3S - MODO LECTURA    "
echo "=========================================="
echo ""

# Función para imprimir con colores
print_status() {
    local status=$1
    local message=$2
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" == "FAIL" ]; then
        echo -e "${RED}✗${NC} $message"
    elif [ "$status" == "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${BLUE}ℹ${NC} $message"
    fi
}

# 1. Verificar que kubectl está disponible
echo -e "${BLUE}[1/10]${NC} Verificando kubectl..."
if command -v kubectl &> /dev/null; then
    print_status "OK" "kubectl está instalado"
    kubectl version --client --short 2>/dev/null || true
else
    print_status "FAIL" "kubectl no está instalado"
    exit 1
fi
echo ""

# 2. Verificar conectividad al cluster
echo -e "${BLUE}[2/10]${NC} Verificando conectividad al cluster..."
if kubectl cluster-info &> /dev/null; then
    print_status "OK" "Conectado al cluster k3s"
else
    print_status "FAIL" "No se puede conectar al cluster"
    exit 1
fi
echo ""

# 3. Verificar estado de nodos
echo -e "${BLUE}[3/10]${NC} Estado de los nodos..."
kubectl get nodes -o wide
echo ""

# 4. Verificar DNS del HOST
echo -e "${BLUE}[4/10]${NC} Probando DNS desde el HOST..."
if dig +short acme-v02.api.letsencrypt.org @8.8.8.8 &> /dev/null; then
    IP=$(dig +short acme-v02.api.letsencrypt.org @8.8.8.8 | tail -n1)
    print_status "OK" "DNS del host funciona correctamente (resuelve a: $IP)"
else
    print_status "FAIL" "DNS del host NO funciona"
fi
echo ""

# 5. Verificar CoreDNS
echo -e "${BLUE}[5/10]${NC} Verificando CoreDNS..."
COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
if [ "$COREDNS_PODS" -gt 0 ]; then
    print_status "OK" "CoreDNS está desplegado ($COREDNS_PODS pod(s))"
    kubectl get pods -n kube-system -l k8s-app=kube-dns
else
    print_status "FAIL" "CoreDNS no está desplegado"
fi
echo ""

# 6. Verificar servicio kube-dns
echo -e "${BLUE}[6/10]${NC} Verificando servicio kube-dns..."
KUBE_DNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
if [ -n "$KUBE_DNS_IP" ]; then
    print_status "OK" "Servicio kube-dns activo en IP: $KUBE_DNS_IP"
    kubectl get svc -n kube-system kube-dns
else
    print_status "FAIL" "Servicio kube-dns no encontrado"
fi
echo ""

# 7. Verificar configuración de CoreDNS
echo -e "${BLUE}[7/10]${NC} Analizando configuración de CoreDNS..."
FORWARD_CONFIG=$(kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null | grep "forward")

echo "Configuración actual de forward:"
echo "$FORWARD_CONFIG"
echo ""

if echo "$FORWARD_CONFIG" | grep -q "/etc/resolv.conf"; then
    print_status "WARN" "CoreDNS está configurado para usar /etc/resolv.conf (puede causar problemas)"
    echo -e "${YELLOW}      Esto hace que CoreDNS intente usar el DNS del host (127.0.0.53)${NC}"
    echo -e "${YELLOW}      que NO es accesible desde dentro de los pods${NC}"
elif echo "$FORWARD_CONFIG" | grep -qE "8\.8\.8\.8|1\.1\.1\.1|9\.9\.9\.9"; then
    print_status "OK" "CoreDNS está configurado para usar DNS público"
else
    print_status "INFO" "CoreDNS tiene una configuración personalizada"
fi
echo ""

# 8. Probar DNS desde un pod temporal
echo -e "${BLUE}[8/10]${NC} Probando resolución DNS desde un pod temporal..."
echo "Creando pod de prueba (timeout 15 segundos)..."

# Crear el pod y capturar su nombre
POD_NAME="dns-test-$(date +%s)"
echo "Iniciando pod: $POD_NAME"

# Crear el pod en background y obtener logs con timeout
kubectl run $POD_NAME --image=busybox:1.36 --restart=Never --command -- sh -c "nslookup acme-v02.api.letsencrypt.org || echo 'DNS_FAILED'" &> /dev/null &
KUBECTL_PID=$!

# Esperar a que el pod esté corriendo (máximo 10 segundos)
echo -n "Esperando a que el pod inicie..."
for i in {1..10}; do
    if kubectl get pod $POD_NAME &> /dev/null; then
        POD_STATUS=$(kubectl get pod $POD_NAME -o jsonpath='{.status.phase}' 2>/dev/null)
        if [ "$POD_STATUS" == "Running" ] || [ "$POD_STATUS" == "Succeeded" ] || [ "$POD_STATUS" == "Failed" ]; then
            echo " ✓"
            break
        fi
    fi
    echo -n "."
    sleep 1
done
echo ""

# Obtener logs con timeout
echo "Obteniendo resultados..."
DNS_TEST=$(timeout 15 kubectl logs $POD_NAME 2>&1 || echo "TIMEOUT")

# Limpiar el pod
kubectl delete pod $POD_NAME --force --grace-period=0 &> /dev/null || true

# Analizar resultados
if echo "$DNS_TEST" | grep -q "Address: "; then
    print_status "OK" "DNS funciona correctamente desde los pods"
    echo "$DNS_TEST" | grep -A2 "Name:" || echo "$DNS_TEST" | head -5
elif echo "$DNS_TEST" | grep -q "DNS_FAILED\|timed out\|no servers could be reached\|can't resolve"; then
    print_status "FAIL" "DNS NO funciona desde los pods"
    echo -e "${RED}Esto confirma el problema:${NC}"
    echo "$DNS_TEST" | head -10
    echo ""
    print_status "INFO" "Este es el problema que está afectando cert-manager"
elif echo "$DNS_TEST" | grep -q "TIMEOUT"; then
    print_status "FAIL" "Timeout al probar DNS (el pod no responde)"
    echo -e "${RED}El pod se quedó bloqueado esperando respuesta DNS${NC}"
    print_status "INFO" "Esto confirma que DNS NO funciona desde los pods"
else
    print_status "WARN" "No se pudo completar la prueba de DNS"
    echo "Output recibido:"
    echo "$DNS_TEST" | head -10
fi
echo ""

# 9. Verificar cert-manager
echo -e "${BLUE}[9/10]${NC} Verificando cert-manager..."
CERT_MANAGER_PODS=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l)
if [ "$CERT_MANAGER_PODS" -gt 0 ]; then
    print_status "OK" "cert-manager está desplegado"
    kubectl get pods -n cert-manager
else
    print_status "WARN" "cert-manager no está instalado"
fi
echo ""

# 10. Verificar ClusterIssuer
echo -e "${BLUE}[10/10]${NC} Verificando ClusterIssuer..."
if kubectl get clusterissuer letsencrypt-prod &> /dev/null; then
    ISSUER_READY=$(kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$ISSUER_READY" == "True" ]; then
        print_status "OK" "ClusterIssuer letsencrypt-prod está READY"
    else
        print_status "FAIL" "ClusterIssuer letsencrypt-prod NO está ready"
        echo ""
        echo "Detalles del error:"
        kubectl describe clusterissuer letsencrypt-prod | grep -A10 "Status:"
    fi
else
    print_status "INFO" "ClusterIssuer letsencrypt-prod no existe aún"
fi
echo ""

# RESUMEN Y RECOMENDACIONES
echo "=========================================="
echo "         RESUMEN Y DIAGNÓSTICO           "
echo "=========================================="
echo ""

# Determinar el problema principal
if echo "$DNS_TEST" | grep -q "timed out\|no servers could be reached\|DNS_FAILED\|TIMEOUT"; then
    echo -e "${RED}✗ PROBLEMA CONFIRMADO:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DNS NO funciona desde los pods del cluster"
    echo ""
    echo -e "${YELLOW}Causa raíz:${NC}"
    echo "• CoreDNS está configurado con: forward . /etc/resolv.conf"
    echo "• /etc/resolv.conf apunta a 127.0.0.53 (systemd-resolved)"
    echo "• Los pods NO pueden acceder a 127.0.0.53 del host"
    echo "• Por eso cert-manager no puede comunicarse con Let's Encrypt"
    echo ""
    echo -e "${GREEN}✓ SOLUCIÓN (ejecutar estos comandos):${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "# 1. Actualizar configuración de CoreDNS"
    echo "kubectl get configmap coredns -n kube-system -o yaml | \\"
    echo "  sed 's|forward . /etc/resolv.conf|forward . 8.8.8.8 8.8.4.4 1.1.1.1|g' | \\"
    echo "  kubectl apply -f -"
    echo ""
    echo "# 2. Reiniciar CoreDNS"
    echo "kubectl rollout restart deployment coredns -n kube-system"
    echo ""
    echo "# 3. Esperar a que esté listo"
    echo "kubectl rollout status deployment coredns -n kube-system"
    echo ""
    echo "# 4. Verificar que funciona"
    echo "kubectl run dns-verify --image=busybox:1.36 --restart=Never --rm -it -- nslookup acme-v02.api.letsencrypt.org"
    echo ""
    echo "# 5. Recrear ClusterIssuer"
    echo "kubectl delete clusterissuer letsencrypt-prod --ignore-not-found"
    echo "kubectl apply -f tu-clusterissuer.yaml"
    echo ""
elif echo "$DNS_TEST" | grep -q "Address: "; then
    echo -e "${GREEN}✓ TODO CORRECTO:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "• DNS funciona correctamente desde los pods"
    echo "• CoreDNS está configurado apropiadamente"
    echo "• cert-manager debería poder comunicarse con Let's Encrypt"
    echo ""
    if [ "$ISSUER_READY" != "True" ]; then
        echo -e "${YELLOW}NOTA:${NC} El ClusterIssuer aún no está ready."
        echo "Puede tomar unos minutos para registrarse con Let's Encrypt."
        echo "Verifica con: kubectl describe clusterissuer letsencrypt-prod"
    fi
else
    echo -e "${YELLOW}⚠ RESULTADO INCONCLUSO:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "No se pudo determinar con certeza el estado del DNS"
    echo "Revisa los logs anteriores para más detalles"
    echo ""
    echo "Puedes probar manualmente con:"
    echo "kubectl run dns-manual --image=busybox:1.36 --restart=Never -- sleep 3600"
    echo "kubectl exec dns-manual -- nslookup acme-v02.api.letsencrypt.org"
    echo "kubectl delete pod dns-manual"
fi

echo ""
echo "=========================================="
echo "       FIN DEL DIAGNÓSTICO               "
echo "=========================================="
