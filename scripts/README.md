# Scripts de Diagnóstico y Utilidades

Scripts para diagnosticar y gestionar el despliegue de Nginx en K3s.

## Scripts Disponibles

### activar-redireccion.sh - Activar Redirección HTTPS

**Propósito**: Activa la redirección HTTP → HTTPS después de obtener el certificado.

**Uso**:
```bash
bash scripts/activar-redireccion.sh
```

**Características**:
- Verifica que el certificado esté Ready antes de continuar
- Crea el Middleware de Traefik
- Actualiza el Ingress con la anotación de redirección
- Muestra comandos para probar la redirección

**Cuándo usar:**
- Después de que `kubectl get certificate -n nginx-namespace` muestre READY=True
- Cuando quieras activar HTTP → HTTPS redirect

**Ejemplo:**
```bash
$ bash scripts/activar-redireccion.sh

============================================================
  ACTIVAR REDIRECCIÓN HTTP → HTTPS
============================================================

Verificando estado del certificado...
✅ Certificado está listo

⚠️  Esto modificará el Ingress para redirigir todo el tráfico HTTP a HTTPS

¿Continuar? (s/n): s

ℹ️  Creando Middleware de redirección...
✅ Middleware creado

ℹ️  Actualizando Ingress con redirección...
✅ Ingress actualizado con redirección

✅ Redirección HTTPS activada correctamente
```

### diagnostico.sh - Script Unificado de Diagnóstico

**Propósito**: Realiza un diagnóstico completo del despliegue mostrando qué funciona y qué no.

**Uso**:
```bash
bash scripts/diagnostico.sh
```

**Características**:
- Verificación de prerequisitos (kubectl, conexión al cluster)
- Validación de namespace y recursos (Deployment, Service, Ingress)
- Estado de pods y réplicas
- Verificación de cert-manager y certificados
- Diagnóstico de DNS y conectividad
- Detección de IPs privadas vs públicas
- Resumen con estadísticas (pasadas/advertencias/fallidas)
- Recomendaciones personalizadas según los problemas detectados

**Secciones de diagnóstico**:
1. **Prerequisitos**: kubectl, cluster, nodos
2. **Namespace y Recursos**: Deployment, Pods, Service
3. **Ingress y Networking**: Ingress, DNS, accesibilidad HTTP
4. **Cert-Manager**: ClusterIssuer, Certificate, Orders, Challenges
5. **DNS Avanzado**: CoreDNS, conectividad interna
6. **Resumen**: Estadísticas y recomendaciones

**Modo interactivo**:
Por defecto, el script pausa entre secciones. Para ejecutarlo sin pausas:
```bash
INTERACTIVE=false bash scripts/diagnostico.sh
```

**Ejemplo de salida**:
```
========================================
  1. VERIFICACIÓN DE PREREQUISITOS
========================================

Verificando kubectl...
✅ kubectl está instalado

Verificando conexión al cluster...
✅ Conectado al cluster K3s

========================================
  RESUMEN DE DIAGNÓSTICO
========================================

Total de verificaciones: 24

✅ Pasadas: 20
⚠️  Advertencias: 3
❌ Fallidas: 1

✅ Estado general: BUENO (83%)
```

### delete.sh - Limpieza de Recursos

**Propósito**: Elimina todos los recursos de Nginx desplegados en el cluster.

**Uso**:
```bash
bash scripts/delete.sh
```

**Características**:
- Confirmación interactiva (requiere escribir 'si')
- Elimina el namespace completo (incluye todos los recursos)
- Elimina el ClusterIssuer
- Mensajes de progreso y confirmación

**Ejemplo**:
```bash
$ bash scripts/delete.sh

========================================
  ELIMINANDO RECURSOS DE NGINX
========================================

Se eliminarán los siguientes recursos:
  - Namespace: nginx-namespace
  - ClusterIssuer: letsencrypt-prod

⚠️  Esta acción es IRREVERSIBLE

¿Estás seguro? (escribe 'si' para confirmar): si

ℹ️  Eliminando namespace nginx-namespace...
✅ Namespace eliminado

ℹ️  Eliminando ClusterIssuer letsencrypt-prod...
✅ ClusterIssuer eliminado

✅ Limpieza completada
```

## Flujo de Uso Recomendado

### 1. Después de la Instalación
```bash
# Ejecutar diagnóstico completo
bash scripts/diagnostico.sh
```

### 2. Si Hay Problemas con Certificados
```bash
# El diagnóstico mostrará el estado detallado
bash scripts/diagnostico.sh

# Revisar logs de cert-manager (sugerido por el diagnóstico)
kubectl logs -n cert-manager -l app=cert-manager --tail=50
```

### 3. Para Limpiar y Reiniciar
```bash
# Eliminar todo
bash scripts/delete.sh

# Volver a instalar
bash 00-install.sh
```

## Ventajas del Nuevo Enfoque

### Antes (5 scripts separados):
- Información fragmentada
- Difícil saber qué script ejecutar
- Duplicación de código
- Sin resumen consolidado

### Ahora (2 scripts unificados):
- Todo en un lugar: Un solo comando para diagnosticar todo
- Resumen estadístico: Saber de un vistazo qué porcentaje funciona
- Recomendaciones inteligentes: Sugiere qué hacer según los problemas
- Sin duplicación: Usa funciones compartidas de `lib/`
- Configuración centralizada: Lee de `config.env`
- Consistencia visual: Usa helpers para colores y formato

## Personalización

### Variables de Entorno

Puedes sobrescribir variables sin modificar los scripts:

```bash
# Cambiar namespace
NAMESPACE="mi-namespace" bash scripts/diagnostico.sh

# Modo no interactivo
INTERACTIVE=false bash scripts/diagnostico.sh

# Cambiar dominio
DOMAIN="otro-dominio.com" bash scripts/diagnostico.sh
```

### Integración con CI/CD

El script de diagnóstico puede usarse en pipelines:

```yaml
# Ejemplo GitHub Actions
- name: Validate Deployment
  run: |
    INTERACTIVE=false bash scripts/diagnostico.sh
```

## Solución de Problemas Comunes

### El diagnóstico muestra advertencias sobre el certificado

**Causa**: El certificado puede tardar 2-5 minutos en emitirse.

**Solución**:
```bash
# Esperar y volver a ejecutar
sleep 120
bash scripts/diagnostico.sh
```

### El diagnóstico muestra IP privada

**Causa**: El Ingress tiene una IP privada, Let's Encrypt no puede validarla.

**Soluciones**:
1. Usar ngrok o Cloudflare Tunnel
2. Configurar port forwarding
3. Usar LoadBalancer con IP pública

### El DNS no resuelve

**Causa**: El dominio aún no apunta al servidor.

**Solución**:
1. Obtén la IP del Ingress: `kubectl get ingress -n nginx-namespace`
2. Actualiza tu DNS para apuntar a esa IP
3. Espera propagación (hasta 24 horas, usualmente minutos)

## Comandos Útiles Adicionales

```bash
# Monitorear certificado en tiempo real
kubectl get certificate -n nginx-namespace -w

# Ver logs de cert-manager
kubectl logs -n cert-manager -l app=cert-manager -f

# Ver eventos del namespace
kubectl get events -n nginx-namespace --sort-by='.lastTimestamp'

# Probar HTTPS
curl -I https://tu-dominio.com

# Ver todos los recursos
kubectl get all,ingress,certificate -n nginx-namespace
```
