# Alcance — qué falta construir

Estado al 29 de septiembre de 2026.
Leer `CLAUDE.md` antes que esto: contiene las reglas que no se negocian.

---

## Lo que ya existe y funciona

| Capa | Estado |
|---|---|
| Esquema SQL (11 tablas, 5 vistas, 2 triggers) | Verificado contra base real |
| Protección anti-duplicación | Verificada con pruebas |
| Modelos (9) | Compilados |
| DAOs (5) | Compilados y probados |
| Pruebas (44) | En verde (Flutter 3.35.0) |
| `pantalla_inicio` | Escrita; enlaza al hato y avisa si está vacío |
| `pantalla_evento` | Escrita y probada en navegador |
| `pantalla_animal_nuevo` (T1) | Hecha, con pruebas |
| `pantalla_hato` (T2) | Hecha, con pruebas |
| Tema y tokens de diseño | Escritos |
| CI en GitHub Actions | Configurado |

---

## El problema que bloqueaba todo — resuelto

~~No hay forma de dar de alta un animal.~~ Resuelto con T1 y T2: el hato se carga desde el botón **Hato** de la pantalla de inicio, que además avisa cuando el hato está vacío.

**Sigue abierto el problema hermano:** `pantalla_inicio` muestra bloques de retiro de leche y caídas de producción, pero no existe ninguna pantalla que cree tratamientos ni registros de producción. Esos bloques van a estar siempre vacíos hasta que se construyan sus formularios.

---

## Tareas en orden de prioridad

### T1 · Alta de animal — HECHO

`lib/ui/pantalla_animal_nuevo.dart`

Formulario mínimo. Todo campo de más es una razón para no cargar el hato.

**Campos obligatorios:** arete interno, sexo, categoría, fecha de ingreso
**Campos opcionales:** nombre, arete oficial, fecha de nacimiento (con marca de estimada), raza

Criterios de aceptación:
- Llamar `AnimalDao.crear()` con los datos del formulario
- Si el arete ya existe en la finca, la restricción `UNIQUE` lanza excepción: capturarla y mostrar un mensaje claro, no dejar que reviente la app
- Toques de 56 px, texto de 17 px
- Al guardar, ofrecer "guardar y agregar otro": cargar un hato de 30 animales en sesiones de un animal por pantalla es inviable
- Fecha de nacimiento con interruptor "es aproximada" que alimente `nacimiento_estimado`

### T2 · Lista del hato — HECHO

Mientras no exista la ficha (T3), tocar una fila abre el registro de un caso con ese animal ya elegido.

`lib/ui/pantalla_hato.dart`

Criterios de aceptación:
- Usar `AnimalDao.listarActivos()` y `AnimalDao.buscar()`
- Buscador en la parte superior
- Cada fila: arete, nombre, categoría. Altura mínima 56 px
- Botón para agregar animal (lleva a T1)
- Tocar una fila abre la ficha (T3)
- Estado vacío con acción: si no hay animales, el texto debe llevar directo a agregar el primero
- Enlazar desde `pantalla_inicio`

### T3 · Ficha del animal

`lib/ui/pantalla_animal.dart`

Criterios de aceptación:
- Datos del animal y su edad (`Animal.edadDias`)
- Días en leche (`EventoReproductivoDao.diasEnLeche()`)
- Historial sanitario (`EventoSaludDao.porAnimal()`), lo más reciente arriba
- Historial reproductivo (`EventoReproductivoDao.porAnimal()`)
- Si tiene retiro de leche vigente (`TratamientoDao.retiroDeAnimal()`), mostrarlo destacado arriba
- Botón para registrar caso, con el animal ya preseleccionado
- Los eventos que no sirven para entrenar se marcan con `EventoSalud.motivoNoSirve` y se pueden completar tocándolos

### T4 · Registrar tratamiento

`lib/ui/pantalla_tratamiento.dart`

