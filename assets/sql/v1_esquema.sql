-- =============================================================================
--  PROYECTO: Monitoreo ganadero de bajo costo
--  MODULO:   Fase 1 - Base de datos local de la app de registro
--  MOTOR:    SQLite 3 (embebido en el telefono, funciona sin internet)
--  VERSION:  1.0
--
--  OBJETIVO DE ESTE ESQUEMA:
--  No es solo llevar el historial del hato. Es producir, sin trabajo extra,
--  un conjunto de datos etiquetados que en la Fase 3 se pueda cruzar contra
--  las series del acelerometro para entrenar y validar el algoritmo.
--  Cada decision de diseno de abajo esta tomada con ese cruce en mente.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- CONFIGURACION DEL MOTOR
-- -----------------------------------------------------------------------------

-- SQLite trae las claves foraneas DESACTIVADAS por defecto (por compatibilidad
-- historica). Sin esta linea se pueden insertar tratamientos que apuntan a
-- eventos inexistentes y la base se corrompe en silencio. Hay que ejecutarla
-- en CADA apertura de conexion, no basta con ponerla una vez al crear la base.
PRAGMA foreign_keys = ON;

-- WAL (Write-Ahead Logging): permite leer mientras se escribe. En la practica
-- evita que la app se congele si el usuario consulta una ficha justo cuando se
-- esta guardando otro registro. Tambien es mas resistente a que el telefono se
-- apague de golpe a mitad de una escritura, cosa habitual en campo.
PRAGMA journal_mode = WAL;


-- =============================================================================
--  CONVENCIONES QUE SE USAN EN TODO EL ESQUEMA
-- =============================================================================
--
--  IDs      -> TEXT con un UUID v4 generado en el telefono.
--              Motivo: cuando dos personas registren desde dos telefonos
--              distintos (tu y tu socio), los enteros autoincrementales chocan
--              (ambos generarian el id 1, 2, 3...) y la sincronizacion se
--              vuelve irreparable. El UUID es unico sin coordinacion previa.
--
--  Fechas   -> TEXT en formato ISO-8601 CON desplazamiento horario.
--              Ejemplo: '2026-08-01T06:30:00-05:00'
--              Ecuador continental es UTC-5 fijo y sin horario de verano, pero
--              se guarda el offset igual: el dia que exportes datos o compares
--              contra un log del gateway en UTC, lo vas a agradecer.
--              SQLite no tiene tipo fecha nativo; ISO-8601 es el unico formato
--              de texto que ordena cronologicamente de forma correcta.
--
--  Booleanos-> INTEGER con valor 0 o 1. SQLite tampoco tiene tipo booleano.
--
--  Borrado  -> Nunca se ejecuta DELETE. Se marca eliminado = 1.
--              Motivo: una etiqueta que desaparece del dataset rompe el
--              entrenamiento sin dejar rastro de por que.
-- =============================================================================


-- =============================================================================
--  1. FINCA
--     Una sola fila al inicio, pero se deja como tabla porque el dia que
--     entren mas fincas no hay que migrar nada.
-- =============================================================================
CREATE TABLE finca (
    id                TEXT PRIMARY KEY,          -- UUID de la finca
    nombre            TEXT NOT NULL,             -- Nombre con el que la conoce el duenio
    propietario       TEXT,                      -- Nombre del responsable
    provincia         TEXT,                      -- Para analisis por zona mas adelante
    canton            TEXT,
    latitud           REAL,                      -- Centroide aproximado. REAL = punto flotante.
    longitud          REAL,                      -- Sirve para cruzar con clima y altitud despues.
    altitud_msnm      INTEGER,                   -- Relevante: la altura afecta consumo de bateria
                                                 -- y el comportamiento termico del animal.
    creado_en         TEXT NOT NULL,             -- Auditoria: cuando se creo esta fila
    eliminado         INTEGER NOT NULL DEFAULT 0 -- Borrado logico
);


