# Diagrama de Flujo: Despliegue con Let's Encrypt

## Flujo Visual Completo

```
┌─────────────────────────────────────────────────────────────────┐
│                    FASE 1: PREPARACIÓN                          │
└─────────────────────────────────────────────────────────────────┘

    ┌────────────────────┐
    │ cert-manager       │
    │ instalado?         │
    └──────┬─────────────┘
           │ NO
           ├──────────────┐
           │              ▼
           │    ┌─────────────────────────────────┐
           │    │ kubectl apply -f                │
           │    │ cert-manager.yaml               │
           │    └─────────────────────────────────┘
           │              │
           │ ✅ ESPERAR   ▼
           │    ┌─────────────────────────────────┐
           │    │ kubectl wait pods cert-manager  │
           │    └─────────────────────────────────┘
           │              │
           └──────────────┘
                          │
                          ▼
           ┌─────────────────────────────────┐
           │ kubectl apply -f                │
           │ clusterissuer.yml               │
           │                                 │
           │ Configura Let's Encrypt:        │
           │ - Server ACME                   │
           │ - Email                         │
           │ - Método de validación HTTP-01  │
           └─────────────────────────────────┘
                          │
                          ▼

┌─────────────────────────────────────────────────────────────────┐
│              FASE 2: DESPLIEGUE SIN REDIRECCIÓN                 │
└─────────────────────────────────────────────────────────────────┘

           ┌─────────────────────────────────┐
           │ kubectl apply -f namespace.yml  │
           └─────────────────────────────────┘
                          │
                          ▼
           ┌─────────────────────────────────┐
           │ kubectl apply -f deployment.yml │
           │                                 │
           │ Despliega:                      │
           │ - 3 réplicas de Nginx           │
           │ - Health checks                 │
           │ - Resource limits               │
           └─────────────────────────────────┘
                          │
                          ▼
           ┌─────────────────────────────────┐
           │ kubectl apply -f service.yml    │
           │                                 │
           │ Expone internamente:            │
           │ - ClusterIP                     │
           │ - Puerto 80                     │
           └─────────────────────────────────┘
                          │
           ✅ ESPERAR     ▼
           ┌─────────────────────────────────┐
           │ Verificar: Pods Running (1/1)   │
           └─────────────────────────────────┘
                          │
                          ▼
           ┌─────────────────────────────────┐
           │ kubectl apply -f ingress.yml    │
           │                                 │
           │ ⚠️ SIN REDIRECCIÓN HTTP→HTTPS   │
           │                                 │
           │ Anotaciones:                    │
           │ ✅ cert-manager.io/cluster-issuer│
           │ ❌ NO middleware de redirección │
           └─────────────────────────────────┘
                          │
                          ▼

┌─────────────────────────────────────────────────────────────────┐
│           FASE 3: OBTENCIÓN DEL CERTIFICADO (automática)        │
└─────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────┐
    │ cert-manager detecta anotación en Ingress            │
    └───────────────────┬──────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ cert-manager crea automáticamente:                  │
    │                                                     │
    │  1. Certificate resource                           │
    │  2. CertificateRequest                             │
    │  3. Order (solicitud ACME a Let's Encrypt)         │
    │  4. Challenge (HTTP-01)                            │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ cert-manager despliega:                             │
    │                                                     │
    │  - Pod: cm-acme-http-solver-xxxxx                  │
    │  - Ingress temporal con alta prioridad             │
    │                                                     │
    │  Endpoint: /.well-known/acme-challenge/TOKEN       │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ Let's Encrypt valida:                               │
    │                                                     │
    │  GET http://tu-dominio.com/.well-known/...         │
    │                                                     │
    │  ✅ SIN REDIRECCIÓN → Acceso HTTP funciona         │
    │  ✅ Responde correctamente → Validación OK         │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ Let's Encrypt emite certificado                     │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ cert-manager:                                       │
    │                                                     │
    │  1. Guarda certificado como Secret                 │
    │  2. Marca Certificate como Ready=True              │
    │  3. Elimina pod solver                             │
    │  4. Elimina Ingress temporal                       │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
               ⏱️ Esperar 2-5 minutos
                        │
                        ▼

┌─────────────────────────────────────────────────────────────────┐
│           FASE 4: ACTIVAR REDIRECCIÓN HTTPS                     │
└─────────────────────────────────────────────────────────────────┘

    ┌──────────────────────────────────────────────────────┐
    │ Verificar certificado listo:                         │
    │                                                      │
    │ kubectl get certificate nginx-tls                    │
    │ READY = True ✅                                      │
    └───────────────────┬──────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ kubectl apply -f middleware.yml                     │
    │                                                     │
    │ Crea Middleware de Traefik:                        │
    │ - redirectScheme: https                            │
    │ - permanent: true (301)                            │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ kubectl apply -f ingress-patch.yml                  │
    │                                                     │
    │ Actualiza Ingress con:                             │
    │ ✅ Middleware de redirección                        │
    │                                                     │
    │ Anotación agregada:                                │
    │ traefik.ingress.kubernetes.io/router.middlewares   │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼

┌─────────────────────────────────────────────────────────────────┐
│                    RESULTADO FINAL                              │
└─────────────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────┐
    │ Usuario accede: http://tu-dominio.com              │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ Traefik Ingress Controller:                         │
    │                                                     │
    │ 1. Detecta request HTTP                            │
    │ 2. Aplica middleware                               │
    │ 3. Devuelve: 301 Moved Permanently                 │
    │    Location: https://tu-dominio.com                │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ Navegador redirige a:                               │
    │ https://tu-dominio.com                              │
    └───────────────────┬─────────────────────────────────┘
                        │
                        ▼
    ┌─────────────────────────────────────────────────────┐
    │ Conexión HTTPS:                                     │
    │                                                     │
    │ ✅ Certificado válido de Let's Encrypt             │
    │ ✅ TLS/SSL establecido                             │
    │ ✅ Nginx responde con contenido                    │
    └─────────────────────────────────────────────────────┘
```

