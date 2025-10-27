#!/bin/bash

# ============================================================================
# Script Unificado de Diagnóstico y Validación
# Verifica el estado completo del despliegue de Nginx en K3s
# ============================================================================

# Obtener el directorio del script principal
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cargar configuración y funciones
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/kubernetes.sh"

# Variables globales para el resumen
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Función para registrar resultados
check_result() {
    local status=$1
    local message=$2

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    case $status in
        "pass")
            PASSED_CHECKS=$((PASSED_CHECKS + 1))
            print_success "$message"
            ;;
        "fail")
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
            print_error "$message"
            ;;
        "warning")
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
            print_warning "$message"
            ;;
    esac
}

# Función para pausar entre secciones (opcional)
pausar() {
    if [ "${INTERACTIVE:-true}" = "true" ]; then
        echo ""
        read -p "Presiona Enter para continuar..."
        echo ""
    fi
}

# ============================================================================
# SECCIÓN 1: PREREQUISITOS
# ============================================================================

print_header "1. VERIFICACIÓN DE PREREQUISITOS"

# 1.1 Verificar kubectl
print_info "Verificando kubectl..."
if command -v kubectl &> /dev/null; then
    check_result "pass" "kubectl está instalado"
    kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1
else
    check_result "fail" "kubectl no está instalado"
    exit 1
fi

# 1.2 Verificar conexión al cluster
echo ""
print_info "Verificando conexión al cluster..."
if kubectl cluster-info &> /dev/null; then
    check_result "pass" "Conectado al cluster K3s"
else
    check_result "fail" "No se puede conectar al cluster"
    exit 1
fi

# 1.3 Verificar nodos
echo ""
print_info "Estado de los nodos:"
kubectl get nodes -o wide

pausar

# ============================================================================
# SECCIÓN 2: NAMESPACE Y RECURSOS BASE
# ============================================================================

print_header "2. VALIDACIÓN DE NAMESPACE Y RECURSOS"

# 2.1 Verificar namespace
print_info "Verificando namespace: $NAMESPACE"
if kubectl get namespace $NAMESPACE &>/dev/null; then
    check_result "pass" "Namespace existe"
    kubectl get namespace $NAMESPACE
else
    check_result "fail" "Namespace NO existe"
    echo "Ejecuta: bash 00-install.sh"
    exit 1
fi

