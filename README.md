# NetworkPolicesKubernetes

Claro. Aquí tienes el documento `README.md` completamente actualizado con la arquitectura alternativa, los scripts de PowerShell corregidos (sin tildes ni 'ñ') y los procedimientos de prueba detallados.

-----

# README: Implementacion de Seguridad por Capas con NetworkPolicies en Kubernetes

## Descripcion

El objetivo de este proyecto es demostrar la implementacion de un **modelo de seguridad por capas** (defense-in-depth) en una aplicacion de tres niveles (Web, Aplicacion, Datos) desplegada en Kubernetes. Para ello, se utilizan **NetworkPolicies** para asegurar el **Minimo Privilegio** en la comunicacion de red.

Cada capa reside en su propio Namespace, garantizando que el trafico solo fluya en la direccion permitida: **Web $\rightarrow$ Aplicacion $\rightarrow$ Datos**.

-----

## 1\. Arquitectura de la Aplicacion

La aplicacion se distribuye en tres Namespaces aislados logicamente. La comunicacion se basa en la etiqueta de pod **`tier`**.

| Capa | Namespace | Etiqueta de Pod | Puerto de Comunicacion | Servicio | Acceso Externo |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Web (Frontend)** | `web` | `tier: frontend` | 80 | Nginx | `NodePort` |
| **Aplicacion (Backend)** | `app` | `tier: backend` | 8080 | BusyBox (simulado) | `ClusterIP` |
| **Datos (DB)** | `data` | `tier: database` | 5432 | PostgreSQL | `ClusterIP` |

-----

## 2\. Estrategia de NetworkPolicies

Se aplica una estrategia de **Denegar por Defecto** a todos los pods de todos los Namespaces. Posteriormente, se definen las siguientes reglas explicitas:

| Namespace | Tipo de Regla | Origen/Destino Permitido | Puerto | Proposito |
| :--- | :--- | :--- | :--- | :--- |
| `web` | Ingress | `0.0.0.0/0` (Internet) | 80 | Permite acceso externo. |
| `web` | Egress | `app` (tier: backend) | 8080 | Permite comunicacion al Backend. |
| `app` | Ingress | `web` (tier: frontend) | 8080 | Acepta trafico solo del Frontend. |
| `app` | Egress | `data` (tier: database) | 5432 | Permite comunicacion a la Base de Datos. |
| `data` | Ingress | `app` (tier: backend) | 5432 | Acepta trafico solo del Backend. |
| `data` | Egress | **Ninguno** (`egress: []` explicito) | - | Bloquea toda salida de la DB para maxima seguridad. |

-----

## 3\. Implementacion y Pruebas (PowerShell)

### 3.1. Proceso de Implementacion

Se asume que los archivos YAML de Namespaces, Despliegues, Servicios y NetworkPolicies (separados en `default-deny.yaml` y `network-policies.yaml`) estan presentes. El siguiente script se utiliza para aplicar toda la configuracion:

```powershell
# apply-all.ps1 - Comandos clave

# Aplicar Namespaces y Despliegues
kubectl apply -f namespaces.yaml,deployments.yaml

# Esperar a que los pods esten listos (importante antes de las pruebas)
kubectl wait --for=condition=Ready pod -l tier=frontend -n web --timeout=90s
kubectl wait --for=condition=Ready pod -l tier=backend -n app --timeout=90s
kubectl wait --for=condition=Ready pod -l tier=database -n data --timeout=90s

# Aplicar Politicas de Seguridad
kubectl apply -f default-deny.yaml
kubectl apply -f network-policies.yaml
```

### 3.2. Script de Pruebas de Seguridad

El script `test-policies.ps1` automatiza la validacion usando `nc -z` y el codigo de salida de PowerShell (`$LASTEXITCODE`) para mostrar si las conexiones fueron **permitidas (Exito)** o **bloqueadas (Bloqueado)**.

**Contenido del script `test-policies.ps1` (sin tildes ni 'ñ'):**

```powershell
# test-policies.ps1

Write-Host "--- INICIANDO PRUEBAS DE NETWORKPOLICIES ---`n"

# --- 1. OBTENER NOMBRES DE PODS ---
Write-Host "Obteniendo nombres de pods..."
$FRONTEND_POD = $(kubectl get pods -n web -l tier=frontend -o jsonpath='{.items[0].metadata.name}')
$BACKEND_POD = $(kubectl get pods -n app -l tier=backend -o jsonpath='{.items[0].metadata.name}')
$DB_POD = $(kubectl get pods -n data -l tier=database -o jsonpath='{.items[0].metadata.name}')
Write-Host "Frontend Pod: $FRONTEND_POD"
Write-Host "Backend Pod:  $BACKEND_POD"
Write-Host "DB Pod:       $DB_POD`n"