## Comparación: Orden Correcto vs Incorrecto

### ❌ ORDEN INCORRECTO (Falla)

```
1. ClusterIssuer ✅
2. Namespace + Deployment + Service ✅
3. Ingress CON redirección ❌ ← Error aquí
4. Ingress redirige HTTP → HTTPS
5. Let's Encrypt intenta validar vía HTTP
6. HTTP redirige a HTTPS
7. HTTPS no funciona (sin certificado aún)
8. Challenge falla: ERR_CONNECTION_REFUSED
9. Certificado NO se emite ❌

┌───────────────────────┐
│  Let's Encrypt        │
└──────────┬────────────┘
           │ GET http://.../.well-known/...
           ▼
┌───────────────────────┐
│  Traefik Ingress      │
│  (con redirección)    │
└──────────┬────────────┘
           │ 301 → https://...
           ▼
┌───────────────────────┐
│  Cliente intenta HTTPS│
└──────────┬────────────┘
           │ ❌ Sin certificado
           ▼
   Connection Refused
```

### ✅ ORDEN CORRECTO (Funciona)

```
1. ClusterIssuer ✅
2. Namespace + Deployment + Service ✅
3. Ingress SIN redirección ✅
4. Let's Encrypt valida vía HTTP
5. HTTP funciona sin redirección
6. Challenge exitoso
7. Certificado emitido ✅
8. Middleware de redirección aplicado ✅
9. HTTP → HTTPS funciona con certificado

┌───────────────────────┐
│  Let's Encrypt        │
└──────────┬────────────┘
           │ GET http://.../.well-known/...
           ▼
┌───────────────────────┐
│  Traefik Ingress      │
│  (sin redirección)    │
└──────────┬────────────┘
           │ 200 OK + Token
           ▼
┌───────────────────────┐
│  ACME Solver Pod      │
│  ✅ Validación OK     │
└───────────────────────┘
```

