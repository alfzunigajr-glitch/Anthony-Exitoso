# Subir el proyecto a GitHub — todo en un solo lugar

Proyecto: app de registro del hato (Fase 1)
Sistema: Windows

---

## Resumen de lo que vas a hacer

1. Crear cuenta de GitHub (si no tienes)
2. Crear el proyecto base con `flutter create`
3. Colocar los 29 archivos en su carpeta
4. Ejecutar un script que sube todo
5. Ver el APK compilarse solo

Tiempo: unos 40 minutos la primera vez, casi todo esperando descargas.

---

## Parte 1 · Requisitos

| Necesitas | Cómo conseguirlo |
|---|---|
| Cuenta de GitHub | `github.com/signup` — gratis |
| Flutter instalado | Ver guía de instalación, pasos 1 y 2 |
| Git | El script lo instala solo |
| GitHub CLI | El script lo instala solo |

**Si no tienes cuenta de GitHub:** créala antes de empezar. Usa un correo al que tengas acceso permanente, no uno del trabajo — este repositorio te va a acompañar todo el proyecto.

Activa también la verificación en dos pasos cuando te la ofrezca. Si pierdes la cuenta, pierdes el historial.

---

## Parte 2 · Crear el proyecto base

Los archivos que tienes son solo el código. Falta toda la parte de plataforma (carpeta `android/`, Gradle, permisos, íconos), y eso lo genera Flutter.

Abre PowerShell:

```powershell
# Ruta CORTA. Windows tiene límite de 260 caracteres por ruta y Gradle lo revienta.
mkdir C:\dev
cd C:\dev

flutter create app_ganado
cd app_ganado
```

Esto crea un proyecto de ejemplo funcional. Ahora lo reemplazas por el código real.

**Borra estos dos archivos de ejemplo:**

```powershell
Remove-Item lib\main.dart
Remove-Item test\widget_test.dart
```

Si los dejas, las pruebas fallan por código que no tiene nada que ver con el proyecto.

---

## Parte 3 · Colocar los archivos

Descarga los 29 archivos y ponlos con **exactamente** esta estructura. Las rutas importan: si un archivo queda en otra carpeta, las importaciones no lo encuentran.

```
C:\dev\app_ganado\
│
├── .gitignore                          ← raíz
├── pubspec.yaml                        ← reemplaza el que generó flutter create
├── subir_a_github.ps1                  ← raíz
│
├── .github\
│   └── workflows\
│       └── ci.yml
│
├── assets\
│   └── sql\
│       ├── v1_esquema.sql
│       └── v2_parche.sql
│
├── lib\
│   ├── main.dart
│   │
│   ├── core\
│   │   ├── fechas.dart
│   │   └── tema.dart
│   │
│   ├── data\
│   │   ├── db\
│   │   │   └── app_database.dart
│   │   │
│   │   ├── models\
│   │   │   ├── animal.dart
│   │   │   ├── diagnostico.dart
│   │   │   ├── evento_reproductivo.dart
│   │   │   ├── evento_salud.dart
│   │   │   ├── finca.dart
│   │   │   ├── medicion_corporal.dart
│   │   │   ├── produccion_leche.dart
│   │   │   └── tratamiento.dart
│   │   │
│   │   └── dao\
│   │       ├── animal_dao.dart
│   │       ├── evento_reproductivo_dao.dart
│   │       ├── evento_salud_dao.dart
│   │       ├── produccion_dao.dart
│   │       └── tratamiento_dao.dart
│   │
│   └── ui\
│       ├── pantalla_evento.dart
│       └── pantalla_inicio.dart
│
└── test\
    ├── ayuda_pruebas.dart
    ├── dao_test.dart
    ├── esquema_test.dart
    └── fechas_test.dart
```

**Ojo con dos detalles:**

La carpeta `.github` empieza con punto. El Explorador de Windows la oculta por defecto: activa *Vista → Elementos ocultos* para verla. Es más fácil crearla desde PowerShell:

```powershell
mkdir .github\workflows
```

Y el nombre del archivo `ci.yml` debe ser exacto, dentro de `.github\workflows\`. Si está en otro lado, GitHub no lo ejecuta y no te avisa por qué.

### Comprobar que quedó bien

```powershell
flutter pub get
flutter analyze
```

`pub get` descarga las dependencias. `analyze` revisa que no falten archivos ni haya errores de tipo.

Si `analyze` reporta algo, mándamelo tal cual antes de subir.

---

## Parte 4 · Subir a GitHub

```powershell
cd C:\dev\app_ganado

