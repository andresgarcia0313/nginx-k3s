#!/bin/bash

echo "=== DIAGNÓSTICO DE RED PARA CERTIFICADO ==="
echo ""

# 1. Verificar IP del Ingress
INGRESS_IP=$(kubectl get ingress nginx -n nginx-namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "1. IP del Ingress: $INGRESS_IP"

# 2. Verificar DNS
DNS_IP=$(dig +short nginx.negociapp.com | tail -1)
echo "2. IP en DNS: $DNS_IP"

# 3. Comparar
if [ "$INGRESS_IP" == "$DNS_IP" ]; then
    echo "   ✓ DNS apunta correctamente al Ingress"
else
    echo "   ✗ PROBLEMA: DNS no apunta al Ingress"
    echo "   ACCIÓN: Actualiza el DNS de nginx.negociapp.com para que apunte a $INGRESS_IP"
fi

# 4. Verificar accesibilidad HTTP externa
echo ""
echo "3. Probando acceso HTTP externo..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://nginx.negociapp.com --max-time 5)
echo "   Código HTTP: $HTTP_CODE"

if [ "$HTTP_CODE" == "000" ]; then
    echo "   ✗ PROBLEMA: No se puede acceder al dominio desde Internet"
    echo "   CAUSA PROBABLE: IP privada o firewall bloqueando"
elif [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ]; then
    echo "   ✓ El dominio es accesible"
else
    echo "   ⚠ Respuesta inesperada"
fi

# 5. Verificar si la IP es privada
echo ""
echo "4. Verificando tipo de IP..."
if [[ $INGRESS_IP =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\.|^100\. ]]; then
    echo "   ✗ PROBLEMA CRÍTICO: $INGRESS_IP es una IP PRIVADA"
    echo "   Let's Encrypt NO puede validar dominios en IPs privadas"
    echo "   SOLUCIÓN: Necesitas exponer tu cluster con una IP pública"
    echo "   Opciones:"
    echo "   - Usar un servicio como ngrok, Cloudflare Tunnel"
    echo "   - Configurar port forwarding en tu router"
    echo "   - Usar un LoadBalancer con IP pública"
else
    echo "   ✓ La IP parece ser pública"
fi

echo ""
echo "=== FIN DEL DIAGNÓSTICO ==="
