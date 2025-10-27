#!/bin/bash

# ============================================================================
# Script de limpieza de recursos de Nginx
# ============================================================================

# Obtener el directorio del script principal
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Cargar configuración y funciones
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/helpers.sh"

print_header "ELIMINANDO RECURSOS DE NGINX"

echo "Se eliminarán los siguientes recursos:"
echo "  - Namespace: $NAMESPACE"
echo "  - ClusterIssuer: letsencrypt-prod"
echo ""
print_warning "Esta acción es IRREVERSIBLE"
echo ""
read -p "¿Estás seguro? (escribe 'si' para confirmar): " confirm

if [[ "$confirm" != "si" ]]; then
    print_info "Operación cancelada"
    exit 0
fi

echo ""
print_info "Eliminando namespace $NAMESPACE..."
kubectl delete namespace $NAMESPACE --timeout=60s

if [ $? -eq 0 ]; then
    print_success "Namespace eliminado"
else
    print_warning "Hubo un problema eliminando el namespace"
fi

echo ""
print_info "Eliminando ClusterIssuer letsencrypt-prod..."
kubectl delete clusterissuer letsencrypt-prod

if [ $? -eq 0 ]; then
    print_success "ClusterIssuer eliminado"
else
    print_warning "Hubo un problema eliminando el ClusterIssuer"
fi

echo ""
print_success "Limpieza completada"
echo ""
print_info "Para volver a desplegar, ejecuta: bash 00-install.sh"