-- =============================================================================
--  2. ANIMAL
--     El sujeto de todo el sistema. Una fila por animal que ha existido en la
--     finca, incluidos los que ya salieron: sus datos historicos siguen siendo
--     validos para entrenar.
-- =============================================================================
CREATE TABLE animal (
    id                  TEXT PRIMARY KEY,        -- UUID interno. NUNCA cambia.
                                                 -- Es la llave que va a unir la ficha del
                                                 -- animal con sus series del acelerometro.

    finca_id            TEXT NOT NULL,           -- A que finca pertenece

    -- --- Identificadores visibles en campo -------------------------------
    -- Se separan del id interno a proposito: un arete se cae, se reemplaza,
    -- se reasigna. Si el identificador visible fuera la clave primaria, cada
    -- cambio de arete romperia todo el historico del animal.
    arete_oficial       TEXT,                    -- Numero del arete de Agrocalidad (trazabilidad
                                                 -- oficial). Puede llegar despues del nacimiento.
    arete_interno       TEXT,                    -- Numero de manejo que usa la finca a diario
    nombre              TEXT,                    -- Nombre comun. En lecheria de Sierra casi todas
                                                 -- las vacas tienen nombre y el ordeniador las
                                                 -- reconoce por el, no por el numero.

    -- --- Datos biologicos -------------------------------------------------
    sexo                TEXT NOT NULL,           -- 'H' hembra / 'M' macho
    fecha_nacimiento    TEXT,                    -- ISO-8601. Puede ser estimada, ver campo siguiente.
    nacimiento_estimado INTEGER NOT NULL DEFAULT 0, -- 1 si la fecha es aproximada.
                                                 -- Importante: la edad es una variable predictora
                                                 -- y no da lo mismo un dato exacto que un estimado.
    raza                TEXT,                    -- 'HOLSTEIN', 'JERSEY', 'BROWN_SWISS', 'CRIOLLO', 'MESTIZO'
    madre_id            TEXT,                    -- Autorreferencia: apunta a otro animal de esta
                                                 -- misma tabla. Permite genealogia sin tabla extra.

    -- --- Estado en el hato -----------------------------------------------
    categoria           TEXT NOT NULL,           -- 'TERNERA','VACONA','VAQUILLA','VACA_LACTANCIA',
                                                 -- 'VACA_SECA','TORO','TORETE'
                                                 -- Cambia con el tiempo; aqui se guarda la actual.
    fecha_ingreso       TEXT NOT NULL,           -- Nacimiento en la finca o fecha de compra
    activo              INTEGER NOT NULL DEFAULT 1, -- 1 = esta en el hato hoy
    fecha_salida        TEXT,                    -- NULL mientras siga activo
    motivo_salida       TEXT,                    -- 'VENTA','MUERTE','DESCARTE','ROBO'
                                                 -- 'MUERTE' es una etiqueta valiosisima: es el
                                                 -- desenlace mas severo y el mas facil de confirmar.

    -- --- Auditoria --------------------------------------------------------
    creado_en           TEXT NOT NULL,
    modificado_en       TEXT NOT NULL,
    creado_por          TEXT,                    -- Quien digito. Con dos usuarios ya importa.
    eliminado           INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (finca_id) REFERENCES finca(id),
    FOREIGN KEY (madre_id) REFERENCES animal(id),

    -- Un mismo numero de arete no puede repetirse dentro de la misma finca.
    -- Se usa UNIQUE sobre el par (finca, arete) y no sobre el arete solo,
    -- porque dos fincas distintas si pueden tener el mismo numero interno.
    UNIQUE (finca_id, arete_interno)
);


