# Orden Correcto de Despliegue para Let's Encrypt

## Problema: ¿Por qué importa el orden?

Let's Encrypt necesita **acceso HTTP sin redirección** al endpoint `/.well-known/acme-challenge/*` para validar que controlas el dominio. Si rediriges HTTP→HTTPS **antes** de obtener el certificado, la validación fallará.

## Flujo Correcto: 3 Fases

### Fase 1: Preparación (ClusterIssuer)
### Fase 2: Despliegue Inicial (Sin Redirección)
### Fase 3: Activar Redirección (Después del Certificado)

---

## 📋 Orden Detallado de Comandos

### Paso 1: Verificar Prerequisitos

```bash
# Verificar que cert-manager está instalado
kubectl get namespace cert-manager

# Si NO está instalado:
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

# Esperar a que esté listo (importante)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=300s
```

### Paso 2: Crear ClusterIssuer (Configuración de Let's Encrypt)

```bash
kubectl apply -f k8s/base/clusterissuer.yml
```

**¿Qué hace?**
- Configura cert-manager para usar Let's Encrypt
- Define cómo validar el dominio (HTTP-01 challenge)
- Se crea ANTES de cualquier certificado

**Verificar:**
```bash
kubectl get clusterissuer letsencrypt-prod
# Debe mostrar READY=True
```

### Paso 3: Crear Namespace

```bash
kubectl apply -f k8s/base/namespace.yml
```

### Paso 4: Desplegar Aplicación (Deployment y Service)

```bash
kubectl apply -f k8s/base/deployment.yml
kubectl apply -f k8s/base/service.yml
```

**Verificar que los pods estén listos:**
```bash
kubectl get pods -n nginx-namespace
# Esperar a que todos estén Running y Ready (1/1)
```

### Paso 5: Crear Ingress SIN Redirección

```bash
kubectl apply -f k8s/base/ingress.yml
```

**¿Por qué SIN redirección?**
- Let's Encrypt necesita acceso HTTP al endpoint `/.well-known/acme-challenge/TOKEN`
- La anotación `cert-manager.io/cluster-issuer` hace que cert-manager cree automáticamente:
  - Un Certificate resource
  - Un CertificateRequest
  - Un Order (ACME)
  - Uno o más Challenges
  - Un Ingress temporal para el challenge

**Verificar Ingress:**
```bash
kubectl get ingress -n nginx-namespace
# Debe tener una IP/ADDRESS asignada
```

### Paso 6: Esperar el Certificado (2-5 minutos)

```bash
# Monitorear en tiempo real
kubectl get certificate -n nginx-namespace -w

# Ver estado detallado
kubectl describe certificate nginx-tls -n nginx-namespace
```

**Estados del certificado:**
1. `Pending` → Solicitando certificado
2. `Ready: False` → En proceso de validación
3. `Ready: True` → ✅ Certificado obtenido

**Si tarda más de 5 minutos, diagnosticar:**
```bash
bash scripts/diagnostico.sh
```

### Paso 7: Activar Redirección HTTPS (Después del Certificado)

**SOLO cuando el certificado esté Ready=True:**

```bash
# Verificar primero
kubectl get certificate nginx-tls -n nginx-namespace -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
# Debe devolver: True

# Entonces aplicar redirección
kubectl apply -f k8s/overlays/with-redirect/middleware.yml
kubectl apply -f k8s/overlays/with-redirect/ingress-patch.yml
```

**O usar Kustomize:**
```bash
kubectl apply -k k8s/overlays/with-redirect
```

---

## 🎯 Resumen: Orden Completo

```bash
# 1. ClusterIssuer (configuración Let's Encrypt)
kubectl apply -f k8s/base/clusterissuer.yml

# 2. Namespace
kubectl apply -f k8s/base/namespace.yml

# 3. Deployment y Service
kubectl apply -f k8s/base/deployment.yml
kubectl apply -f k8s/base/service.yml

# 4. Ingress SIN redirección
kubectl apply -f k8s/base/ingress.yml

# 5. Esperar certificado
kubectl wait --for=condition=ready certificate/nginx-tls -n nginx-namespace --timeout=600s

# 6. Activar redirección HTTPS
kubectl apply -k k8s/overlays/with-redirect
```

