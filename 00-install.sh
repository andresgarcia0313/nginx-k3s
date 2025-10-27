#!/bin/bash

# ============================================================================
# Script de instalación automatizada de Nginx con HTTPS en K3s
# ============================================================================

# Obtener el directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar configuración y funciones
source "$SCRIPT_DIR/config.env"
source "$SCRIPT_DIR/lib/helpers.sh"
source "$SCRIPT_DIR/lib/kubernetes.sh"

# ============================================================================
# Verificación de prerequisitos
# ============================================================================

print_header "1. VERIFICANDO PREREQUISITOS"

verify_kubectl || exit 1
verify_cluster_connection || exit 1

# Verificar e instalar cert-manager si es necesario
if ! verify_cert_manager; then
    print_warning "cert-manager no está instalado"
    echo ""
    echo "¿Deseas instalar cert-manager ahora? (s/n)"
    read -r response
    if [[ "$response" =~ ^[Ss]$ ]]; then
        install_cert_manager || exit 1
    else
        print_error "cert-manager es necesario. Instálalo manualmente y vuelve a ejecutar este script"
        exit 1
    fi
fi

pause

# ============================================================================
# Selección de método de instalación
# ============================================================================

print_header "2. MÉTODO DE INSTALACIÓN"

echo "Selecciona el método de instalación:"
echo ""
echo "1) Simple: Sin redirección HTTPS inicial"
echo "   - Despliega sin redirección HTTP->HTTPS"
echo "   - Espera certificado SSL"
echo "   - Opcionalmente activa redirección después"
echo "   - Recomendado para principiantes"
echo ""
echo "2) Avanzado: Con redirección HTTPS desde el inicio"
echo "   - Todo en un solo comando"
echo "   - Redirección HTTP->HTTPS automática"
echo "   - Recomendado si entiendes el proceso"
echo ""
read -p "Selecciona (1 o 2): " method

# ============================================================================
# MÉTODO 1: Simple (sin redirección inicial)
# ============================================================================

if [ "$method" = "1" ]; then
    print_header "3. DESPLEGANDO NGINX (sin redirección HTTPS)"

    apply_manifest "$SCRIPT_DIR/k8s/overlays/simple" "configuración simple" || exit 1

    pause

    print_header "4. ESPERANDO A QUE LOS PODS ESTÉN LISTOS"

    wait_for_deployment "$NAMESPACE" || exit 1

    pause

    print_header "5. ESPERANDO CERTIFICADO SSL"

    wait_for_certificate "$NAMESPACE" || exit 1

    pause

    print_header "6. ACTIVANDO REDIRECCIÓN HTTPS"

    echo "¿Deseas activar la redirección automática HTTP -> HTTPS? (s/n)"
    read -r response
    if [[ "$response" =~ ^[Ss]$ ]]; then
        print_info "Aplicando redirección HTTPS..."
        kubectl apply -f "$SCRIPT_DIR/k8s/overlays/with-redirect/middleware.yml"
        kubectl apply -f "$SCRIPT_DIR/k8s/overlays/with-redirect/ingress-patch.yml"
        print_success "Redirección HTTPS activada"
    else
        print_warning "Redirección HTTPS no activada"
        print_info "Puedes activarla después con: kubectl apply -k k8s/overlays/with-redirect"
    fi

# ============================================================================
# MÉTODO 2: Avanzado (con redirección desde el inicio)
# ============================================================================

elif [ "$method" = "2" ]; then
    print_header "3. DESPLEGANDO NGINX (con redirección HTTPS)"

    apply_manifest "$SCRIPT_DIR/k8s/overlays/with-redirect" "configuración con redirección" || exit 1

    pause

    print_header "4. ESPERANDO A QUE LOS PODS ESTÉN LISTOS"

    wait_for_deployment "$NAMESPACE" || exit 1

    pause

    print_header "5. ESPERANDO CERTIFICADO SSL"

    wait_for_certificate "$NAMESPACE" || exit 1

else
    print_error "Opción inválida"
    exit 1
fi

# ============================================================================
# Resumen final
# ============================================================================

print_header "INSTALACIÓN COMPLETADA"

show_deployment_summary "$NAMESPACE"

print_header "PRÓXIMOS PASOS"

echo "1. Verifica que tu dominio apunta a la IP del Ingress:"
echo "   kubectl get ingress -n $NAMESPACE"
echo ""

echo "2. Prueba el acceso HTTPS:"
echo "   curl -I https://$DOMAIN"
echo ""

if [ "$method" = "1" ]; then
    echo "3. Si activaste la redirección, prueba que HTTP redirige a HTTPS:"
    echo "   curl -I http://$DOMAIN"
    echo ""
elif [ "$method" = "2" ]; then
    echo "3. Prueba que HTTP redirige a HTTPS:"
    echo "   curl -I http://$DOMAIN"
    echo "   (Debe mostrar: HTTP/1.1 301 Moved Permanently)"
    echo ""
fi

echo "4. Para ver logs de cert-manager si hay problemas:"
echo "   kubectl logs -n cert-manager -l app=cert-manager -f"
echo ""

echo "5. Para ejecutar diagnósticos:"
echo "   bash scripts/03-test.sh"
echo ""

print_success "Todo listo. Tu sitio debería estar accesible en https://$DOMAIN"
