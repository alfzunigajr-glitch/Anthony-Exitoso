# =============================================================================
#  subir_a_github.ps1
#
#  Deja el proyecto en GitHub con el flujo de compilacion automatica activo.
#
#  COMO USARLO:
#   1. Abre PowerShell
#   2. Ve a la carpeta del proyecto:   cd C:\dev\app_ganado
#   3. Ejecuta:                        .\subir_a_github.ps1
#
#  Si Windows bloquea el script, permitelo solo para esta sesion:
#     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# =============================================================================

$ErrorActionPreference = "Stop"   # Detenerse al primer error en vez de seguir

$NOMBRE_REPO = "app-ganado"
$DESCRIPCION = "Registro del hato - Fase 1 del proyecto de monitoreo ganadero"

# Ejecuta un programa externo (git, gh) sin que PowerShell 5.1 convierta lo que
# escribe en stderr en un error fatal. Devuelve la salida; el resultado real se
# consulta en $LASTEXITCODE.
function Ejecutar {
    param([Parameter(ValueFromRemainingArguments = $true)] $argumentos)
    $anterior = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $comando = $argumentos[0]
        $resto = @($argumentos | Select-Object -Skip 1)
        & $comando @resto 2>&1 | ForEach-Object { "$_" }
    } finally {
        $ErrorActionPreference = $anterior
    }
}

Write-Host ""
Write-Host "=== Subir app-ganado a GitHub ===" -ForegroundColor Cyan
Write-Host ""

# -----------------------------------------------------------------------------
# 1. Comprobar que estamos en la carpeta correcta
# -----------------------------------------------------------------------------
if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "No encuentro pubspec.yaml." -ForegroundColor Red
    Write-Host "Ejecuta el script desde la carpeta del proyecto (ej. C:\dev\app_ganado)"
    exit 1
}

if (-not (Test-Path ".github/workflows/ci.yml")) {
    Write-Host "Aviso: no existe .github/workflows/ci.yml" -ForegroundColor Yellow
    Write-Host "El codigo se subira, pero GitHub no compilara el APK automaticamente."
    Write-Host ""
}

# -----------------------------------------------------------------------------
# 2. Instalar git y GitHub CLI si faltan
#    winget viene con Windows 10 y 11, no hay que instalarlo aparte.
# -----------------------------------------------------------------------------
function Falta($comando) {
    return -not (Get-Command $comando -ErrorAction SilentlyContinue)
}

if (Falta "git") {
    Write-Host "Instalando git..." -ForegroundColor Yellow
    winget install --id Git.Git -e --source winget --accept-package-agreements
    Write-Host ""
    Write-Host "git quedo instalado. CIERRA esta ventana, abre otra y vuelve a ejecutar." -ForegroundColor Yellow
    Write-Host "(PowerShell no ve los programas nuevos hasta que se reinicia)"
    exit 0
}

if (Falta "gh") {
    Write-Host "Instalando GitHub CLI..." -ForegroundColor Yellow
    winget install --id GitHub.cli -e --source winget --accept-package-agreements
    Write-Host ""
    Write-Host "GitHub CLI quedo instalado. CIERRA esta ventana, abre otra y vuelve a ejecutar." -ForegroundColor Yellow
    exit 0
}

# git necesita nombre y correo para poder hacer commits. En una instalacion
# nueva no estan, y sin ellos el commit falla.
$nombreGit = Ejecutar git config user.name
if (-not $nombreGit) {
    $nombreGit = Read-Host "Tu nombre para los commits de git"
    git config --global user.name "$nombreGit"
}
$correoGit = Ejecutar git config user.email
if (-not $correoGit) {
    $correoGit = Read-Host "Tu correo para los commits de git"
    git config --global user.email "$correoGit"
}