---

## ⚡ Método Rápido con Kustomize

### Opción A: Despliegue en 2 Pasos (Recomendado)

```bash
# Paso 1: Desplegar sin redirección
kubectl apply -k k8s/overlays/simple

# Paso 2: Esperar certificado (2-5 minutos)
kubectl wait --for=condition=ready certificate/nginx-tls -n nginx-namespace --timeout=600s

# Paso 3: Activar redirección
kubectl apply -k k8s/overlays/with-redirect
```

### Opción B: Todo de Una Vez (Avanzado)

```bash
# Despliega con redirección desde el inicio
kubectl apply -k k8s/overlays/with-redirect
```

**¿Por qué funciona esto?**
- Traefik tiene 2 Ingress con prioridades diferentes
- El Ingress temporal del challenge tiene mayor prioridad
- Let's Encrypt puede acceder sin redirección

**⚠️ Advertencia:** Método avanzado, puede fallar si:
- Traefik no maneja prioridades correctamente
- Hay problemas de configuración
- Es la primera vez que configuras esto

---

## 🔍 ¿Qué Pasa Internamente?

### Durante la Fase de Validación (Paso 6)

Cuando aplicas el Ingress con `cert-manager.io/cluster-issuer`, **automáticamente**:

1. **cert-manager crea un Certificate**
   ```bash
   kubectl get certificate -n nginx-namespace
   ```

2. **cert-manager crea un Order (solicitud ACME)**
   ```bash
   kubectl get order -n nginx-namespace
   ```

3. **cert-manager crea un Challenge**
   ```bash
   kubectl get challenge -n nginx-namespace
   ```

4. **cert-manager crea un Ingress temporal**
   ```bash
   kubectl get ingress -n nginx-namespace
   # Verás: cm-acme-http-solver-xxxxx
   ```

5. **cert-manager despliega un pod solver**
   ```bash
   kubectl get pods -n nginx-namespace
   # Verás: cm-acme-http-solver-xxxxx
   ```

6. **Let's Encrypt accede vía HTTP**
   ```
   http://tu-dominio.com/.well-known/acme-challenge/TOKEN_RANDOM
   ```

7. **Si la validación es exitosa:**
   - cert-manager obtiene el certificado
   - Lo guarda como Secret
   - Marca el Certificate como Ready=True
   - Elimina el solver y su Ingress temporal

---

## ❌ Errores Comunes

### Error 1: Aplicar Redirección Demasiado Pronto

```bash
# ❌ INCORRECTO: Redirección antes del certificado
kubectl apply -k k8s/overlays/with-redirect  # Sin certificado previo

# Resultado:
# - Let's Encrypt intenta acceder vía HTTP
# - El servidor redirige a HTTPS
# - HTTPS no funciona porque NO HAY certificado
# - Challenge falla: ERR_CONNECTION_REFUSED o similar
```

### Error 2: No Esperar a que los Pods Estén Listos

```bash
# ❌ INCORRECTO: Crear Ingress sin pods listos
kubectl apply -f k8s/base/deployment.yml
kubectl apply -f k8s/base/ingress.yml  # Inmediatamente

# Resultado:
# - Ingress apunta a pods que no existen
# - Let's Encrypt recibe 503 Service Unavailable
# - Challenge falla
```

### Error 3: Dominio No Apunta al Servidor

```bash
# Verificar ANTES de aplicar:
dig +short tu-dominio.com

# Debe devolver la IP pública del servidor
# Si devuelve vacío o IP incorrecta:
# - Actualizar DNS
# - Esperar propagación (hasta 24 horas)
```

### Error 4: IP Privada

```bash
# ❌ Ingress con IP privada
kubectl get ingress -n nginx-namespace
# ADDRESS: 192.168.1.100

# Resultado:
# - Let's Encrypt NO puede acceder a IPs privadas
# - Challenge falla: Connection timeout
```

**Solución:**
- Usar IP pública
- Configurar port forwarding
- Usar ngrok/Cloudflare Tunnel

---

## ✅ Validar Cada Paso

