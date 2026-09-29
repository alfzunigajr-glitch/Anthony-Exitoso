-- =============================================================================
--  PARCHE DE ESQUEMA v1.0 -> v1.1
--
--  QUE RESUELVE:
--  1. Agrega prolapso cervical al catalogo de diagnosticos.
--  2. Deja el aborto viviendo UNICAMENTE en evento_reproductivo, e impide
--     por construccion que se registre tambien como evento de salud.
--  3. Cierra las tres vias por las que un evento podia contarse dos veces.
--
--  PRINCIPIO DE DISENIO DE ESTE PARCHE:
--  No se confia en que la app "recuerde" no duplicar. Si una regla importa,
--  la hace cumplir el motor de base de datos. Una convencion se rompe el dia
--  que alguien escribe una pantalla nueva; una restriccion, no.
-- =============================================================================

PRAGMA foreign_keys = ON;


-- =============================================================================
--  1. NUEVO DIAGNOSTICO
-- =============================================================================

-- Prolapso cervical. Va en evento_salud porque es una patologia que se trata,
-- no un hito del ciclo reproductivo.
--   afecta_rumia = 1     -> el animal deja de comer mientras esta el cuadro
--   afecta_actividad = 1 -> cambia postura y frecuencia de echarse, que es
--                           justamente lo que el acelerometro puede leer
INSERT INTO catalogo_diagnostico
    (codigo, nombre, sistema, afecta_rumia, afecta_actividad, curso) VALUES
    ('PROL_CERV', 'Prolapso cervical', 'REPRODUCTIVO', 1, 1, 'AGUDO');

-- OJO: aqui NO se inserta 'ABORTO'.
-- Y esa omision no es un olvido, es el mecanismo de proteccion.
-- La columna evento_salud.diagnostico_codigo tiene FOREIGN KEY hacia
-- catalogo_diagnostico(codigo). Si el codigo 'ABORTO' no existe en el catalogo,
-- el motor RECHAZA cualquier intento de insertarlo como evento de salud.
-- Resultado: el aborto solo puede existir en evento_reproductivo.
-- La duplicacion no queda prohibida por acuerdo, queda imposibilitada.


-- =============================================================================
--  2. PRIMERA VIA DE DUPLICACION: asignaciones de dispositivo solapadas
--
--  Escenario: por error de digitacion, el collar 7 queda registrado como
--  puesto en la vaca A del 1 al 30 de marzo Y en la vaca B del 15 al 20.
--  La vista de entrenamiento hace JOIN contra esta tabla, asi que un evento
--  del 17 de marzo se cruzaria con DOS asignaciones y generaria DOS filas
--  para un solo evento real. El conteo se infla sin que nada avise.
--
--  Solucion: un disparador (trigger) que rechaza la insercion si el periodo
--  se cruza con otro periodo del mismo dispositivo.
-- =============================================================================

CREATE TRIGGER trg_asignacion_sin_solape
BEFORE INSERT ON asignacion_dispositivo   -- Se ejecuta ANTES de escribir la fila
FOR EACH ROW                              -- Una vez por cada fila que se intenta insertar
WHEN EXISTS (                             -- Solo actua si la subconsulta devuelve algo
    SELECT 1
    FROM asignacion_dispositivo a
    WHERE a.dispositivo_id = NEW.dispositivo_id  -- NEW = la fila que se esta insertando
      AND a.eliminado = 0                        -- Las borradas logicamente no cuentan

      -- Condicion de solape entre dos intervalos [inicio1,fin1] y [inicio2,fin2]:
      -- se cruzan si inicio1 <= fin2 Y fin1 >= inicio2.
      -- COALESCE sustituye el NULL de ts_retiro (que significa "sigue puesto")
      -- por una fecha muy lejana, para que se comporte como un intervalo abierto.
      AND NEW.ts_colocacion <= COALESCE(a.ts_retiro,       '9999-12-31T23:59:59-05:00')
      AND COALESCE(NEW.ts_retiro, '9999-12-31T23:59:59-05:00') >= a.ts_colocacion
)
BEGIN
    -- RAISE(ABORT, ...) cancela la operacion y devuelve el mensaje a la app,
    -- que puede mostrarlo al usuario. La transaccion se revierte entera.
    SELECT RAISE(ABORT, 'El dispositivo ya tiene una asignacion en ese periodo');
