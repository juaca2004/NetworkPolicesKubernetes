#Layered Security with NetworkPolicies

This document details the creation of a three-tiered microservices architecture in Kubernetes, where security is enforced using NetworkPolicies under the principle of Least Privilege.

## 1. Initial Configuration and Creation of YAML Files

### 1.1. Creation of Namespaces, Deployments, and Services (`deployments.yaml`)

The different `.yaml` files are created with the application architecture: `web` (frontend), `app` (backend), and `data` (database).

```yaml
# deployments.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: web
---
apiVersion: v1
kind: Namespace
metadata:
  name: app
---
apiVersion: v1
kind: Namespace
metadata:
  name: data
---
# Despliegue y Servicio Web (Frontend)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend-dep
  namespace: web
spec:
  replicas: 1
  selector:
    matchLabels:
      tier: frontend
  template:
    metadata:
      labels:
        tier: frontend
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: web-svc
  namespace: web
spec:
  selector:
    tier: frontend
  ports:
  - port: 80
    targetPort: 80
  type: NodePort
---
# Despliegue y Servicio Aplicacion (Backend)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend-dep
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      tier: backend
  template:
    metadata:
      labels:
        tier: backend
    spec:
      containers:
      - name: backend
        # Simula un servidor escuchando en el puerto 8080
        image: busybox
        command: ["sh", "-c", "while true; do echo -e 'HTTP/1.1 200 OK\r\n\r\nhello from backend' | nc -l -p 8080; done"]
        ports:
        - containerPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: app-svc
  namespace: app
spec:
  selector:
    tier: backend
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
---
# Despliegue y Servicio Datos (DB)
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-dep
  namespace: data
spec:
  replicas: 1
  selector:
    matchLabels:
      tier: database
  template:
    metadata:
      labels:
        tier: database
    spec:
      containers:
      - name: postgres
        image: postgres:14-alpine
        env:
        - name: POSTGRES_PASSWORD
          value: "secure_password"
        ports:
        - containerPort: 5432
---
apiVersion: v1
kind: Service
metadata:
  name: data-svc
  namespace: data
spec:
  selector:
    tier: database
  ports:
  - port: 5432
    targetPort: 5432
  type: ClusterIP
```

-----

### 1.2. NetworkPolicies: Deny by Default (`default-deny.yaml`)

This policy applies to *all* pods in each Namespace, blocking all Ingress and Egress before applying the specific rules.

```yaml
# default-deny.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: web # Se aplica tambien en 'app' y 'data'
spec:
  podSelector: {} 
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: app
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: data
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress: []
  egress: []
```

-----

### 1.3. Network Policies: Specific Rules (`network-policies.ymal`)
These rules allow the flow of `web` $\rightarrow$ `app` $\rightarrow$ `data` traffic.

```yaml
# network-policies.yaml

# ----------------- Politicas para 'web' -----------------
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-ingress-internet
  namespace: web
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 0.0.0.0/0 # Trafico externo (Internet)
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-allow-egress-to-app
  namespace: web
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: app
      podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 8080
  # DNS tambien se permite (puerto 53)
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
# ----------------- Politicas para 'app' -----------------
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-allow-ingress-from-web
  namespace: app
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: web
      podSelector:
        matchLabels:
          tier: frontend
    ports:
    - protocol: TCP
      port: 8080
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-allow-egress-to-data
  namespace: app
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: data
      podSelector:
        matchLabels:
          tier: database
    ports:
    - protocol: TCP
      port: 5432
  # DNS tambien se permite (puerto 53)
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
---
# ----------------- Politicas para 'data' -----------------
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: data-allow-ingress-from-app
  namespace: data
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  - Egress # Se incluye para aplicar la regla vacia de Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: app
      podSelector:
        matchLabels:
          tier: backend
    ports:
    - protocol: TCP
      port: 5432
  egress: [] # Niega EXPLÍCITAMENTE todo el trafico de salida
```

-----

## 2. Applying Architecture and Policies

Run the following commands in the PowerShell console, making sure you are in the same directory as the YAML files.

```powershell
# 1. Aplicar Namespaces y deployements"
apply -f namespaces.yaml,web-deployment.yaml,app-deployment.yaml,data-deployment.yaml
```
<img width="1441" height="251" alt="image" src="https://github.com/user-attachments/assets/89097fc2-9db1-46aa-93c4-752bba45d70e" />




```powershell
# 2. Aplicar Politicas de Denegar por Defecto
kubectl apply -f default-deny.yaml
```
<img width="1103" height="79" alt="image" src="https://github.com/user-attachments/assets/2472a465-b832-478b-a7d4-eac1f55b91f5" />


```powershell
# 4. Aplicar Politicas Especificas de Flujo
kubectl apply -f network-policies.yaml
```
<img width="1162" height="205" alt="image" src="https://github.com/user-attachments/assets/01bcc0fb-c28a-47a1-ae93-488575530f92" />

-----
## 3. Security Test Script (`test-policies.ps1`)

The `test-policies.ps1` file is created with the following contents. This script validates whether **allowed** connections succeed and whether **blocked** connections fail/block.

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

## 4. Running the Script

Simply run the script in PowerShell:

```powershell
.\test-policies.ps1
```
<img width="898" height="537" alt="image" src="https://github.com/user-attachments/assets/1c7d88a4-b6a5-42dc-8274-4e6cecde3242" />

The output will clearly indicate whether layered security was implemented SUCCESSFULLY or if there were security FAILURES.
