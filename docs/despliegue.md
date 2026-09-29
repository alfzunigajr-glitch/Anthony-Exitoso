# Versión web en Railway

Una copia de la app que corre en el navegador, para revisar la interfaz desde cualquier computador o celular sin instalar el APK.

**No sirve para cargar datos reales.** Cada navegador guarda su propia base (IndexedDB): lo que se registra en el computador no aparece en el celular, y borrar los datos del navegador lo borra todo. La app real es el APK, que guarda en el teléfono.

---

## Qué se publica

| Archivo | Para qué |
|---|---|
| `lib/main_web.dart` | Punto de entrada web: SQLite en WebAssembly y datos de ejemplo en el primer arranque |
| `web/` | Página que envuelve la app: barra de "versión de prueba", botón "Empezar de cero" y marco de teléfono en pantallas anchas |
| `Dockerfile` | Instala Flutter 3.35.0 (la misma versión del CI), compila la versión web y la sirve con Caddy |
| `Caddyfile` | Servidor de archivos. Usa el puerto que asigna Railway (`PORT`) |
| `railway.json` | Le dice a Railway que use el `Dockerfile` |

El APK no cambia: `main.dart` no importa nada de esto.

---

## Publicarlo por primera vez

1. Entra a [railway.com](https://railway.com) con tu cuenta de GitHub.
2. **New Project → Deploy from GitHub repo** y elige `Anthony-Exitoso`.
   Si no aparece, Railway te pide darle acceso al repositorio en GitHub: dáselo solo a ese repo.
3. Railway detecta `railway.json` y empieza a compilar. **La primera vez tarda unos 5 minutos**, casi todo en descargar Flutter y compilar. Si solo cambió el código, Railway reutiliza lo ya descargado y tarda menos.
4. Cuando termine (círculo verde), ve a **Settings → Networking → Generate Domain**.
   Te da una dirección tipo `app-ganado-production.up.railway.app`. Esa es la que abres desde cualquier lado.

Rama que publica: la rama principal del repo (hoy, `claude/ganaderia-project-review-mqcfv6`). Se cambia en **Settings → Source → Branch**.

---

## Después

Cada `git push` a esa rama vuelve a compilar y publicar solo. No hay que hacer nada en Railway.

Si un despliegue falla, en Railway entra al despliegue rojo → **Build Logs**, copia el error y pásalo.

**Costo:** Railway da un crédito de prueba al registrarse; después, el plan Hobby cobra una cuota mensual baja. Esta app es solo archivos estáticos y consume muy poco. Si no la vas a usar por un tiempo, en **Settings** puedes pausar el servicio.

---

## Probarlo en tu computador sin Railway

Con Docker instalado:

```bash
docker build -t app-ganado-web .
docker run --rm -p 8080:8080 app-ganado-web
```

y abre `http://localhost:8080`.
