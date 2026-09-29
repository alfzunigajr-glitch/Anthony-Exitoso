// =============================================================================
//  tratamiento_dao.dart
//
//  Contiene la consulta mas util de la Fase 1 desde el punto de vista de Jhon:
//  que vacas tienen la leche en retiro hoy. Es la funcion que justifica abrir
//  la app todos los dias mientras el collar todavia no existe, y de que la
//  abra todos los dias depende la Compuerta 1.
// =============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/fechas.dart';
import '../db/app_database.dart';
import '../models/tratamiento.dart';

/// Animal con la leche en periodo de retiro.
class AnimalEnRetiro {
  final String animalId;
  final String etiquetaAnimal;   // Arete o nombre, para mostrar en pantalla
  final String farmaco;
  final DateTime aplicadoEn;
  final DateTime retiroHasta;
  final int diasRestantes;

  const AnimalEnRetiro({
    required this.animalId,
    required this.etiquetaAnimal,
    required this.farmaco,
    required this.aplicadoEn,
    required this.retiroHasta,
    required this.diasRestantes,
  });
}

class TratamientoDao {
  static const _uuid = Uuid();

  Future<Database> get _db async => AppDatabase.instancia.db;

  // ===========================================================================
  //  ESCRITURA
  // ===========================================================================