-- =============================================================================
--  3. DISPOSITIVO
--     Todavia no existe hardware, pero la tabla se crea AHORA. Motivo: si la
--     agregas en la Fase 2, tendras que migrar una base que ya tiene meses de
--     datos reales encima, con la app instalada en el telefono de tu socio.
--     Crearla vacia hoy cuesta cero.
-- =============================================================================
CREATE TABLE dispositivo (
    id                TEXT PRIMARY KEY,          -- UUID interno del dispositivo
    numero_serie      TEXT NOT NULL UNIQUE,      -- Serie grabada fisicamente en la carcasa.
                                                 -- Es lo que vas a leer en campo cuando lo recojas.
    dev_eui           TEXT,                      -- Identificador del modulo LoRa (equivalente a la MAC).
                                                 -- Es lo que viaja en cada paquete de radio, asi que
                                                 -- es la llave real para atar un paquete a un animal.
    version_hw        TEXT,                      -- 'v0.1', 'v0.2'... Cuando cambies de PCB vas a
                                                 -- necesitar saber que datos vienen de que revision.
    version_fw        TEXT,                      -- Version de firmware. Mismo motivo: un cambio en la
                                                 -- frecuencia de muestreo altera la serie y hay que
                                                 -- poder identificar donde ocurrio el cambio.
    fecha_alta        TEXT NOT NULL,
    estado            TEXT NOT NULL DEFAULT 'DISPONIBLE',
                                                 -- 'DISPONIBLE','EN_USO','AVERIADO','PERDIDO'
                                                 -- 'PERDIDO' importa: la tasa de perdida es una de
                                                 -- las metricas de exito de la Fase 3.
    creado_en         TEXT NOT NULL,
    eliminado         INTEGER NOT NULL DEFAULT 0
);


-- =============================================================================
--  4. ASIGNACION DE DISPOSITIVO  <-- TABLA CRITICA
--     Guarda el HISTORIAL completo de que dispositivo estuvo en que animal y
--     entre que fechas.
--
--     Por que no basta con una columna 'animal_id' dentro de dispositivo:
--     el collar 7 estuvo en la vaca A hasta marzo y en la vaca B desde abril.
--     Si solo guardas la asignacion actual, cuando en la Fase 3 proceses seis
--     meses de senal vas a atribuir a la vaca B datos que son de la vaca A.
--     El dataset queda contaminado y no hay forma de detectarlo despues.
--     Este es el error silencioso mas frecuente en pilotos de este tipo.
-- =============================================================================
CREATE TABLE asignacion_dispositivo (
    id                TEXT PRIMARY KEY,
    dispositivo_id    TEXT NOT NULL,
    animal_id         TEXT NOT NULL,

    ts_colocacion     TEXT NOT NULL,             -- Momento exacto en que se puso al animal.
                                                 -- Anotarlo al minuto: los primeros minutos el
                                                 -- animal se sacude y esa senal hay que descartarla.
    ts_retiro         TEXT,                      -- NULL = sigue puesto ahora mismo

    posicion          TEXT NOT NULL DEFAULT 'COLLAR',
                                                 -- 'COLLAR','ARETE_IZQ','ARETE_DER','PATA'
                                                 -- La posicion cambia por completo la firma del
                                                 -- acelerometro. Un modelo entrenado con datos de
                                                 -- collar no sirve para datos de arete.
    orientacion       TEXT,                      -- 'NORMAL','INVERTIDO'. Si el collar gira, los ejes
                                                 -- X/Y/Z se invierten y hay que corregirlo por software.
    motivo_retiro     TEXT,                      -- 'FIN_PILOTO','BATERIA','AVERIA','PERDIDA','SALIDA_ANIMAL'
    notas             TEXT,

    creado_en         TEXT NOT NULL,
    eliminado         INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (dispositivo_id) REFERENCES dispositivo(id),
    FOREIGN KEY (animal_id)      REFERENCES animal(id)
);