# Permite ejecutar el script solo en esta ventana.
# Al cerrarla, Windows vuelve a su configuración normal.
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\subir_a_github.ps1
```

### Qué va a pasar

1. **Instala git y GitHub CLI** si no los tienes. Después de cada instalación te va a pedir que cierres la ventana y abras otra: PowerShell no ve los programas nuevos hasta reiniciarse. Vuelve a ejecutar el script.

2. **Te autentica.** Se abre el navegador. Elige:
   - `GitHub.com`
   - `HTTPS`
   - `Authenticate with browser`

   Aparece un código de 8 caracteres, lo pegas en el navegador y confirmas.

   **Tu contraseña nunca pasa por el script.** GitHub devuelve un token que Windows guarda en su almacén de credenciales.

3. **Revisa que no subas claves.** Si encuentra un `.jks` o `key.properties` sin ignorar, se detiene. Es intencional: una clave de firma que sube una vez queda en el historial de git para siempre.

4. **Crea el repositorio privado y sube todo.**

Al terminar te imprime dos enlaces: el del repositorio y el de las compilaciones.

---

## Parte 5 · Ver el APK compilarse

Entra a `https://github.com/TU-USUARIO/app-ganado/actions`

Vas a ver la ejecución corriendo. Dos etapas:

| Etapa | Qué hace | Tarda |
|---|---|---|
| Pruebas | `flutter analyze` y `flutter test` | ~2 min |
| APK | `flutter build apk --release` | ~4 min |

**Si sale verde:** entra a la ejecución y baja hasta *Artifacts*. Ahí está el APK listo para mandarle a Jhon.

**Si sale rojo:** haz clic en la etapa que falló, despliega el paso rojo y copia el mensaje de error. Mándamelo y lo corregimos.

Es bastante probable que la primera vez falle. No pude ejecutar Dart en mi entorno, así que escribí el código sin compilador. La lógica SQL sí quedó verificada, pero puede haber algún error de tipo o una importación faltante. Es normal y se arregla rápido.

---

## Parte 6 · El día a día

Cada vez que cambies algo:

```powershell
git add .
git commit -m "describe lo que cambiaste"
git push
```

Y con cada `push`, GitHub compila un APK nuevo solo.

Comandos que vas a usar seguido:

| Comando | Para qué |
|---|---|
| `git status` | Qué archivos cambiaste |
| `git log --oneline` | Historial de cambios |
| `git diff` | Ver exactamente qué cambió |
| `gh repo view --web` | Abrir el repositorio en el navegador |
| `gh run list` | Ver las últimas compilaciones |
| `gh run watch` | Seguir la compilación en curso desde la terminal |

---

## Problemas frecuentes

**`No se reconoce el término 'flutter'`**
El PATH no quedó, o la ventana de PowerShell es anterior a la instalación. Abre una nueva.

**`No se puede cargar el archivo subir_a_github.ps1`**
Falta el `Set-ExecutionPolicy` de la Parte 4. Es por sesión: hay que repetirlo cada vez que abras una ventana nueva.

**`fatal: not a git repository`**
No estás en la carpeta del proyecto. Haz `cd C:\dev\app_ganado`.

**El workflow no aparece en Actions**
El archivo no está en `.github\workflows\ci.yml` exactamente, o la indentación del YAML se dañó al copiarlo. YAML es sensible a los espacios: no admite tabulaciones, solo espacios.

**`Unable to load asset: assets/sql/v1_esquema.sql`**
Falta la sección `assets:` en `pubspec.yaml`, o los `.sql` no están en `assets\sql\`.

**`gh: command not found` después de instalarlo**
Cierra PowerShell y abre otra ventana.

---

## Antes de que Jhon instale nada

Un punto que es mejor resolver ahora que dentro de seis meses.

Flutter firma las versiones de release con una **clave de depuración** por defecto. Funciona para instalar y probar. Pero el día que generes una clave propia, Android va a rechazar la actualización con "aplicación no instalada", y la única salida es desinstalar.

**Desinstalar borra la base de datos.** Meses de eventos sanitarios que no se reconstruyen.

Se evita creando la clave antes de la primera instalación:

```powershell
keytool -genkey -v -keystore C:\dev\clave-ganado.jks -keyalg RSA `
  -keysize 2048 -validity 10000 -alias ganado
```

Guarda ese archivo y su contraseña en un gestor de contraseñas o un disco externo. Si se pierden no se regeneran.

El `.gitignore` ya está preparado para que nunca suban al repositorio.

Cuando quieras, te paso la configuración para que el proyecto y el workflow de GitHub usen esa clave.

---

## Lo siguiente

1. `flutter analyze` sin errores
2. Proyecto subido y compilación en verde
3. APK instalado en un Android (emulador o teléfono real)
4. Crear la clave de firma
5. Faltan las pantallas de alta de animales y lista del hato: sin ellas no hay a quién registrarle nada
6. Cargar el hato de Jhon
7. Cronometrar cuánto tarda él en registrar un caso sin que le expliques nada

El último punto es el que decide la Compuerta 1.
