// =============================================================================
//  produccion_dao.dart
//
//  Dos cosas no obvias resueltas aqui:
//   1. El guardado usa UPSERT, porque la tabla tiene UNIQUE(animal, fecha,
//      ordenio) y volver a registrar el mismo ordenio debe corregir, no fallar.
//   2. detectarCaidas() compara cada ordenio contra el promedio movil del mismo
//      animal. Es el precursor mas simple del algoritmo de la Fase 3, y se
//      puede probar HOY, sin ningun sensor.
// =============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/fechas.dart';
import '../db/app_database.dart';
import '../models/produccion_leche.dart';

class ProduccionDao {
  static const _uuid = Uuid();

  Future<Database> get _db async => AppDatabase.instancia.db;

  // ===========================================================================
  //  ESCRITURA
  // ===========================================================================

  /// Guarda el registro de un ordenio. Si ya existia, lo corrige.
  ///
  /// POR QUE UPSERT Y NO INSERT A SECAS:
  /// la tabla tiene UNIQUE(animal_id, fecha, ordenio) para impedir el error de
  /// digitacion mas comun, que es registrar dos veces el mismo ordenio. Pero el
  /// ordeniador SI necesita poder corregir un numero mal anotado. Con INSERT a
  /// secas la correccion fallaria; con UPSERT, actualiza.
  ///
  /// POR QUE NO ConflictAlgorithm.replace:
  /// `replace` hace DELETE + INSERT por dentro, asi que la fila nueva recibe un
  /// id distinto y pierde su `creado_en` original. ON CONFLICT DO UPDATE
  /// modifica la fila existente conservando ambos.
  Future<void> guardar({
    required String animalId,
    required DateTime fecha,
    required int ordenio,
    required double litros,
    DateTime? tsOrdenio,
  }) async {
    final db = await _db;

    await db.rawInsert('''
      INSERT INTO produccion_leche
        (id, animal_id, fecha, ordenio, litros, ts_ordenio, creado_en)
      VALUES (?, ?, ?, ?, ?, ?, ?)

      -- Si choca con la restriccion UNIQUE sobre estas tres columnas...
      ON CONFLICT(animal_id, fecha, ordenio) DO UPDATE SET
        -- ...se actualizan solo los valores medidos.
        -- `excluded` es la fila que se intento insertar; asi se toma el valor
        -- nuevo sin tener que repetirlo como parametro.
        litros     = excluded.litros,
        ts_ordenio = excluded.ts_ordenio
        -- id y creado_en NO se tocan: la fila conserva su identidad original.
    ''', [
      _uuid.v4(),
      animalId,
      aFecha(fecha),
      ordenio,
      litros,
      tsOrdenio == null ? null : aIso(tsOrdenio),
      ahora(),
    ]);
  }

  /// Guarda varios registros de una sola vez.
  ///
  /// POR QUE UN LOTE Y NO UN BUCLE DE guardar():
  /// el ordenio se registra vaca por vaca, treinta veces seguidas. Cada
  /// escritura suelta abre y cierra una transaccion propia, lo que en un
  /// telefono de gama baja se siente. Un batch las agrupa en UNA transaccion:
  /// o entran todas o no entra ninguna, y es mucho mas rapido.
  Future<void> guardarLote(List<Map<String, Object?>> registros) async {
    final db = await _db;

    // batch() acumula operaciones sin enviarlas hasta el commit().
    final lote = db.batch();

    for (final r in registros) {
      lote.rawInsert('''
        INSERT INTO produccion_leche
          (id, animal_id, fecha, ordenio, litros, ts_ordenio, creado_en)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(animal_id, fecha, ordenio) DO UPDATE SET
          litros     = excluded.litros,
          ts_ordenio = excluded.ts_ordenio
      ''', [
        _uuid.v4(),
        r['animal_id'],
        aFecha(r['fecha'] as DateTime),
        r['ordenio'],
        r['litros'],
        r['ts_ordenio'] == null ? null : aIso(r['ts_ordenio'] as DateTime),
        ahora(),
      ]);
    }

    // noResult: true descarta los resultados de cada operacion. Con treinta
    // inserciones, devolverlos seria memoria gastada en algo que nadie lee.
    await lote.commit(noResult: true);
  }