# --- 2. PRUEBAS DE CONECTIVIDAD PERMITIDA (EXITO ESPERADO) ---
Write-Host "## 2. Flujo Valido (Debe ser EXITO)"

# Prueba 2.1: Web -> Aplicacion (Frontend a Backend)
Write-Host "  Probando: Frontend -> Backend (app-svc.app:8080)"
kubectl exec -it $FRONTEND_POD -n web -- nc -z app-svc.app 8080
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ EXITO: Flujo Web -> App permitido."
} else {
    Write-Host "  ❌ FALLO INESPERADO: Web no puede hablar con App. Revisar politicas de Egress en 'web'."
}

# Prueba 2.2: Aplicacion -> Datos (Backend a DB)
Write-Host "  Probando: Backend -> DB (data-svc.data:5432)"
kubectl exec -it $BACKEND_POD -n app -- nc -z data-svc.data 5432
if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✅ EXITO: Flujo App -> Data permitido."
} else {
    Write-Host "  ❌ FALLO INESPERADO: App no puede hablar con DB. Revisar politicas de Egress en 'app'."
}
Write-Host ""

# --- 3. PRUEBAS DE CONECTIVIDAD DENEGADA (BLOQUEO ESPERADO) ---
Write-Host "## 3. Flujo Invalido (Debe ser BLOQUEADO)"

# Prueba 3.1: Datos -> Aplicacion (DB Egress Denegado)
Write-Host "  Probando: DB -> Backend (Violacion de Egress)"
kubectl exec -it $DB_POD -n data -- nc -w 2 -z app-svc.app 8080 # -w 2 establece un timeout de 2s
if ($LASTEXITCODE -ne 0) {
    Write-Host "  🚫 BLOQUEADO: Conexión denegada. El Egress de la DB funciona correctamente."
} else {
    Write-Host "  ⚠️ FALLO DE SEGURIDAD: La DB puede comunicarse hacia afuera. Revisar 'egress: []' en 'data'."
}

# Prueba 3.2: Web -> Datos (Salto de Capa)
Write-Host "  Probando: Frontend -> DB (Salto de capa)"
kubectl exec -it $FRONTEND_POD -n web -- nc -w 2 -z data-svc.data 5432 # -w 2 establece un timeout de 2s
if ($LASTEXITCODE -ne 0) {
    Write-Host "  🚫 BLOQUEADO: Conexión denegada. El Frontend no puede saltar al DB."
} else {
    Write-Host "  ⚠️ FALLO DE SEGURIDAD: El Frontend puede conectarse al DB. Revisar Ingress en 'data'."
}

# Prueba 3.3: Aplicacion -> Web (Flujo Inverso)
Write-Host "  Probando: Backend -> Frontend (Flujo Inverso)"
kubectl exec -it $BACKEND_POD -n app -- nc -w 2 -z web-svc.web 80 # -w 2 establece un timeout de 2s
if ($LASTEXITCODE -ne 0) {
    Write-Host "  🚫 BLOQUEADO: Conexión denegada. El Backend no puede conectarse al Frontend."
} else {
    Write-Host "  ⚠️ FALLO DE SEGURIDAD: El Backend puede conectarse al Frontend. Revisar Ingress en 'web'."
}
Write-Host "`n--- VERIFICACION DE POLITICAS COMPLETADA ---"
```

### 3.3. Ejecucion del Script

Ejecuta el script desde tu consola de PowerShell:

```powershell
.\test-policies.ps1
```

-----

## 4\. Resultados Esperados

Si todas las NetworkPolicies se aplicaron correctamente, la salida de `test-policies.ps1` deberia ser la siguiente:

| Prueba | Direccion de Trafico | Resultado Esperado | Explicacion de la Politica |
| :--- | :--- | :--- | :--- |
| **2.1** | `web` $\rightarrow$ `app` | ✅ EXITO | Flujo de aplicacion permitido. |
| **2.2** | `app` $\rightarrow$ `data` | ✅ EXITO | Flujo de aplicacion permitido. |
| **3.1** | `data` $\rightarrow$ `app` | 🚫 BLOQUEADO | Egress bloqueado en la DB por `egress: []`. |
| **3.2** | `web` $\rightarrow$ `data` | 🚫 BLOQUEADO | Ingress de `data` solo acepta `app`. |
| **3.3** | `app` $\rightarrow$ `web` | 🚫 BLOQUEADO | Ingress de `web` solo acepta trafico externo. |