-- =============================================================================
--  5. CATALOGO DE DIAGNOSTICOS
--     Vocabulario cerrado. Sin esto, "mastitis", "Mastitis", "mastits" y "MAST"
--     son cuatro clases distintas para el algoritmo y una sola para el humano.
--     Se llena una vez, con tu socio veterinario, ANTES de empezar a registrar.
-- =============================================================================
CREATE TABLE catalogo_diagnostico (
    codigo            TEXT PRIMARY KEY,          -- 'MAST_CLIN', 'COJERA', 'NEUMONIA', 'RET_PLAC'...
    nombre            TEXT NOT NULL,             -- Nombre que ve el usuario en la pantalla
    sistema           TEXT NOT NULL,             -- 'MAMARIO','LOCOMOTOR','RESPIRATORIO','DIGESTIVO',
                                                 -- 'REPRODUCTIVO','METABOLICO','PARASITARIO','OTRO'

    -- Los tres campos siguientes son los que despues definen si un diagnostico
    -- sirve o no como etiqueta de entrenamiento:
    afecta_rumia      INTEGER NOT NULL DEFAULT 0,-- 1 si esta patologia deprime la rumia.
                                                 -- Es la senal que tu sensor pretende detectar.
    afecta_actividad  INTEGER NOT NULL DEFAULT 0,-- 1 si altera el patron de movimiento (ej. cojera)
    curso             TEXT,                      -- 'AGUDO','CRONICO','SUBCLINICO'
                                                 -- Lo subclinico casi nunca tiene un inicio datable,
                                                 -- asi que como etiqueta vale mucho menos.
    activo            INTEGER NOT NULL DEFAULT 1 -- Permite retirar un codigo sin borrar el historico
);


-- =============================================================================
--  6. EVENTO DE SALUD  <-- LA TABLA MAS IMPORTANTE DEL PROYECTO
--     Cada fila de aqui es, potencialmente, una etiqueta de entrenamiento.
--     Los tres timestamps separados son el corazon del diseno.
-- =============================================================================
CREATE TABLE evento_salud (
    id                    TEXT PRIMARY KEY,
    animal_id             TEXT NOT NULL,
    diagnostico_codigo    TEXT NOT NULL,

    -- --- LOS TRES TIEMPOS -------------------------------------------------
    -- Casi todos los sistemas del mercado guardan solo el tercero. Tu necesitas
    -- los tres y por razones distintas cada uno.

    ts_inicio_estimado    TEXT,                  -- (1) CUANDO EMPEZO en realidad.
                                                 -- Es la etiqueta: el instante alrededor del cual
                                                 -- buscaras la anomalia en la senal del sensor.
                                                 -- Casi siempre es una estimacion del veterinario.

    ts_deteccion_humana   TEXT NOT NULL,         -- (2) CUANDO ALGUIEN LO NOTO a simple vista.
                                                 -- ESTA ES LA MARCA QUE TU ALGORITMO DEBE VENCER.
                                                 -- Sin este campo no puedes demostrar que adelantas
                                                 -- 24 o 48 horas al ojo del ganadero, que es
                                                 -- literalmente toda tu propuesta de valor.

    ts_registro           TEXT NOT NULL,         -- (3) CUANDO SE DIGITO en la app.
                                                 -- Lo pone la app sola, el usuario no lo toca.
                                                 -- Sirve para medir el retraso de digitacion: si un
                                                 -- evento se registra cinco dias tarde, su
                                                 -- ts_inicio_estimado es mucho menos confiable.

    precision_ts_inicio   TEXT NOT NULL DEFAULT 'DESCONOCIDO',
                                                 -- 'EXACTO','MAS_MENOS_6H','MAS_MENOS_1D',
                                                 -- 'MAS_MENOS_3D','DESCONOCIDO'
                                                 -- Nadie sabe la hora exacta en que empezo una
                                                 -- mastitis. Si obligas a poner una hora precisa,
                                                 -- el usuario la inventa y entrenas con ruido
                                                 -- disfrazado de dato. Este campo permite ser
                                                 -- honesto y despues filtrar por calidad:
                                                 --   WHERE precision_ts_inicio IN ('EXACTO','MAS_MENOS_6H')

    -- --- Calidad del diagnostico ------------------------------------------
    metodo_diagnostico    TEXT NOT NULL,         -- 'CLINICO','LABORATORIO','NECROPSIA','PRESUNTIVO'
    confirmado            INTEGER NOT NULL DEFAULT 0, -- 1 solo si lo confirmo el veterinario.
                                                 -- Para la validacion final se usan unicamente
                                                 -- eventos confirmados. Los presuntivos sirven
                                                 -- para explorar, no para medir desempenio.
    confirmado_por        TEXT,                  -- Nombre o registro profesional del MVZ
    severidad             INTEGER,               -- Escala 1 a 3 (leve / moderado / grave).
                                                 -- Un caso grave deja una huella mas marcada en la
                                                 -- rumia; permite analizar por nivel de severidad.

    -- --- Cierre del episodio ----------------------------------------------
    ts_resolucion         TEXT,                  -- Cuando se dio por resuelto. Define la ventana
                                                 -- temporal completa del episodio.
    desenlace             TEXT,                  -- 'RECUPERADO','CRONICO','DESCARTE','MUERTE'

    notas                 TEXT,                  -- Texto libre. NO se usa para clasificar; es
                                                 -- solamente para que un humano relea el caso.
    foto_ruta             TEXT,                  -- Ruta local de una foto (ubre, pezuna, etc.)

    creado_por            TEXT,
    modificado_en         TEXT NOT NULL,
    eliminado             INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (animal_id)          REFERENCES animal(id),
    FOREIGN KEY (diagnostico_codigo) REFERENCES catalogo_diagnostico(codigo)
);


