#!/bin/bash

# ============================================================================
# Biblioteca de funciones para Kubernetes
# ============================================================================

# Requiere helpers.sh para las funciones de impresión
if [ -z "$GREEN" ]; then
    echo "Error: Este script requiere lib/helpers.sh"
    exit 1
fi

# ============================================================================
# Verificaciones de prerequisitos
# ============================================================================

verify_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl no está instalado"
        return 1
    fi
    print_success "kubectl está instalado"
    return 0
}

verify_cluster_connection() {
    if ! kubectl cluster-info &> /dev/null; then
        print_error "No se puede conectar al cluster de Kubernetes"
        return 1
    fi
    print_success "Conexión al cluster OK"
    return 0
}

verify_cert_manager() {
    if ! kubectl get namespace cert-manager &> /dev/null; then
        return 1
    fi
    print_success "cert-manager está instalado"
    return 0
}

install_cert_manager() {
    print_info "Instalando cert-manager..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

    print_info "Esperando a que cert-manager esté listo..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s

    if [ $? -eq 0 ]; then
        print_success "cert-manager instalado correctamente"
        return 0
    else
        print_error "Error instalando cert-manager"
        return 1
    fi
}

# ============================================================================
# Funciones de espera y validación
# ============================================================================

wait_for_certificate() {
    local namespace=$1
    local cert_name=${2:-nginx-tls}
    local timeout=${3:-600}
    local elapsed=0

    print_info "Esperando a que cert-manager solicite y obtenga el certificado..."
    print_info "Esto puede tardar 2-5 minutos..."
    echo ""

    while [ $elapsed -lt $timeout ]; do
        cert_status=$(kubectl get certificate $cert_name -n $namespace -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)

        if [ "$cert_status" = "True" ]; then
            print_success "¡Certificado SSL obtenido correctamente!"
            return 0
        fi

        # Mostrar estado cada 10 segundos
        if [ $((elapsed % 10)) -eq 0 ]; then
            echo -ne "\r⏳ Esperando certificado... ${elapsed}s / ${timeout}s"
        fi

        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo ""

    print_error "El certificado no se obtuvo en el tiempo esperado"
    print_info "Puedes verificar el estado con: kubectl describe certificate $cert_name -n $namespace"
    return 1
}

wait_for_deployment() {
    local namespace=$1
    local deployment_name=${2:-nginx}
    local timeout=${3:-300}

    print_info "Esperando a que el Deployment esté listo..."
    kubectl rollout status deployment/$deployment_name -n $namespace --timeout=${timeout}s

    if [ $? -eq 0 ]; then
        print_success "Pods de $deployment_name están listos"
        return 0
    else
        print_error "El Deployment $deployment_name no está listo"
        return 1
    fi
}

# ============================================================================
# Funciones de despliegue
# ============================================================================

apply_manifest() {
    local manifest_file=$1
    local description=${2:-"el manifiesto"}

    print_info "Aplicando $description..."
    kubectl apply -f "$manifest_file"

    if [ $? -eq 0 ]; then
        print_success "Manifiesto aplicado correctamente"
        return 0
    else
        print_error "Error al aplicar el manifiesto"
        return 1
    fi
}

# ============================================================================
# Funciones de información
# ============================================================================

show_deployment_summary() {
    local namespace=$1

    echo "Recursos desplegados:"
    echo ""
    kubectl get all -n $namespace
    echo ""

    print_info "Estado del certificado:"
    kubectl get certificate -n $namespace
    echo ""

    print_info "Estado de los Ingress:"
    kubectl get ingress -n $namespace
    echo ""
}
