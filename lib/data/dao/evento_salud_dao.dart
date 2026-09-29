// =============================================================================
//  evento_salud_dao.dart
//  Acceso a la tabla `evento_salud` y a las vistas de conteo.
//
//  ES EL DAO MÁS IMPORTANTE DE LA APP: cada fila que escribe aquí es una
//  etiqueta de entrenamiento potencial.
// =============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/fechas.dart';
import '../db/app_database.dart';
import '../models/evento_salud.dart';

/// Resultado de la comprobación de duplicados que se hace ANTES de guardar.
class PosibleDuplicado {
  final String eventoId;
  final DateTime fecha;
  final double diasDeDiferencia;

  const PosibleDuplicado({
    required this.eventoId,
    required this.fecha,
    required this.diasDeDiferencia,
  });
}

/// Fila del conteo por diagnóstico. Alimenta la pantalla que reemplaza al
/// conteo retrospectivo que Jhon no pudo hacer con sus cuadernos.
class ConteoDiagnostico {
  final String codigo;
  final String nombre;
  final int total;
  final int confirmados;
  final int conFechaUtil;

  const ConteoDiagnostico({
    required this.codigo,
    required this.nombre,
    required this.total,
    required this.confirmados,
    required this.conFechaUtil,
  });
}

class EventoSaludDao {
  static const _uuid = Uuid();

  Future<Database> get _db async => AppDatabase.instancia.db;

  // ===========================================================================
  //  DETECCIÓN DE DUPLICADOS
  // ===========================================================================

