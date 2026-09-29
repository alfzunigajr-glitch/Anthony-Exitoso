# CLAUDE.md

Contexto permanente del proyecto. Se carga en cada sesión.

---

## Qué es esto

App Flutter de registro sanitario de ganado lechero, para una finca de la Sierra ecuatoriana.

**No es una app de gestión ganadera.** Es un instrumento para producir un conjunto de datos etiquetados que en una fase posterior se cruzará contra la señal de un acelerómetro (collar LoRa 915 MHz) para entrenar un detector temprano de enfermedad.

Esa distinción decide todo. Cada decisión se juzga por: *¿esto mejora la calidad o la cantidad de las etiquetas de entrenamiento?*

**Usuarios reales:**
- Jhon: veterinario y dueño de la finca. Registra junto al animal, a las 5 a.m., con manos frías o mojadas. Antes llevaba todo en papel.
- Anthony: ingeniero, desarrolla el sistema.

---

## Stack

- Flutter, Dart 3
- sqflite (SQLite nativo). Sin backend, sin red, sin nube.
- Esquema SQL en `assets/sql/`, cargado por migraciones
- Pruebas con `flutter_test` + `sqflite_common_ffi`

---

## Reglas que no se negocian

Romper cualquiera de estas corrompe el dataset de forma silenciosa. No hay excepciones sin discutirlo primero.

### 1. `ABORTO` nunca entra en `catalogo_diagnostico`

El aborto vive **solo** en `evento_reproductivo`. Su ausencia del catálogo no es un olvido: es el mecanismo. La clave foránea de `evento_salud` lo rechaza por construcción, así que no puede contarse dos veces.

### 2. Nunca `DELETE`

Todo borrado es lógico: `UPDATE ... SET eliminado = 1`. Una etiqueta que desaparece rompe el entrenamiento sin dejar rastro.

Excepción: ninguna.

### 3. Todas las fechas pasan por `lib/core/fechas.dart`

`DateTime.now().toIso8601String()` de Dart **no incluye el desplazamiento horario**. El esquema espera `-05:00`. Usar el método nativo deja fechas ambiguas que después no se pueden alinear contra la señal del sensor.

- Instantes → `aIso()` / `desdeIso()`
- Días sueltos → `aFecha()`
- Nunca mezclar formatos en una misma columna

### 4. Identificadores UUID v4, nunca autoincrementales

Dos teléfonos registrando a la vez generarían los mismos enteros y la sincronización quedaría irreparable.

### 5. Toda lectura de etiquetas sale de `v_etiquetas`

Nunca consultar `evento_salud` y `evento_reproductivo` por separado y sumar. `v_etiquetas` es la fuente única y garantiza que no haya duplicación.

### 6. Los tres timestamps de `evento_salud` son sagrados

| Campo | Significado |
|---|---|
| `ts_inicio_estimado` | Cuándo empezó de verdad. Es la etiqueta. |
| `ts_deteccion_humana` | Cuándo lo notó una persona. **Es la marca que el algoritmo debe vencer.** |
| `ts_registro` | Cuándo se digitó. Lo pone la app, el usuario nunca lo toca. |

Sin el segundo no se puede demostrar que el collar se adelanta al ojo humano, que es toda la propuesta de valor.

### 7. `precision_ts_inicio` se deduce, no se pregunta

El usuario elige "ahora mismo", "esta mañana", "ayer", "hace 2 o 3 días", "no lo sé". De ahí salen la fecha y la precisión. **Nunca mostrar un desplegable de precisión**: nadie lo llena y la gente inventa fechas para no dejar el campo vacío.

---

## Convenciones de código

### Idioma

- Nombres de clases, métodos, variables y archivos: **español**
- Comentarios: **español**
- Archivos `.sql`: **sin tildes ni ñ** (evita problemas de codificación entre sistemas)
- Archivos `.dart`: comentarios sin tildes; texto visible al usuario **con** tildes y ñ correctas

### Comentarios

Se comenta **por qué**, no qué. Anthony es ingeniero en electrónica y automatización, no desarrollador de Dart: los comentarios existen para que entienda el razonamiento, no para narrar el código.

```dart
// MAL
// Incrementa el contador
contador++;

// BIEN
// Se compara en mayúsculas para que dé igual cómo esté escrito el SQL
final mayus = linea.toUpperCase();
```

