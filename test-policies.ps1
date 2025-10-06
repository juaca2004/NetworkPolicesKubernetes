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