  /// Registra una aplicacion de medicamento sobre un evento de salud.
  Future<Tratamiento> crear({
    required String eventoSaludId,
    required DateTime tsAplicacion,
    required String farmaco,
    String? principioActivo,
    double? dosis,
    String? unidadDosis,
    String? via,
    int? diasRetiroLeche,
    int? diasRetiroCarne,
    String? aplicadoPor,
  }) async {
    final db = await _db;

    final tratamiento = Tratamiento(
      id: _uuid.v4(),
      eventoSaludId: eventoSaludId,
      tsAplicacion: tsAplicacion,
      farmaco: farmaco,
      principioActivo: principioActivo,
      dosis: dosis,
      unidadDosis: unidadDosis,
      via: via,
      diasRetiroLeche: diasRetiroLeche,
      diasRetiroCarne: diasRetiroCarne,
      aplicadoPor: aplicadoPor,
      creadoEn: DateTime.now(),
    );

    // Si eventoSaludId no existe, la clave foranea lanza excepcion aqui.
    // Es lo correcto: un tratamiento sin evento asociado seria un dato huerfano
    // que nunca podria interpretarse.
    await db.insert(
      'tratamiento',
      tratamiento.aFila(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return tratamiento;
  }

  Future<void> eliminar(String id) async {
    final db = await _db;
    await db.update(
      'tratamiento',
      {'eliminado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===========================================================================
  //  LECTURA
  // ===========================================================================

  /// Todas las aplicaciones de un episodio, en orden cronologico ascendente.
  ///
  /// Ascendente y no descendente a proposito: aqui interesa leer la secuencia
  /// del tratamiento de principio a fin, no ver primero lo ultimo.
  Future<List<Tratamiento>> porEvento(String eventoSaludId) async {
    final db = await _db;

    final filas = await db.query(
      'tratamiento',
      where: 'evento_salud_id = ? AND eliminado = 0',
      whereArgs: [eventoSaludId],
      orderBy: 'ts_aplicacion ASC',
    );

    return filas.map(Tratamiento.desdeFila).toList();
  }

  /// Todos los tratamientos de un animal, sin importar el episodio.
  Future<List<Tratamiento>> porAnimal(String animalId) async {
    final db = await _db;

    // JOIN con evento_salud porque tratamiento no guarda animal_id: llega al
    // animal a traves del evento. Normalizar asi evita que un tratamiento
    // pueda quedar apuntando a un animal distinto del de su evento.
    final filas = await db.rawQuery('''
      SELECT t.*
      FROM tratamiento t
      JOIN evento_salud e ON e.id = t.evento_salud_id
      WHERE e.animal_id = ?
        AND t.eliminado = 0
        AND e.eliminado = 0
      ORDER BY t.ts_aplicacion DESC
    ''', [animalId]);

    return filas.map(Tratamiento.desdeFila).toList();
  }

  // ===========================================================================
  //  RETIRO DE LECHE
  // ===========================================================================

  /// Animales cuya leche NO se puede entregar hoy.
  ///
  /// COMO SE CALCULA EN SQL:
  ///   datetime(ts_aplicacion, '+N days') suma dias a una fecha.
  ///   El numero de dias esta en una COLUMNA, no es una constante, asi que hay
  ///   que armar el texto del modificador concatenando:
  ///       '+' || dias_retiro_leche || ' days'
  ///   El operador || concatena en SQL. Para 5 dias produce '+5 days'.
  ///
  /// Se calcula en SQL y no en Dart a proposito: traer todos los tratamientos
  /// del historico al telefono para filtrarlos alli seria cada vez mas lento a
  /// medida que crezca la tabla. El motor filtra sobre el indice y devuelve
  /// solo las pocas filas que importan.
  Future<List<AnimalEnRetiro>> enRetiroLeche(String fincaId) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      SELECT
        a.id                AS animal_id,
        a.arete_interno,
        a.nombre,
        t.farmaco,
        t.ts_aplicacion,
        datetime(t.ts_aplicacion, '+' || t.dias_retiro_leche || ' days')
                            AS retiro_hasta
      FROM tratamiento t
      JOIN evento_salud e ON e.id = t.evento_salud_id
      JOIN animal a       ON a.id = e.animal_id
      WHERE a.finca_id = ?
        AND t.eliminado = 0
        AND e.eliminado = 0
        AND a.eliminado = 0
        AND a.activo = 1

        -- Solo farmacos que tienen periodo de retiro definido
        AND t.dias_retiro_leche IS NOT NULL
        AND t.dias_retiro_leche > 0

        -- El periodo de retiro todavia no termina.
        -- 'now' devuelve el instante actual en UTC; datetime() sobre la
        -- columna tambien normaliza a UTC porque la cadena trae offset.
        -- Al comparar, ambos lados estan en la misma referencia.
        AND datetime(t.ts_aplicacion, '+' || t.dias_retiro_leche || ' days')
            > datetime('now')

      -- Si hay varios tratamientos vigentes para el mismo animal, manda el que
      -- termina mas tarde. GROUP BY + MAX deja una sola fila por animal, que es
      -- lo que el ordeniador necesita ver: una vaca, una fecha.
      GROUP BY a.id
      HAVING retiro_hasta = MAX(
        datetime(t.ts_aplicacion, '+' || t.dias_retiro_leche || ' days')
      )

      ORDER BY retiro_hasta ASC
    ''', [fincaId]);

    final ahoraFecha = DateTime.now();

    return filas.map((f) {
      // datetime() de SQLite devuelve 'AAAA-MM-DD HH:MM:SS' con un espacio en
      // vez de la T, y sin offset (esta en UTC). DateTime.parse no acepta ese
      // formato tal cual, asi que se convierte a ISO valido antes de leerlo.
      final textoUtc = (f['retiro_hasta'] as String).replaceFirst(' ', 'T');
      final hasta = DateTime.parse('${textoUtc}Z').toLocal();


      final arete = f['arete_interno'] as String?;
      final nombre = f['nombre'] as String?;

      return AnimalEnRetiro(
        animalId: f['animal_id'] as String,

        // Se prioriza el arete porque es lo que el ordeniador usa a diario;
        // si no hay, cae al nombre; si tampoco, un guion.
        etiquetaAnimal: arete ?? nombre ?? '—',

        farmaco: f['farmaco'] as String,
        aplicadoEn: desdeIso(f['ts_aplicacion'] as String)!,
        retiroHasta: hasta,
        diasRestantes: diasCalendarioHasta(hasta, desde: ahoraFecha),
      );
    }).toList();
  }

  /// Comprueba si un animal concreto tiene la leche en retiro.
  ///
  /// Version puntual de la consulta anterior, para la ficha del animal.
  /// Devuelve null si se puede entregar la leche.
  Future<AnimalEnRetiro?> retiroDeAnimal(String animalId) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      SELECT
        a.id AS animal_id,
        a.arete_interno,
        a.nombre,
        t.farmaco,
        t.ts_aplicacion,
        datetime(t.ts_aplicacion, '+' || t.dias_retiro_leche || ' days')
                AS retiro_hasta
      FROM tratamiento t
      JOIN evento_salud e ON e.id = t.evento_salud_id
      JOIN animal a       ON a.id = e.animal_id
      WHERE a.id = ?
        AND t.eliminado = 0
        AND e.eliminado = 0
        AND t.dias_retiro_leche IS NOT NULL
        AND t.dias_retiro_leche > 0
        AND datetime(t.ts_aplicacion, '+' || t.dias_retiro_leche || ' days')
            > datetime('now')
      -- El que termina mas tarde manda
      ORDER BY retiro_hasta DESC
      LIMIT 1
    ''', [animalId]);

    if (filas.isEmpty) return null;

    final f = filas.first;
    final textoUtc = (f['retiro_hasta'] as String).replaceFirst(' ', 'T');
    final hasta = DateTime.parse('${textoUtc}Z').toLocal();
    return AnimalEnRetiro(
      animalId: f['animal_id'] as String,
      etiquetaAnimal: (f['arete_interno'] as String?) ?? (f['nombre'] as String?) ?? '—',
      farmaco: f['farmaco'] as String,
      aplicadoEn: desdeIso(f['ts_aplicacion'] as String)!,
      retiroHasta: hasta,
      diasRestantes: diasCalendarioHasta(hasta),
    );
  }

  /// Farmacos usados con mas frecuencia, del mas usado al menos.
  ///
  /// Sirve para dos cosas: precargar el formulario con lo que Jhon usa siempre
  /// (menos escritura, mas probabilidad de que registre), y de paso da una
  /// lectura del gasto en medicamento por tipo.
  Future<List<Map<String, Object?>>> farmacosFrecuentes(String fincaId) async {
    final db = await _db;

    return db.rawQuery('''
      SELECT
        t.farmaco,
        COUNT(*) AS veces,
        -- MAX sobre un texto ISO-8601 devuelve la fecha mas reciente, porque
        -- ese formato ordena cronologicamente como texto.
        MAX(t.ts_aplicacion) AS ultima_vez,
        -- El periodo de retiro se precarga con el ultimo valor usado para ese
        -- farmaco, asi el usuario no lo escribe de nuevo cada vez.
        MAX(t.dias_retiro_leche) AS dias_retiro_leche
      FROM tratamiento t
      JOIN evento_salud e ON e.id = t.evento_salud_id
      JOIN animal a       ON a.id = e.animal_id
      WHERE a.finca_id = ?
        AND t.eliminado = 0
        AND e.eliminado = 0
      GROUP BY t.farmaco
      ORDER BY veces DESC
      LIMIT 10
    ''', [fincaId]);
  }
}