Cuando una decisión tiene alternativas razonables, explicar por qué se descartaron. Ejemplo del código existente: por qué `ON CONFLICT DO UPDATE` y no `ConflictAlgorithm.replace`.

### Estructura

```
lib/
├── core/        fechas.dart, tema.dart — utilidades transversales
├── data/
│   ├── db/      app_database.dart — conexión y migraciones
│   ├── models/  un archivo por entidad
│   └── dao/     un archivo por entidad; TODO el SQL vive aquí
└── ui/          pantallas; comunes.dart tiene las piezas repetidas
```

Los botones de opción, la fila de fecha, el contador de ±1 y las respuestas a "¿cuándo empezó?" viven en `ui/comunes.dart`. Una pantalla nueva los usa de ahí: si cada una tuviera su copia, "Esta mañana" terminaría significando cosas distintas en dos formularios.

Ninguna pantalla ejecuta SQL directamente. Si hace falta una consulta nueva, va en el DAO correspondiente.

### Modelos

- Campos `final`, objetos inmutables
- `factory X.desdeFila(Map)` para leer
- `Map<String, Object?> aFila()` para escribir
- `copyWith()` para "modificar"
- Booleanos: `0`/`1` en SQLite, `bool` en Dart, conversión en el modelo

### DAOs

- Parámetros con `?`, nunca concatenar valores en el SQL
- Cortes por día (columnas `AAAA-MM-DD`) se calculan en Dart con `aFecha()` y se pasan como parámetro. Nunca `date('now')`: SQLite lo da en UTC y en Ecuador, desde las 19:00, ya es el día siguiente. Además deja las pruebas atadas al reloj real
- Errores de restricción que la persona puede corregir (arete repetido) se traducen en el DAO a una excepción propia (`AreteRepetido`). La pantalla no conoce sqflite
- `ConflictAlgorithm.abort` por defecto: un conflicto debe avisar, no guardarse callado
- Consultas con lógica no trivial llevan comentario explicando el algoritmo

---

## Diseño de interfaz

El contexto de uso manda. No es una app de sofá.

| Regla | Razón |
|---|---|
| Toque mínimo **56 px** (`Medida.toque`) | Dedos fríos, manos mojadas. Los 48 de Material fallan. |
| Texto mínimo **17 px** (`Tipo.cuerpo`) | Lectura a un brazo de distancia |
| Contraste alto | Bajo sol directo los grises claros desaparecen |
| Tipografía del sistema | Una fuente descargada falla sin señal, que es lo normal en la finca |
| Colores solo de `Colores` | Ningún color decorativo; todos significan algo |

**Presupuesto de tiempo: registrar un caso en menos de 30 segundos.** Toda pantalla nueva se juzga contra eso. Un paso de navegación de más es un motivo válido para rediseñar.

Se puede guardar incompleto. Un registro a medias es infinitamente mejor que ninguno: la app lo lista después en "por completar".

---

## Verificar antes de dar algo por terminado

```bash
flutter analyze --fatal-infos    # sin advertencias, ni siquiera sugerencias
flutter test                     # las 52 pruebas en verde
```

Toda consulta SQL nueva con lógica no trivial necesita su prueba en `test/dao_test.dart`. El patrón está en las pruebas existentes: fecha fija (`fechaBase`), base en memoria, un caso que debe pasar y uno que no.

Las pantallas nuevas llevan su prueba en `test/pantallas_test.dart`. Toda operación de base dentro de `testWidgets` va en `tester.runAsync()`: el reloj de las pruebas de pantalla es falso y la base nunca respondería.

---

## Problemas conocidos

**`UPSERT` requiere Android 10 o superior.** `ProduccionDao.guardar()` usa `ON CONFLICT DO UPDATE`, que necesita SQLite 3.24. Android 9 trae 3.22 y falla. Pendiente confirmar la versión del teléfono de Jhon.

**Compilado y probado** con Flutter 3.35.0 el 29 de septiembre de 2026: `flutter analyze --fatal-infos` limpio y 52 pruebas en verde. El APK todavía no se ha compilado (lo hace el CI al subir el proyecto).

**Firma con clave de depuración.** Cambiar a una clave propia después de que Jhon instale obligaría a desinstalar, y eso borra la base de datos.

---

## Qué falta

Ver `docs/alcance.md` para el detalle con criterios de aceptación.