-- =============================================================================
--  7. TRATAMIENTO
--     Se separa de evento_salud porque un episodio puede llevar varias
--     aplicaciones en dias distintos. Meterlo en la misma fila obligaria a
--     inventar columnas farmaco_1, farmaco_2... que es justo lo que no se debe.
--
--     Ademas: el tratamiento ALTERA la senal. Un antiinflamatorio sube la rumia
--     por razones farmacologicas, no porque el animal se haya curado. Para
--     interpretar bien la serie hay que saber cuando se aplico que cosa.
-- =============================================================================
CREATE TABLE tratamiento (
    id                    TEXT PRIMARY KEY,
    evento_salud_id       TEXT NOT NULL,
    ts_aplicacion         TEXT NOT NULL,         -- Momento exacto de la aplicacion
    farmaco               TEXT NOT NULL,         -- Nombre comercial o principio activo
    principio_activo      TEXT,                  -- Normalizado. El comercial cambia de marca.
    dosis                 REAL,                  -- Cantidad numerica
    unidad_dosis          TEXT,                  -- 'ml','mg','g','UI'
    via                   TEXT,                  -- 'IM','IV','SC','ORAL','INTRAMAMARIA','TOPICA'
    dias_retiro_leche     INTEGER,               -- Periodo de retiro. Utilidad practica inmediata
                                                 -- para tu socio: la app puede alertar que la leche
                                                 -- de esa vaca no se puede entregar todavia.
                                                 -- Es una funcion que se vende sola.
    dias_retiro_carne     INTEGER,
    aplicado_por          TEXT,
    creado_en             TEXT NOT NULL,
    eliminado             INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (evento_salud_id) REFERENCES evento_salud(id)
);


