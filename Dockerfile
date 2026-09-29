# =============================================================================
#  Dockerfile
#  Version web de prueba, para publicar en Railway (ver docs/despliegue.md).
#
#  Dos etapas:
#   1. compilar: instala Flutter y compila lib/main_web.dart a HTML + JS.
#   2. servir:   una imagen chica con Caddy que solo entrega esos archivos.
#
#  POR QUE DOS ETAPAS: Flutter pesa cerca de 2 GB y solo hace falta para
#  compilar. La imagen que queda corriendo en Railway lleva unos 30 MB.
#
#  POR QUE FLUTTER DESDE git Y NO UNA IMAGEN YA HECHA: se fija exactamente la
#  version del CI (ci.yml), y no se depende de que un tercero siga publicando
#  esa imagen.
# =============================================================================

# buildpack-deps es la imagen oficial de Debian con las herramientas de
# compilacion ya instaladas (git, curl, unzip, xz). Flutter necesita esas
# cuatro y asi no hay que instalar nada con apt.
FROM buildpack-deps:bookworm AS compilar

# Misma version que .github/workflows/ci.yml. Si cambia una, cambiar la otra.
ARG FLUTTER_VERSION=3.35.0

RUN git clone --depth 1 --branch ${FLUTTER_VERSION} \
      https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"

# Solo las herramientas de web: no hace falta nada de Android aqui.
RUN flutter config --no-analytics --enable-web \
 && flutter precache --web

WORKDIR /app

# Las dependencias van antes que el codigo: si solo cambia el codigo, Railway
# reutiliza esta capa y no las vuelve a descargar.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

# Descarga sqlite3.wasm (SQLite compilado para el navegador) en la version
# que corresponde al paquete del pubspec.lock.
RUN dart run sqflite_common_ffi_web:setup

# La fuente Roboto va DENTRO de la version web. Sin ella, el navegador la
# pide a Google al abrir la app, y donde eso esta bloqueado el texto no se
# dibuja. Se agrega aqui y no en el pubspec.yaml del repo: en Android la
# fuente del sistema ya es Roboto, y declararla en el pubspec la meteria
# duplicada en el APK. El archivo sale del propio Flutter clonado arriba.
#
# Las lineas se agregan al final del pubspec, asi que la ultima seccion tiene
# que ser `flutter:`. Si alguien la mueve, el grep detiene la compilacion en
# vez de dejar la fuente en una seccion equivocada.
RUN mkdir -p fuentes_web \
 && cp /opt/flutter/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf \
       /opt/flutter/engine/src/flutter/txt/third_party/fonts/Roboto-Medium.ttf \
       fuentes_web/ \
 && grep -E '^[a-z_]+:' pubspec.yaml | tail -n 1 | grep -qx 'flutter:' \
 && printf '%s\n' \
      '  fonts:' \
      '    - family: Roboto' \
      '      fonts:' \
      '        - asset: fuentes_web/Roboto-Regular.ttf' \
      '        - asset: fuentes_web/Roboto-Medium.ttf' \
      '          weight: 500' >> pubspec.yaml

# --pwa-strategy=none: sin service worker. Con el, el navegador guarda una
# copia de la app y despues de cada despliegue seguiria mostrando la vieja.
#
# --no-web-resources-cdn: el motor grafico de Flutter (CanvasKit) se sirve
# desde Railway y no desde los servidores de Google. Misma razon que la
# fuente: que la app no dependa de otro servidor para abrir.
RUN flutter build web \
      --target lib/main_web.dart \
      --release \
      --pwa-strategy=none \
      --no-web-resources-cdn


FROM caddy:2-alpine AS servir

COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=compilar /app/build/web /srv