Sin esto, el bloque de retiro de leche de la pantalla de inicio nunca muestra nada. **Es la función con valor práctico inmediato para Jhon**, y de que la app le sirva depende que la use.

Criterios de aceptación:
- Se abre desde un evento de salud existente
- Campos: fármaco, fecha y hora de aplicación, días de retiro de leche, días de retiro de carne
- Precargar con `TratamientoDao.farmacosFrecuentes()`: al elegir un fármaco usado antes, rellenar sus días de retiro
- Llamar `TratamientoDao.crear()`
- Tras guardar, si hay retiro de leche, confirmarlo en pantalla con la fecha hasta la que no se puede entregar

### T5 · Captura de producción

`lib/ui/pantalla_produccion.dart`

Alimenta `detectarCaidas()`, que es el precursor del algoritmo de la Fase 3 y se puede probar sin ningún sensor.

Criterios de aceptación:
- Elegir fecha y ordeño (1 o 2)
- Lista de vacas en lactancia con un campo numérico por vaca
- Usar `ProduccionDao.faltantes()` para mostrar cuántas quedan por registrar. Ese contador es lo que hace que el registro se complete en vez de quedar a medias
- Guardar con `ProduccionDao.guardarLote()`, no en un bucle de llamadas sueltas
- Teclado numérico con decimales
- Avanzar al siguiente campo con la tecla "siguiente" del teclado, sin tocar la pantalla

### T6 · Por completar

`lib/ui/pantalla_por_completar.dart`

El contador ya existe en la pantalla de inicio pero no se puede abrir.

Criterios de aceptación:
- Usar `EventoSaludDao.incompletos()`
- Cada fila dice qué le falta (`EventoSalud.motivoNoSirve`)
- Tocar abre la edición del evento
- Al completarlo, el contador de la pantalla de inicio sube

### T7 · Respaldo de la base — RIESGO CRÍTICO

`lib/ui/pantalla_respaldo.dart`

Si se pierde la base, se pierden meses de eventos sanitarios que no se pueden reconstruir. No existen en ningún otro lado.

Criterios de aceptación:
- Copiar el archivo `.db` a la carpeta de descargas del teléfono
- Compartirlo con el selector del sistema (`share_plus`) para subirlo a Drive o WhatsApp
- Mostrar cuándo fue el último respaldo
- Avisar si pasaron más de 7 días sin respaldar

### T8 · Eventos reproductivos

`lib/ui/pantalla_repro.dart`

Criterios de aceptación:
- Un formulario para los seis tipos, con los campos que cambian según el tipo elegido
- El aborto se registra con `EventoReproductivoDao.registrarAborto()`
- Para celo, pedir el método de detección: cuando llegue el collar, esa columna permite comparar detección visual contra sensor
- El momento se elige igual que en `pantalla_evento`: botones en lenguaje natural, precisión deducida

---

## Fuera de alcance (Fase 2 en adelante)

No construir sin discutirlo. El código escrito hoy contra hardware que no existe se reescribe después.

- DAOs de `dispositivo`, `asignacion_dispositivo`, `observacion_conductual`
- Cualquier cosa de Bluetooth o LoRa
- Sincronización con servidor o nube
- Versión web
- Integración con el arete oficial de Agrocalidad / SIFAE
- Multiusuario

Las tablas ya están en el esquema para no tener que migrar después. Sus pantallas y DAOs, no.

---

## Cómo trabajar

Una tarea a la vez, en orden. Después de cada una:

```bash
flutter analyze --fatal-infos
flutter test
```

Si la tarea agregó una consulta SQL con lógica no trivial, agregar su prueba en `test/dao_test.dart` siguiendo el patrón existente: fecha fija, base en memoria, un caso que debe pasar y uno que no.

Antes de escribir una pantalla nueva, leer `lib/ui/pantalla_evento.dart`: es la referencia de estilo, de estructura y de cómo se resuelve el presupuesto de 30 segundos.