-- =============================================================================
--  8. EVENTO REPRODUCTIVO
--     Todo el ciclo en una sola tabla, distinguido por el campo 'tipo'.
--     Alternativa descartada: una tabla por tipo (celo, servicio, palpacion,
--     parto). Serian cuatro tablas casi identicas y toda consulta cronologica
--     necesitaria un UNION de cuatro.
-- =============================================================================
CREATE TABLE evento_reproductivo (
    id                  TEXT PRIMARY KEY,
    animal_id           TEXT NOT NULL,
    tipo                TEXT NOT NULL,           -- 'CELO','SERVICIO','PALPACION','PARTO',
                                                 -- 'ABORTO','SECADO'
    ts_evento           TEXT NOT NULL,
    precision_ts        TEXT NOT NULL DEFAULT 'DESCONOCIDO', -- Misma escala que en evento_salud

    metodo_deteccion    TEXT,                    -- Para tipo='CELO': 'VISUAL','MONTA','PARCHE',
                                                 --   'PODOMETRO','SENSOR'
                                                 -- Cuando llegue tu sensor podras comparar la
                                                 -- deteccion visual contra la del dispositivo
                                                 -- sobre el mismo animal y el mismo ciclo.

    resultado           TEXT,                    -- Para 'PALPACION': 'PRENIADA','VACIA','DUDOSA'
                                                 -- Un servicio seguido de palpacion PRENIADA
                                                 -- confirma retroactivamente que el celo era real.
                                                 -- Esa es tu unica etiqueta de celo verdaderamente
                                                 -- confiable; el resto es apreciacion visual.

    servicio_tipo       TEXT,                    -- 'MONTA_NATURAL','IA'
    identificador_semen TEXT,                    -- Codigo de pajuela o identificacion del toro
    numero_servicio     INTEGER,                 -- 1er, 2do, 3er servicio de esta lactancia
    crias_nacidas       INTEGER,                 -- Para tipo='PARTO'
    dificultad_parto    INTEGER,                 -- Escala 1 a 4. Un parto distocico deja una firma
                                                 -- muy clara en la actividad previa y posterior.
    ejecutado_por       TEXT,
    notas               TEXT,

    creado_en           TEXT NOT NULL,
    modificado_en       TEXT NOT NULL,
    eliminado           INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (animal_id) REFERENCES animal(id)
);


-- =============================================================================
--  9. PRODUCCION DE LECHE
--     Registro por ordenio, no por dia. La caida de produccion es un indicador
--     temprano de enfermedad casi tan bueno como la rumia, y es un dato que la
--     finca ya toma todos los dias. Es tu variable de contraste gratuita.
-- =============================================================================
CREATE TABLE produccion_leche (
    id                TEXT PRIMARY KEY,
    animal_id         TEXT NOT NULL,
    fecha             TEXT NOT NULL,             -- Solo la fecha, formato 'YYYY-MM-DD'
    ordenio           INTEGER NOT NULL,          -- 1 = manianiero, 2 = tarde.
                                                 -- Separarlos importa: la caida suele aparecer
                                                 -- primero en un solo ordenio.
    litros            REAL NOT NULL,
    ts_ordenio        TEXT,                      -- Hora real, si se conoce
    creado_en         TEXT NOT NULL,
    eliminado         INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (animal_id) REFERENCES animal(id),

    -- Impide registrar dos veces el mismo ordenio del mismo dia para el mismo
    -- animal, que es el error de digitacion mas comun en este tipo de registro.
    UNIQUE (animal_id, fecha, ordenio)
);


-- =============================================================================
-- 10. PESO Y CONDICION CORPORAL
-- =============================================================================
CREATE TABLE medicion_corporal (
    id                TEXT PRIMARY KEY,
    animal_id         TEXT NOT NULL,
    fecha             TEXT NOT NULL,
    peso_kg           REAL,
    metodo_peso       TEXT,                      -- 'BASCULA','CINTA','ESTIMADO'
                                                 -- La cinta bovina tiene un error del 5 al 10 %.
                                                 -- Saber el metodo evita interpretar como cambio
                                                 -- real lo que es solo error de medicion.
    condicion_corporal REAL,                     -- Escala 1 a 5, en pasos de 0.25
    creado_en         TEXT NOT NULL,
    eliminado         INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (animal_id) REFERENCES animal(id)
);