# -----------------------------------------------------------------------------
# 3. Autenticarse
#    Abre el navegador para que entres con TU cuenta. La contrasenia nunca pasa
#    por el script: GitHub devuelve un token que queda guardado en Windows.
# -----------------------------------------------------------------------------
Ejecutar gh auth status | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Vas a entrar a GitHub en el navegador." -ForegroundColor Yellow
    Write-Host "Elige: GitHub.com  ->  HTTPS  ->  Authenticate with browser"
    Write-Host ""
    gh auth login
    if ($LASTEXITCODE -ne 0) {
        Write-Host "No se pudo iniciar sesion en GitHub." -ForegroundColor Red
        exit 1
    }
}

$usuario = (gh api user --jq .login)
Write-Host "Conectado como: $usuario" -ForegroundColor Green
Write-Host ""

# -----------------------------------------------------------------------------
# 4. Preparar el repositorio local
# -----------------------------------------------------------------------------
if (-not (Test-Path ".git")) {
    # 'main' en vez de 'master': es el nombre por defecto en GitHub desde 2020
    # y el que espera el archivo ci.yml.
    git init -b main
    Write-Host "Repositorio local creado" -ForegroundColor Green
}

# Comprobacion de seguridad: que la clave de firma no este por subirse.
# Si sube una vez, queda en el historial de git para siempre aunque la borres.
$claves = Get-ChildItem -Recurse -Include *.jks, *.keystore, key.properties `
          -ErrorAction SilentlyContinue
if ($claves) {
    $rastreadas = $claves | Where-Object {
        # -q: no imprime nada; solo el codigo de salida (0 = ignorado)
        Ejecutar git check-ignore -q $_.FullName | Out-Null
        $LASTEXITCODE -ne 0
    }
    if ($rastreadas) {
        Write-Host "CUIDADO: hay claves de firma sin ignorar:" -ForegroundColor Red
        $rastreadas | ForEach-Object { Write-Host "   $($_.Name)" }
        Write-Host "Revisa el .gitignore antes de continuar." -ForegroundColor Red
        exit 1
    }
}

git add .
$salida = Ejecutar git commit -m "Fase 1: esquema, capa de datos, pruebas y pantallas iniciales"
if ($LASTEXITCODE -eq 0) {
    Write-Host "Cambios guardados" -ForegroundColor Green
} elseif ($salida -match "nothing to commit|nada para hacer commit") {
    Write-Host "No hay cambios nuevos" -ForegroundColor Yellow
} else {
    Write-Host "No se pudo hacer el commit:" -ForegroundColor Red
    $salida | ForEach-Object { Write-Host "   $_" }
    exit 1
}

# -----------------------------------------------------------------------------
# 5. Crear el repositorio en GitHub y subir
#    --private porque es trabajo propio y va a referenciar datos de una finca
#    real. Se puede abrir despues; lo que no se puede es cerrar lo que ya se vio.
# -----------------------------------------------------------------------------
Ejecutar gh repo view "$usuario/$NOMBRE_REPO" | Out-Null
if ($LASTEXITCODE -eq 0) {
    Write-Host "El repositorio ya existe, subiendo cambios..." -ForegroundColor Yellow
    Ejecutar git remote get-url origin | Out-Null
    if ($LASTEXITCODE -ne 0) {
        git remote add origin "https://github.com/$usuario/$NOMBRE_REPO.git"
    }
    git push -u origin main
} else {
    Write-Host "Creando el repositorio..." -ForegroundColor Yellow
    gh repo create $NOMBRE_REPO --private --source=. --description $DESCRIPCION --push
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "La subida fallo. Revisa el mensaje de arriba." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== Listo ===" -ForegroundColor Green
Write-Host ""
Write-Host "Repositorio:  https://github.com/$usuario/$NOMBRE_REPO"
Write-Host "Compilacion:  https://github.com/$usuario/$NOMBRE_REPO/actions"
Write-Host ""
Write-Host "El APK tarda unos 5 minutos. Cuando el circulo este verde, entra a"
Write-Host "la ejecucion y descargalo desde la seccion Artifacts."
Write-Host ""
Write-Host "De aqui en adelante, para subir cambios:" -ForegroundColor Cyan
Write-Host "   git add ."
Write-Host "   git commit -m 'lo que cambiaste'"
Write-Host "   git push"
Write-Host ""
