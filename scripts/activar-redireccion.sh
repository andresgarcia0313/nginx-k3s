#!/bin/bash

# ============================================================================
# Script para activar redirección HTTP → HTTPS
# ============================================================================

# Obtener el directorio del script principal
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cargar configuración y funciones
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/helpers.sh"

print_header "ACTIVAR REDIRECCIÓN HTTP → HTTPS"

# Verificar que el certificado esté listo
print_info "Verificando estado del certificado..."
CERT_READY=$(kubectl get certificate nginx-tls -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

if [ "$CERT_READY" != "True" ]; then
    print_error "El certificado NO está listo aún"
    echo ""
    echo "Estado actual:"
    kubectl get certificate -n $NAMESPACE
    echo ""
    print_warning "Debes esperar a que el certificado esté Ready=True antes de activar la redirección"
    print_info "Monitorea el estado con: kubectl get certificate -n $NAMESPACE -w"
    exit 1
fi

print_success "Certificado está listo"
echo ""

# Mostrar advertencia
print_warning "Esto modificará el Ingress para redirigir todo el tráfico HTTP a HTTPS"
echo ""
read -p "¿Continuar? (s/n): " confirm

if [[ "$confirm" != "s" ]] && [[ "$confirm" != "S" ]]; then
    print_info "Operación cancelada"
    exit 0
fi

echo ""
print_info "Creando Middleware de redirección..."
kubectl apply -f "$SCRIPT_DIR/k8s/overlays/with-redirect/middleware.yml"

if [ $? -ne 0 ]; then
    print_error "Error creando el Middleware"
    exit 1
fi

print_success "Middleware creado"
echo ""

print_info "Actualizando Ingress con redirección..."
kubectl apply -f "$SCRIPT_DIR/k8s/overlays/with-redirect/ingress.yml"

if [ $? -ne 0 ]; then
    print_error "Error actualizando el Ingress"
    exit 1
fi

print_success "Ingress actualizado con redirección"
echo ""

print_header "VERIFICACIÓN"

echo "Estado del Ingress:"
kubectl get ingress -n $NAMESPACE
echo ""

echo "Middleware creado:"
kubectl get middleware -n $NAMESPACE
echo ""

print_header "PRUEBAS"

echo "Para probar la redirección HTTP → HTTPS:"
echo ""
echo "  curl -I http://$DOMAIN"
echo "  # Debe devolver: HTTP/1.1 301 Moved Permanently"
echo ""
echo "  curl -I https://$DOMAIN"
echo "  # Debe devolver: HTTP/2 200"
echo ""

print_success "Redirección HTTPS activada correctamente"