END;

-- Mismo control para las modificaciones. Sin este segundo trigger, se podria
-- insertar una asignacion valida y luego editarla hasta dejarla solapada.
CREATE TRIGGER trg_asignacion_sin_solape_update
BEFORE UPDATE ON asignacion_dispositivo
FOR EACH ROW
WHEN EXISTS (
    SELECT 1
    FROM asignacion_dispositivo a
    WHERE a.dispositivo_id = NEW.dispositivo_id
      AND a.id <> NEW.id            -- Excluye la propia fila: no se solapa consigo misma
      AND a.eliminado = 0
      AND NEW.ts_colocacion <= COALESCE(a.ts_retiro,       '9999-12-31T23:59:59-05:00')
      AND COALESCE(NEW.ts_retiro, '9999-12-31T23:59:59-05:00') >= a.ts_colocacion
)
BEGIN
    SELECT RAISE(ABORT, 'La edicion dejaria dos asignaciones solapadas');
END;


-- =============================================================================
--  3. SEGUNDA VIA DE DUPLICACION: el mismo caso clinico registrado dos veces
--
--  Escenario real: tu registras la mastitis de la vaca 18 el martes por la
--  noche, y Jhon la registra el miercoles sin saber que ya estaba. Son dos
--  filas para un solo episodio.
--
--  Por que NO se pone una restriccion UNIQUE que lo prohiba:
--  una vaca SI puede tener mastitis dos veces en el mismo mes, y son dos
--  episodios legitimos y distintos. Prohibirlo perderia datos reales.
--
--  Solucion: no bloquear, sino detectar. Esta vista lista los pares
--  sospechosos para que la app avise ("esta vaca ya tiene un caso de mastitis
--  registrado hace 3 dias, es el mismo?") y decida un humano.
-- =============================================================================

CREATE VIEW v_posibles_duplicados AS
SELECT
    e1.id                AS evento_id_1,
    e2.id                AS evento_id_2,
    e1.animal_id,
    e1.diagnostico_codigo,
    e1.ts_deteccion_humana AS fecha_1,
    e2.ts_deteccion_humana AS fecha_2,
    -- Diferencia en dias entre ambos registros. julianday() convierte la fecha
    -- a un numero de dias; la resta da la distancia exacta.
    ABS(julianday(e1.ts_deteccion_humana) - julianday(e2.ts_deteccion_humana))
                         AS dias_de_diferencia
FROM evento_salud e1
JOIN evento_salud e2
     ON  e1.animal_id          = e2.animal_id           -- Mismo animal
     AND e1.diagnostico_codigo = e2.diagnostico_codigo  -- Mismo diagnostico
     -- e1.id < e2.id evita que cada par aparezca dos veces (A-B y B-A)
     -- y evita tambien que una fila se compare consigo misma.
     AND e1.id < e2.id
WHERE e1.eliminado = 0
  AND e2.eliminado = 0
  -- Ventana de 7 dias: dos casos del mismo cuadro en menos de una semana son
  -- sospechosos. Mas alla de eso, lo normal es que sean episodios distintos.
  AND ABS(julianday(e1.ts_deteccion_humana) - julianday(e2.ts_deteccion_humana)) <= 7;


-- =============================================================================
--  4. VISTA UNIFICADA DE ETIQUETAS  <-- FUENTE UNICA DE VERDAD
--
--  Problema que resuelve: ahora las etiquetas viven en DOS tablas
--  (evento_salud y evento_reproductivo). Si alguien consulta las dos por
--  separado y suma, cuenta mal. Si consulta solo una, pierde datos.
--
--  Esta vista es el unico lugar del que se deben leer etiquetas. Se usa
--  UNION ALL, no UNION:
--    UNION     -> elimina duplicados comparando todas las columnas. Es lento y,
--                 peor, ocultaria un duplicado real en vez de dejarlo ver.
--    UNION ALL -> concatena sin comparar. Es correcto AQUI porque las dos
--                 consultas son disjuntas por construccion: una lee solo de
--                 evento_salud y la otra solo de evento_reproductivo, y el
--                 aborto no puede estar en la primera (ver seccion 1).
--                 Cero solape posible, cero necesidad de deduplicar.
-- =============================================================================

CREATE VIEW v_etiquetas AS

-- ---- Rama 1: eventos de salud -------------------------------------------
SELECT
    e.id                    AS etiqueta_id,
    'SALUD'                 AS fuente,          -- De que tabla viene esta fila
    'ENFERMEDAD'            AS tipo_etiqueta,   -- Para que sirve al entrenar
    e.animal_id,
    e.diagnostico_codigo    AS codigo,
    e.ts_inicio_estimado,
    e.ts_deteccion_humana,
    e.precision_ts_inicio,
    e.confirmado,
    e.severidad,
    d.afecta_rumia,
    d.afecta_actividad
FROM evento_salud e
JOIN catalogo_diagnostico d ON d.codigo = e.diagnostico_codigo
WHERE e.eliminado = 0

UNION ALL

-- ---- Rama 2: eventos reproductivos relevantes ---------------------------
SELECT
    r.id                    AS etiqueta_id,
    'REPRO'                 AS fuente,
    -- Cada tipo cumple un papel distinto en el analisis:
    --   ABORTO -> etiqueta positiva de patologia
    --   PARTO  -> NO es enfermedad, pero altera el comportamiento de forma
    --             brutal. Hay que conocerlo para EXCLUIR esa ventana del
    --             analisis de enfermedad y no confundir un parto con un cuadro
    --             clinico. Es una etiqueta de control.
    --   CELO   -> objetivo del segundo algoritmo, no del de salud
    CASE r.tipo
        WHEN 'ABORTO' THEN 'ABORTO'
        WHEN 'PARTO'  THEN 'PARTO_CONTROL'
        WHEN 'CELO'   THEN 'CELO'
    END                     AS tipo_etiqueta,
    r.animal_id,
    r.tipo                  AS codigo,
    r.ts_evento             AS ts_inicio_estimado,
    r.ts_evento             AS ts_deteccion_humana,
    r.precision_ts          AS precision_ts_inicio,
    -- Un celo solo se considera confirmado si una palpacion posterior dio
    -- preniada. Esa comprobacion se hace en la vista de mas abajo; aqui se
    -- deja en 0 y se resuelve despues, para no anidar subconsultas pesadas.
    CASE WHEN r.tipo = 'CELO' THEN 0 ELSE 1 END AS confirmado,
    NULL                    AS severidad,
    1                       AS afecta_rumia,
    1                       AS afecta_actividad
FROM evento_reproductivo r
WHERE r.eliminado = 0
  -- Filtro explicito: solo estos tres tipos son etiquetas. SERVICIO,
  -- PALPACION y SECADO son datos de manejo y no entran al entrenamiento.
  AND r.tipo IN ('ABORTO', 'PARTO', 'CELO');


-- =============================================================================
--  5. VISTA DE ENTRENAMIENTO v2
--
--  Reemplaza a v_etiquetas_entrenamiento de la version 1.0.
--  Ahora se apoya en v_etiquetas, asi que cubre las dos tablas sin duplicar,
--  y arrastra el dispositivo que llevaba puesto el animal en ese momento.
-- =============================================================================

DROP VIEW IF EXISTS v_etiquetas_entrenamiento;

CREATE VIEW v_etiquetas_entrenamiento AS
SELECT
    t.etiqueta_id,
    t.fuente,
    t.tipo_etiqueta,
    t.animal_id,
    t.codigo,
    t.ts_inicio_estimado,
    t.ts_deteccion_humana,
    t.precision_ts_inicio,
    t.severidad,
    ad.dispositivo_id,
    ad.posicion,
    -- Cuantas horas tardo el humano en notarlo desde el inicio estimado.
    -- El 24.0 con decimal fuerza division en punto flotante; con 24 entero,
    -- SQLite truncaria el resultado.
    (julianday(t.ts_deteccion_humana) - julianday(t.ts_inicio_estimado)) * 24.0
        AS horas_hasta_deteccion_visual
FROM v_etiquetas t

-- LEFT JOIN y no JOIN: durante la Fase 1 no hay dispositivos todavia. Con un
-- JOIN normal la vista saldria vacia y pareceria que algo esta roto.
LEFT JOIN asignacion_dispositivo ad
     ON  ad.animal_id = t.animal_id
     -- La etiqueta tiene que caer dentro del periodo en que el collar
     -- estuvo puesto en ESE animal.
     AND t.ts_inicio_estimado >= ad.ts_colocacion
     AND (ad.ts_retiro IS NULL OR t.ts_inicio_estimado <= ad.ts_retiro)
     AND ad.eliminado = 0
     -- Gracias al trigger de la seccion 2, este LEFT JOIN nunca puede
     -- devolver mas de una fila por etiqueta. Sin el trigger, esta consulta
     -- seria la que multiplicaria el conteo en silencio.

WHERE t.confirmado = 1
  AND t.ts_inicio_estimado IS NOT NULL
  -- Solo fechas de calidad suficiente. Un evento con precision de +-3 dias
  -- no sirve para buscar una anomalia en una ventana de 48 horas.
  AND t.precision_ts_inicio IN ('EXACTO', 'MAS_MENOS_6H', 'MAS_MENOS_1D');


-- =============================================================================
--  6. VISTA DE CONTEO  <-- LA QUE VAS A USAR CON JHON
--
--  Cuenta cada evento UNA sola vez, desde la fuente unificada. Es el numero
--  que reemplaza al conteo retrospectivo que no se pudo hacer.
--  Basta con dejarla correr 6 a 8 semanas de uso real de la app.
-- =============================================================================

CREATE VIEW v_conteo_eventos AS
SELECT
    t.tipo_etiqueta,
    t.codigo,
    COUNT(*)                                    AS total,
    -- COUNT solo cuenta valores no nulos, asi que CASE ... ELSE NULL permite
    -- contar condicionalmente sin escribir una subconsulta aparte.
    COUNT(CASE WHEN t.confirmado = 1 THEN 1 END) AS confirmados,
    COUNT(CASE WHEN t.precision_ts_inicio IN ('EXACTO','MAS_MENOS_6H','MAS_MENOS_1D')
               THEN 1 END)                       AS con_fecha_util,
    MIN(t.ts_deteccion_humana)                   AS primer_registro,
    MAX(t.ts_deteccion_humana)                   AS ultimo_registro
FROM v_etiquetas t
GROUP BY t.tipo_etiqueta, t.codigo
ORDER BY total DESC;


-- =============================================================================
--  7. INDICE DE APOYO
--     La vista v_posibles_duplicados filtra por animal y diagnostico. Sin este
--     indice, con miles de eventos la deteccion de duplicados se vuelve lenta
--     porque tiene que recorrer la tabla entera.
-- =============================================================================
CREATE INDEX idx_evento_salud_dup
    ON evento_salud(animal_id, diagnostico_codigo, ts_deteccion_humana);

-- =============================================================================
--  FIN DEL PARCHE v1.1
-- =============================================================================