-- =============================================================================
-- 11. OBSERVACION CONDUCTUAL
--     Tabla de Fase 2, creada desde ya por la misma razon que 'dispositivo'.
--     Aqui van las 20-30 horas de observacion directa con cronometro que
--     necesitas para validar que el acelerometro distingue rumia de pastoreo.
--     Sin estas filas no puedes afirmar que tu sensor detecta rumia; solo que
--     detecta movimiento.
-- =============================================================================
CREATE TABLE observacion_conductual (
    id                TEXT PRIMARY KEY,
    animal_id         TEXT NOT NULL,
    ts_inicio         TEXT NOT NULL,             -- Al segundo. Esta es la referencia contra la
    ts_fin            TEXT NOT NULL,             -- que se alinea la serie del acelerometro.
    conducta          TEXT NOT NULL,             -- 'RUMIA','PASTOREO','DESCANSO_ECHADA',
                                                 -- 'DESCANSO_PARADA','CAMINATA','BEBIENDO','OTRO'
    postura           TEXT,                      -- 'PARADA','ECHADA'. La misma rumia genera una
                                                 -- senal distinta parada que echada.
    observador        TEXT NOT NULL,             -- Quien observo. Dos personas etiquetan distinto;
                                                 -- hay que poder medir esa discrepancia.
    confianza         INTEGER,                   -- 1 a 3. Si el observador dudo, la fila vale menos
                                                 -- como verdad de terreno.
    creado_en         TEXT NOT NULL,
    eliminado         INTEGER NOT NULL DEFAULT 0,

    FOREIGN KEY (animal_id) REFERENCES animal(id)
);


-- =============================================================================
-- 12. INDICES
--     Un indice es una estructura auxiliar que acelera las busquedas a costa de
--     algo de espacio y de escrituras marginalmente mas lentas. Se crean solo
--     sobre las columnas por las que realmente se filtra.
--     Regla practica: indexa lo que va en el WHERE, no lo que va en el SELECT.
-- =============================================================================

-- La consulta mas frecuente de la app: "dame el historial de este animal".
CREATE INDEX idx_evento_salud_animal   ON evento_salud(animal_id, ts_deteccion_humana);
CREATE INDEX idx_evento_repro_animal   ON evento_reproductivo(animal_id, ts_evento);
CREATE INDEX idx_produccion_animal     ON produccion_leche(animal_id, fecha);
CREATE INDEX idx_tratamiento_evento    ON tratamiento(evento_salud_id);

-- La consulta clave de la Fase 3: "que animal llevaba este dispositivo el dia X".
CREATE INDEX idx_asignacion_disp       ON asignacion_dispositivo(dispositivo_id, ts_colocacion);
CREATE INDEX idx_asignacion_animal     ON asignacion_dispositivo(animal_id, ts_colocacion);

-- Listado del hato activo, que es la pantalla de inicio de la app.
CREATE INDEX idx_animal_activo         ON animal(finca_id, activo);

-- Alineacion de las observaciones conductuales con la senal del sensor.
CREATE INDEX idx_observacion_ts        ON observacion_conductual(animal_id, ts_inicio);


-- =============================================================================
-- 13. VISTAS
--     Una vista es una consulta guardada con nombre. No ocupa espacio: se
--     ejecuta en el momento. Sirve para no repetir la misma logica en veinte
--     lugares del codigo de la app.
-- =============================================================================

-- Hato activo con la edad calculada en dias.
-- julianday() devuelve el numero de dias julianos de una fecha; la resta entre
-- dos de esos numeros da la diferencia exacta en dias.
CREATE VIEW v_hato_activo AS
SELECT
    a.id,
    a.arete_interno,
    a.arete_oficial,
    a.nombre,
    a.categoria,
    a.raza,
    CAST(julianday('now') - julianday(a.fecha_nacimiento) AS INTEGER) AS edad_dias
FROM animal a
WHERE a.activo = 1
  AND a.eliminado = 0;