  /// Busca eventos parecidos antes de guardar uno nuevo.
  ///
  /// POR QUÉ NO SE BLOQUEA POR RESTRICCIÓN EN LA BASE:
  /// una vaca sí puede tener mastitis dos veces en el mismo mes, y son dos
  /// episodios legítimos y distintos. Una restricción UNIQUE perdería datos
  /// reales. La decisión la toma un humano; la app solo avisa.
  ///
  /// El escenario que esto evita: Anthony registra la mastitis de la vaca 18
  /// el martes por la noche y Jhon la registra el miércoles sin saber que ya
  /// estaba. Dos filas para un solo episodio, y el conteo queda inflado.
  Future<List<PosibleDuplicado>> buscarPosiblesDuplicados({
    required String animalId,
    required String diagnosticoCodigo,
    required DateTime fechaDeteccion,
    int ventanaDias = 7,
  }) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      SELECT
        id,
        ts_deteccion_humana,
        -- julianday() convierte una fecha a número de días; la resta da la
        -- distancia exacta. ABS() la deja positiva sin importar el orden.
        ABS(julianday(ts_deteccion_humana) - julianday(?)) AS dias
      FROM evento_salud
      WHERE animal_id = ?
        AND diagnostico_codigo = ?
        AND eliminado = 0
        AND ABS(julianday(ts_deteccion_humana) - julianday(?)) <= ?
      ORDER BY dias ASC
    ''', [
      aIso(fechaDeteccion),   // primer '?' del SELECT
      animalId,
      diagnosticoCodigo,
      aIso(fechaDeteccion),   // el '?' del WHERE
      ventanaDias,
    ]);

    return filas.map((f) => PosibleDuplicado(
      eventoId: f['id'] as String,
      fecha: desdeIso(f['ts_deteccion_humana'] as String)!,
      // Los cálculos de julianday devuelven REAL, que en Dart llega como double.
      diasDeDiferencia: (f['dias'] as num).toDouble(),
    )).toList();
  }

  // ===========================================================================
  //  ESCRITURA
  // ===========================================================================

  /// Registra un evento de salud.
  ///
  /// El DAO fija `tsRegistro` con la hora del sistema: el usuario no puede
  /// tocarlo. Ese campo mide el retraso de digitación y perdería todo sentido
  /// si alguien pudiera editarlo.
  Future<EventoSalud> crear({
    required String animalId,
    required String diagnosticoCodigo,
    required DateTime tsDeteccionHumana,
    required String metodoDiagnostico,
    DateTime? tsInicioEstimado,
    String precisionTsInicio = PrecisionTs.desconocido,
    bool confirmado = false,
    String? confirmadoPor,
    int? severidad,
    String? notas,
    String? fotoRuta,
    String? creadoPor,
  }) async {
    final db = await _db;
    final ahoraFecha = DateTime.now();

    final evento = EventoSalud(
      id: _uuid.v4(),
      animalId: animalId,
      diagnosticoCodigo: diagnosticoCodigo,
      tsInicioEstimado: tsInicioEstimado,
      tsDeteccionHumana: tsDeteccionHumana,

      // La app lo pone, no el usuario.
      tsRegistro: ahoraFecha,

      precisionTsInicio: precisionTsInicio,
      metodoDiagnostico: metodoDiagnostico,
      confirmado: confirmado,
      confirmadoPor: confirmadoPor,
      severidad: severidad,
      notas: notas,
      fotoRuta: fotoRuta,
      creadoPor: creadoPor,
      modificadoEn: ahoraFecha,
    );

    // Si diagnosticoCodigo no existe en el catálogo, la clave foránea lanza
    // excepción aquí. Es lo que impide registrar 'ABORTO' como evento de salud.
    await db.insert(
      'evento_salud',
      evento.aFila(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return evento;
  }

  /// Marca un evento como confirmado por el veterinario.
  ///
  /// Se separa del guardado normal porque suele ocurrir después: primero el
  /// ordeñador anota lo que vio, y más tarde Jhon lo revisa y confirma.
  /// Solo los confirmados entran a la validación del algoritmo.
  Future<void> confirmar({
    required String eventoId,
    required String confirmadoPor,
    int? severidad,
  }) async {
    final db = await _db;

    await db.update(
      'evento_salud',
      {
        'confirmado': 1,
        'confirmado_por': confirmadoPor,
        // Solo se incluye severidad si viene un valor, para no borrar el que
        // ya estaba guardado.
        if (severidad != null) 'severidad': severidad,
        'modificado_en': ahora(),
      },
      where: 'id = ?',
      whereArgs: [eventoId],
    );
  }

  /// Cierra el episodio.
  Future<void> resolver({
    required String eventoId,
    required DateTime tsResolucion,
    required String desenlace,  // 'RECUPERADO','CRONICO','DESCARTE','MUERTE'
  }) async {
    final db = await _db;

    await db.update(
      'evento_salud',
      {
        'ts_resolucion': aIso(tsResolucion),
        'desenlace': desenlace,
        'modificado_en': ahora(),
      },
      where: 'id = ?',
      whereArgs: [eventoId],
    );
  }

  /// Borrado lógico. Se usa cuando se confirma que una fila era duplicada.
  Future<void> eliminar(String eventoId) async {
    final db = await _db;

    await db.update(
      'evento_salud',
      {'eliminado': 1, 'modificado_en': ahora()},
      where: 'id = ?',
      whereArgs: [eventoId],
    );
  }

  // ===========================================================================
  //  LECTURA
  // ===========================================================================

  /// Historial sanitario de un animal, del más reciente al más antiguo.
  Future<List<EventoSalud>> porAnimal(String animalId) async {
    final db = await _db;

    final filas = await db.query(
      'evento_salud',
      where: 'animal_id = ? AND eliminado = 0',
      whereArgs: [animalId],
      // DESC deja arriba lo más reciente, que es lo que interesa al abrir
      // la ficha de un animal.
      orderBy: 'ts_deteccion_humana DESC',
    );

    return filas.map(EventoSalud.desdeFila).toList();
  }

  /// Eventos abiertos: registrados pero sin resolución.
  /// Es la bandeja de trabajo de Jhon.
  Future<List<EventoSalud>> abiertos(String fincaId) async {
    final db = await _db;

    // rawQuery porque hace falta un JOIN con animal para filtrar por finca,
    // y db.query() solo consulta una tabla.
    final filas = await db.rawQuery('''
      SELECT e.*
      FROM evento_salud e
      JOIN animal a ON a.id = e.animal_id
      WHERE a.finca_id = ?
        AND e.ts_resolucion IS NULL
        AND e.eliminado = 0
        AND a.eliminado = 0
      ORDER BY e.ts_deteccion_humana DESC
    ''', [fincaId]);

    return filas.map(EventoSalud.desdeFila).toList();
  }

  /// Eventos confirmados pero sin fecha de inicio utilizable.
  ///
  /// Es la lista de "casos a completar": son eventos que hoy NO sirven para
  /// entrenar y que con una edición de treinta segundos sí servirían.
  /// Recuperar estos casos es de lo más rentable que puede hacer la app.
  Future<List<EventoSalud>> incompletos(String fincaId) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      SELECT e.*
      FROM evento_salud e
      JOIN animal a ON a.id = e.animal_id
      WHERE a.finca_id = ?
        AND e.eliminado = 0
        AND (
              e.ts_inicio_estimado IS NULL
           OR e.precision_ts_inicio NOT IN ('EXACTO','MAS_MENOS_6H','MAS_MENOS_1D')
           OR e.confirmado = 0
        )
      ORDER BY e.ts_deteccion_humana DESC
    ''', [fincaId]);

    return filas.map(EventoSalud.desdeFila).toList();
  }

  // ===========================================================================
  //  CONTEO
  // ===========================================================================

  /// Conteo de eventos por diagnóstico en un rango de fechas.
  ///
  /// Esta consulta es la que reemplaza al conteo retrospectivo imposible.
  /// Con 6 a 8 semanas de uso real da la tasa de incidencia medida, y con esa
  /// tasa se decide cuántos dispositivos comprar para la Fase 3.
  Future<List<ConteoDiagnostico>> contarPorDiagnostico({
    required String fincaId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final db = await _db;

    // Los filtros de fecha son opcionales, así que las condiciones se arman
    // dinámicamente. Los VALORES siguen viajando como parámetros: lo que se
    // construye es la estructura de la consulta, nunca el dato.
    final condiciones = <String>[
      'a.finca_id = ?',
      'e.eliminado = 0',
      'a.eliminado = 0',
    ];
    final args = <Object?>[fincaId];

    if (desde != null) {
      condiciones.add('e.ts_deteccion_humana >= ?');
      args.add(aIso(desde));
    }
    if (hasta != null) {
      condiciones.add('e.ts_deteccion_humana <= ?');
      args.add(aIso(hasta));
    }

    final filas = await db.rawQuery('''
      SELECT
        c.codigo,
        c.nombre,
        COUNT(*) AS total,
        -- COUNT solo cuenta valores no nulos, así que CASE sin ELSE permite
        -- contar condicionalmente sin escribir subconsultas.
        COUNT(CASE WHEN e.confirmado = 1 THEN 1 END) AS confirmados,
        COUNT(CASE
                WHEN e.confirmado = 1
                 AND e.ts_inicio_estimado IS NOT NULL
                 AND e.precision_ts_inicio IN ('EXACTO','MAS_MENOS_6H','MAS_MENOS_1D')
                THEN 1
              END) AS con_fecha_util
      FROM evento_salud e
      JOIN animal a              ON a.id     = e.animal_id
      JOIN catalogo_diagnostico c ON c.codigo = e.diagnostico_codigo
      WHERE ${condiciones.join(' AND ')}
      GROUP BY c.codigo, c.nombre
      ORDER BY total DESC
    ''', args);

    return filas.map((f) => ConteoDiagnostico(
      codigo:       f['codigo'] as String,
      nombre:       f['nombre'] as String,
      total:        f['total'] as int,
      confirmados:  f['confirmados'] as int,
      conFechaUtil: f['con_fecha_util'] as int,
    )).toList();
  }

  /// Total de etiquetas utilizables hasta hoy, leído de la vista unificada.
  ///
  /// Se consulta v_etiquetas_entrenamiento y no las tablas por separado: es la
  /// fuente única de verdad y ya combina salud con reproductivo sin duplicar.
  /// Sumar dos consultas separadas sería exactamente el error que el parche
  /// v1.1 evita.
  Future<int> totalEtiquetasUtiles() async {
    final db = await _db;

    final r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM v_etiquetas_entrenamiento',
    );

    return Sqflite.firstIntValue(r) ?? 0;
  }
}