### Después del Paso 2 (ClusterIssuer)
```bash
kubectl get clusterissuer letsencrypt-prod -o yaml | grep -A 5 status
# Debe mostrar: Ready: True
```

### Después del Paso 4 (Deployment)
```bash
kubectl get deployment nginx -n nginx-namespace
# READY debe ser 3/3 (o el número de réplicas configurado)
```

### Después del Paso 5 (Ingress)
```bash
# Verificar IP asignada
kubectl get ingress nginx -n nginx-namespace
# Debe tener ADDRESS

# Verificar DNS apunta correctamente
ADDRESS=$(kubectl get ingress nginx -n nginx-namespace -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
DNS=$(dig +short app.negociapp.com | tail -1)
echo "Ingress: $ADDRESS | DNS: $DNS"
# Deben coincidir
```

### Después del Paso 6 (Certificado)
```bash
# Estado del certificado
kubectl get certificate nginx-tls -n nginx-namespace
# READY debe ser True

# Verificar Secret creado
kubectl get secret nginx-tls -n nginx-namespace
# Debe existir con tipo: kubernetes.io/tls
```

### Después del Paso 7 (Redirección)
```bash
# Probar redirección
curl -I http://app.negociapp.com
# Debe devolver: HTTP/1.1 301 Moved Permanently
# Location: https://app.negociapp.com

# Probar HTTPS
curl -I https://app.negociapp.com
# Debe devolver: HTTP/2 200
```

---

## 🚀 Scripts Automatizados

### Script de Instalación (usa el orden correcto)

```bash
bash 00-install.sh
```

**Lo que hace internamente:**
1. Verifica prerequisitos
2. Aplica en el orden correcto
3. Espera confirmación entre pasos
4. Monitorea el certificado
5. Pregunta si activar redirección

### Script de Diagnóstico

```bash
bash scripts/diagnostico.sh
```

**Verifica:**
- Orden de aplicación correcto
- Estado de cada recurso
- Problemas de DNS/IP
- Estado del certificado

---

## 📚 Documentación de Referencia

- **Arquitectura Kustomize:** [k8s/README.md](k8s/README.md)
- **Configuración:** [config.env](config.env)
- **Diagnóstico:** [scripts/README.md](scripts/README.md)
- **Cambios del Proyecto:** [CAMBIOS.md](CAMBIOS.md)

---

## 💡 Tips Pro

### Tip 1: Usar Staging de Let's Encrypt para Pruebas

Edita `k8s/base/clusterissuer.yml`:
```yaml
spec:
  acme:
    server: https://acme-staging-v02.api.letsencrypt.org/directory  # Staging
```

**Ventajas:**
- Sin límite de rate (50 certs/semana en producción)
- Certificados no confiables pero válidos para pruebas

### Tip 2: Monitorear en Tiempo Real

Terminal 1:
```bash
kubectl get certificate -n nginx-namespace -w
```

Terminal 2:
```bash
kubectl logs -n cert-manager -l app=cert-manager -f
```

### Tip 3: Debug Avanzado

```bash
# Ver eventos del namespace
kubectl get events -n nginx-namespace --sort-by='.lastTimestamp'

# Ver detalles del challenge
kubectl describe challenge -n nginx-namespace

# Probar acceso al endpoint de challenge
curl -v http://tu-dominio.com/.well-known/acme-challenge/test
```

---

## 🎓 Resumen Ejecutivo

**Orden correcto:**
1. ClusterIssuer → Configurar Let's Encrypt
2. Namespace + Deployment + Service → Aplicación funcionando
3. Ingress SIN redirección → Exponer sin bloquear HTTP
4. **ESPERAR** certificado (2-5 min) → Let's Encrypt valida vía HTTP
5. Middleware + Ingress con redirección → Redireccionar HTTP→HTTPS

**Clave del éxito:**
- ✅ Esperar entre pasos críticos
- ✅ Verificar cada paso antes de continuar
- ✅ DNS debe estar configurado ANTES
- ✅ NO redireccionar HTTP hasta tener certificado
- ✅ IP debe ser pública

**Método más seguro:**
```bash
bash 00-install.sh  # Sigue el orden correcto automáticamente
```