  Future<void> eliminar(String id) async {
    final db = await _db;
    await db.update(
      'produccion_leche',
      {'eliminado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===========================================================================
  //  LECTURA
  // ===========================================================================

  /// Serie de produccion de un animal, del dia mas reciente hacia atras.
  Future<List<ProduccionLeche>> porAnimal(
    String animalId, {
    int ultimosDias = 60,

    /// Dia desde el que se cuenta hacia atras. Por defecto, hoy.
    /// Las pruebas pasan una fecha fija para no depender del reloj.
    DateTime? hoy,
  }) async {
    final db = await _db;

    // La fecha de corte se calcula en Dart y no con date('now') de SQLite:
    // 'now' esta en UTC, y en Ecuador desde las 19:00 ya seria el dia
    // siguiente. aFecha usa la hora local, la misma que se guarda en `fecha`.
    final corte = _corte(hoy, ultimosDias);

    final filas = await db.rawQuery('''
      SELECT *
      FROM produccion_leche
      WHERE animal_id = ?
        AND eliminado = 0
        AND fecha >= ?
      ORDER BY fecha DESC, ordenio DESC
    ''', [animalId, corte]);

    return filas.map(ProduccionLeche.desdeFila).toList();
  }

  /// Litros ya registrados de un ordenio, por animal.
  ///
  /// Sirve para que la pantalla de captura muestre lo que ya se anoto al
  /// volver a abrirla: sin esto, reabrir el ordenio a medias mostraria todo
  /// vacio y la persona volveria a digitar (o creeria que se perdio).
  Future<Map<String, double>> delOrdenio({
    required String fincaId,
    required DateTime fecha,
    required int ordenio,
  }) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      SELECT p.animal_id, p.litros
      FROM produccion_leche p
      JOIN animal a ON a.id = p.animal_id
      WHERE a.finca_id = ?
        AND p.fecha = ?
        AND p.ordenio = ?
        AND p.eliminado = 0
        AND a.eliminado = 0
    ''', [fincaId, aFecha(fecha), ordenio]);

    return {
      for (final f in filas)
        f['animal_id'] as String: (f['litros'] as num).toDouble(),
    };
  }

  /// Produccion total de la finca en un dia.
  Future<double> totalDelDia(String fincaId, DateTime fecha) async {
    final db = await _db;

    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(p.litros), 0) AS total
      FROM produccion_leche p
      JOIN animal a ON a.id = p.animal_id
      WHERE a.finca_id = ?
        AND p.fecha = ?
        AND p.eliminado = 0
        AND a.eliminado = 0
    ''', [fincaId, aFecha(fecha)]);

    // COALESCE convierte el NULL de SUM (que ocurre cuando no hay filas) en 0.
    // Sin el, esta consulta devolveria null y habria que comprobarlo aqui.
    return (r.first['total'] as num).toDouble();
  }

  /// Animales sin registro de produccion en una fecha y ordenio.
  ///
  /// Es la lista de "faltantes" del ordenio de hoy. Sirve para que la pantalla
  /// muestre cuantas vacas quedan por registrar, que es lo que hace que el
  /// registro se complete en vez de quedar a medias.
  Future<List<String>> faltantes({
    required String fincaId,
    required DateTime fecha,
    required int ordenio,
  }) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      SELECT a.id
      FROM animal a
      WHERE a.finca_id = ?
        AND a.activo = 1
        AND a.eliminado = 0
        AND a.categoria = 'VACA_LACTANCIA'

        -- NOT EXISTS deja pasar solo los animales para los que NO hay una fila
        -- de produccion ese dia y ordenio. Es mas eficiente que un LEFT JOIN
        -- con IS NULL porque el motor puede parar en cuanto encuentra una.
        AND NOT EXISTS (
          SELECT 1
          FROM produccion_leche p
          WHERE p.animal_id = a.id
            AND p.fecha = ?
            AND p.ordenio = ?
            AND p.eliminado = 0
        )
      ORDER BY a.arete_interno COLLATE NOCASE
    ''', [fincaId, aFecha(fecha), ordenio]);

    return filas.map((f) => f['id'] as String).toList();
  }

  // ===========================================================================
  //  DETECCION DE CAIDAS
  // ===========================================================================

  /// Detecta animales cuya produccion cayo respecto de su propio promedio.
  ///
  /// ESTE METODO ES EL PRECURSOR DEL ALGORITMO DE LA FASE 3, y se puede probar
  /// hoy mismo sin un solo sensor. La logica es la misma que se aplicara sobre
  /// la rumia: comparar el valor de hoy contra la linea base del propio animal
  /// y avisar cuando se desvia.
  ///
  /// Se compara cada vaca CONSIGO MISMA, no contra el promedio del hato. Una
  /// vaca que da 8 litros cuando siempre dio 8 esta perfecta; una que da 20
  /// cuando siempre dio 30 tiene un problema, aunque 20 sea mas que 8.
  ///
  /// Si esto funciona con produccion, funcionara con rumia. Si Jhon ignora
  /// estas alertas, tambien ignorara las del collar, y eso conviene saberlo en
  /// la Fase 1 y no en el mes 14.
  Future<List<CaidaProduccion>> detectarCaidas({
    required String fincaId,

    /// Cuantos dias de historia se usan como linea base.
    /// 7 dias captura la variacion normal sin arrastrar la tendencia de la
    /// curva de lactancia, que baja de forma lenta y esperada.
    int diasBase = 7,

    /// Umbral de alerta en porcentaje.
    /// 15 % es un punto de partida razonable: por debajo hay demasiado ruido
    /// normal (clima, cambio de pasto, estres de manejo) y saldrian falsas
    /// alarmas que ensenarian a ignorar la pantalla.
    double umbralPorcentaje = 15.0,

    /// Dia de referencia. Por defecto, hoy. Ver [porAnimal].
    DateTime? hoy,
  }) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      -- WITH crea tablas temporales que existen solo durante esta consulta.
      -- Partir el calculo en pasos con nombre lo hace legible; escrito como
      -- una sola consulta anidada seria casi imposible de revisar.
      WITH

      -- Paso 1: produccion total por animal y dia (suma de los dos ordenios)
      diario AS (
        SELECT
          p.animal_id,
          p.fecha,
          SUM(p.litros) AS litros_dia
        FROM produccion_leche p
        JOIN animal a ON a.id = p.animal_id
        WHERE a.finca_id = ?
          AND p.eliminado = 0
          AND a.eliminado = 0
          AND a.activo = 1
          AND p.fecha >= ?
        GROUP BY p.animal_id, p.fecha
      ),

      -- Paso 2: el ultimo dia registrado de cada animal.
      -- No se usa la fecha de hoy porque puede que aun no se haya registrado el
      -- ordenio, y entonces la consulta no devolveria nada.
      ultimo AS (
        SELECT animal_id, MAX(fecha) AS fecha_ultima
        FROM diario
        GROUP BY animal_id
      ),

      -- Paso 3: promedio de los dias ANTERIORES al ultimo.
      -- El dia que se evalua se excluye de su propia linea base: incluirlo
      -- arrastraria el promedio hacia abajo y disimularia la caida.
      base AS (
        SELECT
          d.animal_id,
          AVG(d.litros_dia) AS promedio,
          COUNT(*)          AS dias_con_dato
        FROM diario d
        JOIN ultimo u ON u.animal_id = d.animal_id
        WHERE d.fecha < u.fecha_ultima
        GROUP BY d.animal_id
      )

      SELECT
        d.animal_id,
        a.arete_interno,
        a.nombre,
        d.fecha,
        d.litros_dia                AS litros_hoy,
        b.promedio,
        -- Porcentaje de caida respecto de la linea base.
        -- El 100.0 con decimal fuerza punto flotante; con 100 entero, SQLite
        -- truncaria el resultado a cero en la mayoria de los casos.
        ((b.promedio - d.litros_dia) / b.promedio) * 100.0 AS caida_pct
      FROM diario d
      JOIN ultimo u ON u.animal_id = d.animal_id AND u.fecha_ultima = d.fecha
      JOIN base   b ON b.animal_id = d.animal_id
      JOIN animal a ON a.id = d.animal_id

      -- Con menos de 3 dias de historia el promedio no es confiable y
      -- generaria alertas sin fundamento.
      WHERE b.dias_con_dato >= 3
        AND b.promedio > 0
        AND ((b.promedio - d.litros_dia) / b.promedio) * 100.0 >= ?

      ORDER BY caida_pct DESC
    ''', [fincaId, _corte(hoy, diasBase + 1), umbralPorcentaje]);

    return filas.map((f) => CaidaProduccion(
      animalId: f['animal_id'] as String,
      etiquetaAnimal:
          (f['arete_interno'] as String?) ?? (f['nombre'] as String?) ?? '—',
      fecha: desdeIso(f['fecha'] as String)!,
      litrosHoy: (f['litros_hoy'] as num).toDouble(),
      promedioAnterior: (f['promedio'] as num).toDouble(),
      caidaPorcentaje: (f['caida_pct'] as num).toDouble(),
    )).toList();
  }

  /// Fecha 'AAAA-MM-DD' de [dias] dias antes de [hoy] (o de hoy si es null).
  static String _corte(DateTime? hoy, int dias) =>
      aFecha((hoy ?? DateTime.now()).subtract(Duration(days: dias)));
}
