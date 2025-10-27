#!/bin/bash

# ============================================================================
# INICIO RÁPIDO - Nginx en K3s con HTTPS
# ============================================================================
#
# Este script despliega Nginx de forma rápida sin validaciones ni pausas.
# Para instalación interactiva con validaciones, usa: bash 00-install.sh
#
# ============================================================================

# Obtener el directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar configuración y funciones
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/helpers.sh"

print_info "Desplegando Nginx en K3s con HTTPS..."
echo ""

# Desplegar todo
print_info "Aplicando manifiestos..."
kubectl apply -k "$SCRIPT_DIR/k8s/overlays/simple"

if [ $? -ne 0 ]; then
    print_error "Error al aplicar el manifiesto"
    exit 1
fi

print_success "Manifiesto aplicado correctamente"
echo ""

# Verificar ClusterIssuer
print_info "Verificando ClusterIssuer..."
kubectl get clusterissuer letsencrypt-prod

echo ""
print_info "Esperando a que los pods estén listos..."
kubectl wait --for=condition=ready pod -l app=nginx -n $NAMESPACE --timeout=120s

echo ""
print_info "Estado actual:"
echo ""
kubectl get all -n $NAMESPACE

echo ""
print_info "Certificados:"
kubectl get certificate -n $NAMESPACE

echo ""
print_info "Ingress:"
kubectl get ingress -n $NAMESPACE

echo ""
print_header "DESPLIEGUE COMPLETADO"

print_warning "El certificado SSL puede tardar 2-5 minutos en estar listo."
echo ""
echo "Para monitorear el certificado:"
echo "  kubectl get certificate -n $NAMESPACE -w"
echo ""
echo "Una vez que el certificado esté 'Ready', activa la redirección HTTPS:"
echo "  kubectl apply -k k8s/overlays/with-redirect"
echo ""
echo "Para validación completa:"
echo "  bash scripts/03-test.sh"
echo ""