# 2.2 Verificar deployment
echo ""
print_info "Verificando Deployment..."
if kubectl get deployment nginx -n $NAMESPACE &>/dev/null; then
    check_result "pass" "Deployment existe"
    kubectl get deployment nginx -n $NAMESPACE

    # Verificar réplicas
    DESIRED=$(kubectl get deployment nginx -n $NAMESPACE -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment nginx -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')

    echo "Réplicas deseadas: $DESIRED | Réplicas listas: ${READY:-0}"

    if [ "$DESIRED" == "$READY" ]; then
        check_result "pass" "Todas las réplicas están listas ($READY/$DESIRED)"
    else
        check_result "warning" "No todas las réplicas están listas (${READY:-0}/$DESIRED)"
    fi
else
    check_result "fail" "Deployment NO existe"
    exit 1
fi

# 2.3 Verificar pods
echo ""
print_info "Estado de los Pods:"
kubectl get pods -n $NAMESPACE -l app=nginx -o wide

RUNNING_PODS=$(kubectl get pods -n $NAMESPACE -l app=nginx --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE -l app=nginx --no-headers 2>/dev/null | wc -l)

if [ "$RUNNING_PODS" -gt 0 ] && [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ]; then
    check_result "pass" "Todos los pods están Running ($RUNNING_PODS/$TOTAL_PODS)"
else
    check_result "warning" "Solo $RUNNING_PODS de $TOTAL_PODS pods están Running"

    # Mostrar detalles de pods problemáticos
    for pod in $(kubectl get pods -n $NAMESPACE -l app=nginx --field-selector=status.phase!=Running -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
        echo ""
        print_warning "Pod problemático: $pod"
        kubectl describe pod $pod -n $NAMESPACE | tail -15
    done
fi

# 2.4 Verificar service
echo ""
print_info "Verificando Service..."
if kubectl get service nginx -n $NAMESPACE &>/dev/null; then
    check_result "pass" "Service existe"
    kubectl get service nginx -n $NAMESPACE

    # Verificar endpoints
    ENDPOINTS=$(kubectl get endpoints nginx -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)

    if [ "$ENDPOINTS" -gt 0 ]; then
        check_result "pass" "Service tiene $ENDPOINTS endpoint(s) activo(s)"
    else
        check_result "fail" "Service NO tiene endpoints (pods no están listos)"
    fi
else
    check_result "fail" "Service NO existe"
    exit 1
fi

pausar

# ============================================================================
# SECCIÓN 3: INGRESS Y NETWORKING
# ============================================================================

print_header "3. VALIDACIÓN DE INGRESS Y NETWORKING"

# 3.1 Verificar ingress
print_info "Verificando Ingress..."
if kubectl get ingress nginx -n $NAMESPACE &>/dev/null; then
    check_result "pass" "Ingress existe"
    kubectl get ingress nginx -n $NAMESPACE

    # Verificar IP/ADDRESS asignada
    ADDRESS=$(kubectl get ingress nginx -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    if [ -z "$ADDRESS" ]; then
        ADDRESS=$(kubectl get ingress nginx -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    fi

    if [ -n "$ADDRESS" ]; then
        check_result "pass" "Ingress tiene dirección asignada: $ADDRESS"

        # Verificar si la IP es privada
        if [[ $ADDRESS =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.|^100\. ]]; then
            check_result "fail" "PROBLEMA CRÍTICO: $ADDRESS es una IP PRIVADA"
            echo "Let's Encrypt NO puede validar dominios en IPs privadas"
            echo "Opciones:"
            echo "  - Usar servicio como ngrok o Cloudflare Tunnel"
            echo "  - Configurar port forwarding en tu router"
            echo "  - Usar LoadBalancer con IP pública"
        else
            check_result "pass" "La IP parece ser pública"
        fi
    else
        check_result "warning" "Ingress aún no tiene dirección asignada"
    fi

    # Verificar host configurado
    HOST=$(kubectl get ingress nginx -n $NAMESPACE -o jsonpath='{.spec.rules[0].host}')
    echo ""
    print_info "Host configurado: $HOST"

    # Verificar DNS
    echo ""
    print_info "Verificando resolución DNS..."
    DNS_IP=$(dig +short $HOST | tail -1)

    if [ -n "$DNS_IP" ]; then
        echo "DNS resuelve a: $DNS_IP"

        if [ "$DNS_IP" == "$ADDRESS" ]; then
            check_result "pass" "DNS apunta correctamente al Ingress"
        else
            check_result "warning" "DNS no apunta al Ingress (DNS: $DNS_IP vs Ingress: $ADDRESS)"
        fi
    else
        check_result "warning" "DNS no resuelve aún (normal si acabas de configurar)"
    fi

else
    check_result "fail" "Ingress NO existe"
    exit 1
fi

# 3.2 Probar accesibilidad HTTP externa
echo ""
print_info "Probando acceso HTTP externo a $DOMAIN..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://$DOMAIN --max-time 5 2>/dev/null || echo "000")
echo "Código HTTP: $HTTP_CODE"

case $HTTP_CODE in
    "200"|"301"|"302")
        check_result "pass" "El dominio es accesible vía HTTP (código: $HTTP_CODE)"
        ;;
    "000")
        check_result "fail" "No se puede acceder al dominio desde Internet"
        echo "Causa probable: IP privada o firewall bloqueando"
        ;;
    *)
        check_result "warning" "Respuesta inesperada: $HTTP_CODE"
        ;;
esac

pausar

# ============================================================================
# SECCIÓN 4: CERT-MANAGER Y CERTIFICADOS
# ============================================================================

print_header "4. VALIDACIÓN DE CERT-MANAGER Y CERTIFICADOS"

# 4.1 Verificar cert-manager
print_info "Verificando cert-manager..."
if kubectl get namespace cert-manager &>/dev/null; then
    check_result "pass" "Namespace cert-manager existe"

    # Verificar pods de cert-manager
    CM_PODS_RUNNING=$(kubectl get pods -n cert-manager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    CM_PODS_TOTAL=$(kubectl get pods -n cert-manager --no-headers 2>/dev/null | wc -l)

    if [ "$CM_PODS_RUNNING" -gt 0 ] && [ "$CM_PODS_RUNNING" -eq "$CM_PODS_TOTAL" ]; then
        check_result "pass" "Todos los pods de cert-manager están Running ($CM_PODS_RUNNING/$CM_PODS_TOTAL)"
    else
        check_result "warning" "Solo $CM_PODS_RUNNING de $CM_PODS_TOTAL pods de cert-manager están Running"
    fi

    kubectl get pods -n cert-manager
else
    check_result "fail" "cert-manager NO está instalado"
    echo "Instálalo con: bash 00-install.sh"
fi

# 4.2 Verificar ClusterIssuer
echo ""
print_info "Verificando ClusterIssuer..."
if kubectl get clusterissuer letsencrypt-prod &>/dev/null; then
    check_result "pass" "ClusterIssuer existe"
    kubectl get clusterissuer letsencrypt-prod

    # Verificar estado Ready
    READY=$(kubectl get clusterissuer letsencrypt-prod -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

    if [ "$READY" == "True" ]; then
        check_result "pass" "ClusterIssuer está Ready"
    else
        check_result "warning" "ClusterIssuer NO está Ready"
    fi
else
    check_result "fail" "ClusterIssuer NO existe"
fi

# 4.3 Verificar Certificate
echo ""
print_info "Verificando Certificate..."
if kubectl get certificate -n $NAMESPACE &>/dev/null 2>&1; then
    CERT_COUNT=$(kubectl get certificate -n $NAMESPACE --no-headers 2>/dev/null | wc -l)

    if [ "$CERT_COUNT" -gt 0 ]; then
        check_result "pass" "Encontrados $CERT_COUNT certificado(s)"
        kubectl get certificate -n $NAMESPACE

        # Verificar cada certificado
        for cert in $(kubectl get certificate -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}'); do
            CERT_READY=$(kubectl get certificate $cert -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

            echo ""
            if [ "$CERT_READY" == "True" ]; then
                check_result "pass" "Certificado '$cert' está Ready"
            else
                check_result "warning" "Certificado '$cert' aún no está Ready"

                # Mostrar detalles del challenge si existe
                echo ""
                print_info "Verificando challenges activos..."
                if kubectl get challenge -n $NAMESPACE &>/dev/null 2>&1; then
                    kubectl get challenge -n $NAMESPACE
                fi
            fi
        done
    else
        check_result "warning" "No se encontraron certificados (se crearán automáticamente)"
    fi
else
    check_result "warning" "No se encontraron certificados"
fi

# 4.4 Verificar Orders y Challenges
echo ""
print_info "Estado de Orders (ACME):"
kubectl get order -n $NAMESPACE 2>/dev/null || echo "No hay orders activos"

echo ""
print_info "Estado de Challenges (ACME):"
kubectl get challenge -n $NAMESPACE 2>/dev/null || echo "No hay challenges activos"

pausar

# ============================================================================
# SECCIÓN 5: DNS Y CONECTIVIDAD (DIAGNÓSTICO AVANZADO)
# ============================================================================

print_header "5. DIAGNÓSTICO AVANZADO DE DNS Y CONECTIVIDAD"

# 5.1 DNS del HOST
print_info "Probando DNS desde el HOST..."
if dig +short acme-v02.api.letsencrypt.org @8.8.8.8 &> /dev/null; then
    LE_IP=$(dig +short acme-v02.api.letsencrypt.org @8.8.8.8 | tail -n1)
    check_result "pass" "DNS del host funciona (Let's Encrypt resuelve a: $LE_IP)"
else
    check_result "warning" "DNS del host no responde correctamente"
fi

# 5.2 CoreDNS
echo ""
print_info "Verificando CoreDNS..."
COREDNS_PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
if [ "$COREDNS_PODS" -gt 0 ]; then
    check_result "pass" "CoreDNS está desplegado ($COREDNS_PODS pod(s))"
    kubectl get pods -n kube-system -l k8s-app=kube-dns
else
    check_result "warning" "CoreDNS no se encuentra o no está etiquetado correctamente"
fi

# 5.3 Probar conectividad interna
echo ""
print_info "Probando conectividad interna al servicio..."
INTERNAL_TEST=$(kubectl run test-curl-$RANDOM --image=curlimages/curl:latest --rm --restart=Never -n $NAMESPACE -- curl -s -o /dev/null -w "%{http_code}" http://nginx.${NAMESPACE}.svc.cluster.local --max-time 5 2>/dev/null || echo "FAIL")

if [[ "$INTERNAL_TEST" == "200" ]]; then
    check_result "pass" "Conectividad interna funciona correctamente"
elif [[ "$INTERNAL_TEST" == "FAIL" ]]; then
    check_result "warning" "No se pudo probar conectividad interna"
else
    check_result "warning" "Respuesta inesperada en conectividad interna: $INTERNAL_TEST"
fi

pausar

# ============================================================================
# SECCIÓN 6: RESUMEN Y RECOMENDACIONES
# ============================================================================

print_header "RESUMEN DE DIAGNÓSTICO"

echo "Total de verificaciones: $TOTAL_CHECKS"
echo ""
print_success "Pasadas: $PASSED_CHECKS"
print_warning "Advertencias: $WARNING_CHECKS"
print_error "Fallidas: $FAILED_CHECKS"
echo ""

# Calcular porcentaje de éxito
SUCCESS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))

if [ "$SUCCESS_RATE" -ge 90 ]; then
    print_success "Estado general: EXCELENTE ($SUCCESS_RATE%)"
elif [ "$SUCCESS_RATE" -ge 70 ]; then
    print_warning "Estado general: BUENO ($SUCCESS_RATE%)"
elif [ "$SUCCESS_RATE" -ge 50 ]; then
    print_warning "Estado general: ACEPTABLE ($SUCCESS_RATE%)"
else
    print_error "Estado general: PROBLEMAS DETECTADOS ($SUCCESS_RATE%)"
fi

echo ""
print_header "RECURSOS DESPLEGADOS"
kubectl get all,ingress,certificate -n $NAMESPACE

echo ""
print_header "RECOMENDACIONES"

if [ "$FAILED_CHECKS" -gt 0 ]; then
    echo "Hay problemas críticos que requieren atención:"
    echo "  1. Revisa los mensajes de error arriba"
    echo "  2. Ejecuta: kubectl describe certificate -n $NAMESPACE"
    echo "  3. Revisa logs: kubectl logs -n cert-manager -l app=cert-manager --tail=50"
fi

if [ "$WARNING_CHECKS" -gt 0 ]; then
    echo ""
    echo "Advertencias detectadas:"
    echo "  - Algunos componentes pueden estar inicializándose"
    echo "  - El certificado puede tardar 2-5 minutos en emitirse"
    echo "  - Ejecuta este script nuevamente en unos minutos"
fi

echo ""
echo "Comandos útiles:"
echo "  - Monitorear certificado: kubectl get certificate -n $NAMESPACE -w"
echo "  - Ver logs cert-manager: kubectl logs -n cert-manager -l app=cert-manager -f"
echo "  - Probar HTTPS: curl -I https://$DOMAIN"
echo "  - Re-ejecutar diagnóstico: bash scripts/diagnostico.sh"

echo ""
print_success "Diagnóstico completado"