## Timeline de Eventos

```
Tiempo  | Evento                          | Estado
--------|--------------------------------|------------------
T+0s    | kubectl apply ingress.yml      | Ingress creado
T+2s    | cert-manager detecta           | Certificate pendiente
T+5s    | Challenge creado               | Solver iniciándose
T+10s   | Pod solver Running             | Ingress temporal activo
T+15s   | Let's Encrypt valida           | GET /.well-known/...
T+20s   | Validación exitosa             | Challenge resuelto
T+30s   | Certificado emitido            | Secret creado
T+32s   | Certificate Ready=True ✅      | Solver eliminado
T+35s   | kubectl apply middleware       | Redirección activada
T+40s   | HTTP → HTTPS funciona ✅       | Todo operativo
```

## Comandos de Verificación por Fase

### Durante Fase 2 (Despliegue)
```bash
# Ver que pods estén listos
kubectl get pods -n nginx-namespace
# Debe mostrar: 3/3 Running

# Ver service
kubectl get svc -n nginx-namespace
# Debe tener ClusterIP

# Ver ingress (aún sin certificado)
kubectl get ingress -n nginx-namespace
# Debe tener ADDRESS asignada
```

### Durante Fase 3 (Validación)
```bash
# Ver Certificate (pendiente)
kubectl get certificate -n nginx-namespace
# READY: False

# Ver Challenge activo
kubectl get challenge -n nginx-namespace
# Debe haber 1 challenge

# Ver pod solver temporal
kubectl get pods -n nginx-namespace
# cm-acme-http-solver-xxxxx debe existir

# Ver logs en tiempo real
kubectl logs -n cert-manager -l app=cert-manager -f
```

### Después Fase 3 (Certificado listo)
```bash
# Certificate listo
kubectl get certificate -n nginx-namespace
# READY: True ✅

# Secret creado
kubectl get secret nginx-tls -n nginx-namespace
# Tipo: kubernetes.io/tls

# Challenge eliminado
kubectl get challenge -n nginx-namespace
# No items found (normal)
```

### Después Fase 4 (Redirección activa)
```bash
# Probar redirección
curl -I http://app.negociapp.com
# HTTP/1.1 301 Moved Permanently
# Location: https://app.negociapp.com

# Probar HTTPS
curl -I https://app.negociapp.com
# HTTP/2 200
```

## Resumen Visual de Estados

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Ingress creado │ ──> │ Challenge activo│ ──> │Certificate Ready│
│  HTTP accesible │     │ Validando...    │     │  HTTPS OK ✅    │
│  Sin redirección│     │ Solver running  │     │  Redirección OK │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        2s                      30s                      +30s
```

## Recursos Creados en Cada Fase

### Fase 1
```
✅ ClusterIssuer: letsencrypt-prod
```

### Fase 2
```
✅ Namespace: nginx-namespace
✅ Deployment: nginx (3 réplicas)
✅ Service: nginx (ClusterIP)
✅ Ingress: nginx (sin redirección)
```

### Fase 3 (Automático por cert-manager)
```
✅ Certificate: nginx-tls
✅ CertificateRequest: nginx-tls-xxxxx
✅ Order: nginx-tls-xxxxx-yyyyy
✅ Challenge: nginx-tls-xxxxx-yyyyy-zzzzz
✅ Pod: cm-acme-http-solver-zzzzz (temporal)
✅ Ingress: cm-acme-http-solver-zzzzz (temporal)
✅ Secret: nginx-tls (con certificado)

(Recursos temporales se auto-eliminan)
```

### Fase 4
```
✅ Middleware: redirect-https
✅ Ingress: nginx (actualizado con middleware)
```

---

Ver [ORDEN-DESPLIEGUE.md](ORDEN-DESPLIEGUE.md) para instrucciones detalladas.