-- Vista de exportacion de etiquetas para la Fase 3.
-- Esta es la consulta que vas a correr el dia que entrenes el modelo. Se deja
-- escrita desde ahora para verificar que el esquema efectivamente la soporta:
-- si una vista como esta no se puede escribir, el esquema esta mal disenado.
--
-- Devuelve, por cada evento de salud confirmado y con fecha de inicio confiable,
-- que dispositivo llevaba puesto el animal en ese momento. Con eso ya puedes ir
-- a buscar la ventana de senal correspondiente.
CREATE VIEW v_etiquetas_entrenamiento AS
SELECT
    e.id                    AS evento_id,
    e.animal_id,
    e.diagnostico_codigo,
    d.sistema,
    d.afecta_rumia,
    e.ts_inicio_estimado,
    e.ts_deteccion_humana,
    e.precision_ts_inicio,
    e.severidad,
    ad.dispositivo_id,
    ad.posicion,
    -- Horas que tardo el humano en notarlo desde el inicio estimado.
    -- El factor 24.0 convierte la diferencia (en dias) a horas. El .0 fuerza
    -- division en punto flotante; sin el, SQLite trunca a entero.
    (julianday(e.ts_deteccion_humana) - julianday(e.ts_inicio_estimado)) * 24.0
                            AS horas_hasta_deteccion_visual
FROM evento_salud e
JOIN catalogo_diagnostico d
     ON d.codigo = e.diagnostico_codigo
-- LEFT JOIN y no JOIN: durante la Fase 1 todavia no hay dispositivos, y con un
-- JOIN normal la vista saldria vacia y pareceria que algo esta roto.
LEFT JOIN asignacion_dispositivo ad
     ON ad.animal_id = e.animal_id
     -- El evento tiene que caer DENTRO del periodo en que el collar estuvo puesto.
     AND e.ts_inicio_estimado >= ad.ts_colocacion
     -- ts_retiro NULL significa que sigue puesto, asi que tambien cuenta.
     AND (ad.ts_retiro IS NULL OR e.ts_inicio_estimado <= ad.ts_retiro)
     AND ad.eliminado = 0
WHERE e.eliminado = 0
  AND e.confirmado = 1
  AND e.ts_inicio_estimado IS NOT NULL
  AND e.precision_ts_inicio IN ('EXACTO', 'MAS_MENOS_6H', 'MAS_MENOS_1D');


-- =============================================================================
-- 14. CARGA INICIAL DEL CATALOGO DE DIAGNOSTICOS
--     Revisa esta lista CON TU SOCIO antes de escribir una sola pantalla.
--     Lo que no este aqui no se podra registrar, y agregar codigos despues de
--     tener seis meses de datos obliga a revisar el historico entero.
-- =============================================================================
INSERT INTO catalogo_diagnostico
    (codigo, nombre, sistema, afecta_rumia, afecta_actividad, curso) VALUES
    ('MAST_CLIN',  'Mastitis clinica',        'MAMARIO',      1, 0, 'AGUDO'),
    ('MAST_SUB',   'Mastitis subclinica',     'MAMARIO',      0, 0, 'SUBCLINICO'),
    ('COJERA',     'Cojera',                  'LOCOMOTOR',    1, 1, 'AGUDO'),
    ('NEUMONIA',   'Neumonia',                'RESPIRATORIO', 1, 1, 'AGUDO'),
    ('DIARREA',    'Diarrea',                 'DIGESTIVO',    1, 0, 'AGUDO'),
    ('TIMPANISMO', 'Timpanismo',              'DIGESTIVO',    1, 1, 'AGUDO'),
    ('ACIDOSIS',   'Acidosis ruminal',        'DIGESTIVO',    1, 0, 'SUBCLINICO'),
    ('RET_PLAC',   'Retencion de placenta',   'REPRODUCTIVO', 1, 0, 'AGUDO'),
    ('METRITIS',   'Metritis',                'REPRODUCTIVO', 1, 0, 'AGUDO'),
    ('HIPOCAL',    'Hipocalcemia',            'METABOLICO',   1, 1, 'AGUDO'),
    ('CETOSIS',    'Cetosis',                 'METABOLICO',   1, 1, 'AGUDO'),
    ('PARASITOSIS','Parasitosis',             'PARASITARIO',  1, 0, 'CRONICO'),
    ('HERIDA',     'Herida o trauma',         'OTRO',         0, 1, 'AGUDO'),
    ('OTRO',       'Otro',                    'OTRO',         0, 0, NULL);

-- =============================================================================
--  FIN DEL ESQUEMA v1.0
-- =============================================================================
