// =============================================================================
//  evento_reproductivo_dao.dart
//
//  Ademas de las operaciones normales, este DAO resuelve algo que el archivo
//  .sql dejo abierto a proposito: la vista v_etiquetas marca todos los celos
//  con confirmado = 0, porque comprobar si un celo era real exige mirar
//  eventos POSTERIORES (servicio y palpacion) y anidar esa subconsulta dentro
//  de la vista la volveria lenta.
//  La confirmacion retroactiva se hace aqui, con confirmarCelosRetroactivo().
// =============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/fechas.dart';
import '../db/app_database.dart';
import '../models/evento_reproductivo.dart';
import '../models/evento_salud.dart' show PrecisionTs;

/// Celo cuya validez quedo comprobada por una prenez posterior.
class CeloConfirmado {
  final String celoId;
  final DateTime fechaCelo;
  final String metodoDeteccion;
  final DateTime fechaServicio;
  final DateTime fechaPalpacion;

  const CeloConfirmado({
    required this.celoId,
    required this.fechaCelo,
    required this.metodoDeteccion,
    required this.fechaServicio,
    required this.fechaPalpacion,
  });
}

class EventoReproductivoDao {
  static const _uuid = Uuid();

  Future<Database> get _db async => AppDatabase.instancia.db;

  // ===========================================================================
  //  ESCRITURA
  // ===========================================================================

  /// Registra cualquier evento reproductivo.
  ///
  /// Es un metodo unico para los seis tipos en vez de seis metodos separados.
  /// Los campos que no aplican a un tipo quedan en null, que es exactamente lo
  /// que el esquema espera.
  Future<EventoReproductivo> crear({
    required String animalId,
    required String tipo,
    required DateTime tsEvento,
    String precisionTs = PrecisionTs.desconocido,
    String? metodoDeteccion,
    String? resultado,
    String? servicioTipo,
    String? identificadorSemen,
    int? numeroServicio,
    int? criasNacidas,
    int? dificultadParto,
    String? ejecutadoPor,
    String? notas,
  }) async {
    final db = await _db;
    final ahoraFecha = DateTime.now();

    final evento = EventoReproductivo(
      id: _uuid.v4(),
      animalId: animalId,
      tipo: tipo,
      tsEvento: tsEvento,
      precisionTs: precisionTs,
      metodoDeteccion: metodoDeteccion,
      resultado: resultado,
      servicioTipo: servicioTipo,
      identificadorSemen: identificadorSemen,
      numeroServicio: numeroServicio,
      criasNacidas: criasNacidas,
      dificultadParto: dificultadParto,
      ejecutadoPor: ejecutadoPor,
      notas: notas,
      creadoEn: ahoraFecha,
      modificadoEn: ahoraFecha,
    );

    await db.insert(
      'evento_reproductivo',
      evento.aFila(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return evento;
  }

  /// Atajo para registrar un aborto.
  ///
  /// Existe como metodo propio porque es la via UNICA de registrarlo. Si en el
  /// futuro alguien busca "aborto" en el codigo, encuentra este metodo y no se
  /// le ocurre intentar meterlo por evento_salud (donde de todos modos la
  /// clave foranea lo rechazaria, porque 'ABORTO' no esta en el catalogo).
  Future<EventoReproductivo> registrarAborto({
    required String animalId,
    required DateTime fecha,
    String precisionTs = PrecisionTs.masMenos1d,
    String? ejecutadoPor,
    String? notas,
  }) {
    return crear(
      animalId: animalId,
      tipo: TipoRepro.aborto,
      tsEvento: fecha,
      precisionTs: precisionTs,
      ejecutadoPor: ejecutadoPor,
      notas: notas,
    );
  }

  Future<void> actualizar(EventoReproductivo evento) async {
    final db = await _db;

    // El operador de propagacion (...) copia todo el mapa y luego se
    // sobrescribe la marca de modificacion con la hora actual.
    await db.update(
      'evento_reproductivo',
      {...evento.aFila(), 'modificado_en': ahora()},
      where: 'id = ?',
      whereArgs: [evento.id],
    );
  }

  Future<void> eliminar(String id) async {
    final db = await _db;
    await db.update(
      'evento_reproductivo',
      {'eliminado': 1, 'modificado_en': ahora()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ===========================================================================
  //  LECTURA
  // ===========================================================================

  /// Historial reproductivo de un animal, del mas reciente al mas antiguo.
  Future<List<EventoReproductivo>> porAnimal(String animalId) async {
    final db = await _db;

    final filas = await db.query(
      'evento_reproductivo',
      where: 'animal_id = ? AND eliminado = 0',
      whereArgs: [animalId],
      orderBy: 'ts_evento DESC',
    );

    return filas.map(EventoReproductivo.desdeFila).toList();
  }

  /// Eventos de un tipo especifico en un rango de fechas, para toda la finca.
  ///
  /// La consulta clave para el cronograma: con tipo = PARTO da la distribucion
  /// de partos en el anio, que es lo que define en que meses debe correr la
  /// Fase 3. La mayor parte de la patologia aparece en el periodo de
  /// transicion, asi que instrumentar fuera de la temporada de partos
  /// desperdicia collares.
  Future<List<EventoReproductivo>> porTipo({
    required String fincaId,
    required String tipo,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final db = await _db;

    // Las condiciones se arman de forma dinamica porque las fechas son
    // opcionales. Lo que se construye es la ESTRUCTURA de la consulta; los
    // valores siguen viajando como parametros y nunca concatenados.
    final condiciones = <String>[
      'a.finca_id = ?',
      'r.tipo = ?',
      'r.eliminado = 0',
      'a.eliminado = 0',
    ];
    final args = <Object?>[fincaId, tipo];

    if (desde != null) {
      condiciones.add('r.ts_evento >= ?');
      args.add(aIso(desde));
    }
    if (hasta != null) {
      condiciones.add('r.ts_evento <= ?');
      args.add(aIso(hasta));
    }

    final filas = await db.rawQuery('''
      SELECT r.*
      FROM evento_reproductivo r
      JOIN animal a ON a.id = r.animal_id
      WHERE ${condiciones.join(' AND ')}
      ORDER BY r.ts_evento DESC
    ''', args);

    return filas.map(EventoReproductivo.desdeFila).toList();
  }

  /// Ultimo parto de un animal. Devuelve null si nunca pario.
  ///
  /// Sirve para dos cosas: calcular los dias en leche, y saber si el animal
  /// esta en periodo de transicion (tres semanas antes a tres despues del
  /// parto), que es cuando conviene tener el collar puesto.
  Future<EventoReproductivo?> ultimoParto(String animalId) async {
    final db = await _db;

    final filas = await db.query(
      'evento_reproductivo',
      where: 'animal_id = ? AND tipo = ? AND eliminado = 0',
      whereArgs: [animalId, TipoRepro.parto],
      orderBy: 'ts_evento DESC',
      limit: 1,
    );

    if (filas.isEmpty) return null;
    return EventoReproductivo.desdeFila(filas.first);
  }

  /// Dias en leche: dias transcurridos desde el ultimo parto.
  /// Devuelve null si el animal nunca pario.
  Future<int?> diasEnLeche(String animalId) async {
    final parto = await ultimoParto(animalId);
    if (parto == null) return null;
    return DateTime.now().difference(parto.tsEvento).inDays;
  }

  /// Animales en periodo de transicion: entre 21 dias antes y 21 despues del
  /// parto. Es donde se concentra la mayor parte de la patologia del hato.
  ///
  /// EN FASE 3 ESTA CONSULTA DECIDE DONDE VAN LOS COLLARES. Una vaca sana en
  /// mitad de lactancia produce seis meses de senal aburrida y cero etiquetas;
  /// una vaca en transicion produce etiquetas. Rotar los collares sobre estos
  /// animales multiplica el rendimiento por dispositivo.
  ///
  /// Nota: solo detecta la ventana POSTERIOR al parto, porque la anterior
  /// requiere fecha probable de parto y eso exige registrar el servicio con
  /// su fecha. Se calculara cuando haya suficientes servicios registrados.
  Future<List<String>> animalesEnTransicion({
    required String fincaId,
    int diasDespuesParto = 21,
  }) async {
    final db = await _db;

    final filas = await db.rawQuery('''
      SELECT DISTINCT r.animal_id
      FROM evento_reproductivo r
      JOIN animal a ON a.id = r.animal_id
      WHERE a.finca_id = ?
        AND r.tipo = 'PARTO'
        AND r.eliminado = 0
        AND a.eliminado = 0
        AND a.activo = 1
        -- julianday('now') da el momento actual como numero de dias.
        -- La resta da cuantos dias pasaron desde el parto.
        AND julianday('now') - julianday(r.ts_evento) BETWEEN 0 AND ?
    ''', [fincaId, diasDespuesParto]);

    // Se devuelve solo la lista de ids. Quien la llama decide si necesita el
    // objeto Animal completo y lo pide al AnimalDao.
    return filas.map((f) => f['animal_id'] as String).toList();
  }

  // ===========================================================================
  //  CONFIRMACION RETROACTIVA DE CELOS
  // ===========================================================================

  /// Devuelve los celos cuya validez quedo comprobada por una prenez posterior.
  ///
  /// LA CADENA DE COMPROBACION:
  ///   1. Hay un CELO en el momento T.
  ///   2. Hay un SERVICIO entre T y T + 3 dias (se insemina sobre ese celo).
  ///   3. Hay una PALPACION con resultado PRENIADA despues del servicio,
  ///      dentro de la ventana en que la palpacion es diagnostica.
  ///
  /// Si se cumplen las tres, ese celo fue REAL, no una apreciacion equivocada.
  ///
  /// POR QUE IMPORTA TANTO: cuando el collar detecte celo, hay que medir su
  /// acierto contra algo. Un celo "visto" por el ordeniador puede ser un falso
  /// positivo. Un celo seguido de prenez, no. Estos son los unicos casos con
  /// los que se puede medir el algoritmo sin enganiarse.
  Future<List<CeloConfirmado>> confirmarCelosRetroactivo({
    required String fincaId,

    /// Maximo de dias entre el celo y el servicio. La inseminacion se hace
    /// dentro de las horas siguientes al celo; 3 dias da margen sin admitir
    /// servicios que en realidad pertenecen a otro ciclo.
    int diasMaxCeloServicio = 3,

    /// Ventana en que la palpacion es diagnostica tras el servicio.
    int diasMinServicioPalpacion = 25,
    int diasMaxServicioPalpacion = 120,
  }) async {
    final db = await _db;

    // Tres auto-uniones sobre la misma tabla: una por cada eslabon de la
    // cadena. Los alias c, s y pl distinguen cada copia.
    final filas = await db.rawQuery('''
      SELECT
        c.id            AS celo_id,
        c.ts_evento     AS fecha_celo,
        c.metodo_deteccion,
        s.ts_evento     AS fecha_servicio,
        pl.ts_evento    AS fecha_palpacion
      FROM evento_reproductivo c

      JOIN animal a ON a.id = c.animal_id

      -- Eslabon 2: el servicio que siguio a este celo
      JOIN evento_reproductivo s
           ON  s.animal_id = c.animal_id
           AND s.tipo = 'SERVICIO'
           AND s.eliminado = 0
           -- El servicio va DESPUES del celo
           AND julianday(s.ts_evento) >= julianday(c.ts_evento)
           -- y dentro de la ventana permitida
           AND julianday(s.ts_evento) - julianday(c.ts_evento) <= ?

      -- Eslabon 3: la palpacion que confirmo la prenez
      JOIN evento_reproductivo pl
           ON  pl.animal_id = c.animal_id
           AND pl.tipo = 'PALPACION'
           AND pl.resultado = 'PRENIADA'
           AND pl.eliminado = 0
           AND julianday(pl.ts_evento) - julianday(s.ts_evento) BETWEEN ? AND ?

      WHERE a.finca_id = ?
        AND c.tipo = 'CELO'
        AND c.eliminado = 0
        AND a.eliminado = 0

      -- GROUP BY sobre el id del celo: si hubo dos palpaciones preniadas para
      -- el mismo servicio, el celo debe aparecer UNA sola vez. Sin esto, el
      -- conteo de celos confirmados se inflaria, que es justo el error que el
      -- parche v1.1 se dedica a evitar en el resto del esquema.
      GROUP BY c.id

      ORDER BY c.ts_evento DESC
    ''', [
      diasMaxCeloServicio,
      diasMinServicioPalpacion,
      diasMaxServicioPalpacion,
      fincaId,
    ]);

    return filas.map((f) => CeloConfirmado(
      celoId:          f['celo_id'] as String,
      fechaCelo:       desdeIso(f['fecha_celo'] as String)!,
      metodoDeteccion: f['metodo_deteccion'] as String? ?? 'VISUAL',
      fechaServicio:   desdeIso(f['fecha_servicio'] as String)!,
      fechaPalpacion:  desdeIso(f['fecha_palpacion'] as String)!,
    )).toList();
  }

  /// Cuenta eventos por tipo. Alimenta la pantalla de conteo junto con el
  /// conteo de eventos de salud.
  Future<Map<String, int>> contarPorTipo({
    required String fincaId,
    DateTime? desde,
    DateTime? hasta,
  }) async {
    final db = await _db;

    final condiciones = <String>[
      'a.finca_id = ?',
      'r.eliminado = 0',
      'a.eliminado = 0',
    ];
    final args = <Object?>[fincaId];

    if (desde != null) {
      condiciones.add('r.ts_evento >= ?');
      args.add(aIso(desde));
    }
    if (hasta != null) {
      condiciones.add('r.ts_evento <= ?');
      args.add(aIso(hasta));
    }

    final filas = await db.rawQuery('''
      SELECT r.tipo, COUNT(*) AS n
      FROM evento_reproductivo r
      JOIN animal a ON a.id = r.animal_id
      WHERE ${condiciones.join(' AND ')}
      GROUP BY r.tipo
      ORDER BY n DESC
    ''', args);

    // Se arma un Map tipo -> cantidad usando un "collection for", que es mas
    // compacto que crear el mapa vacio y llenarlo en un bucle aparte.
    return {
      for (final f in filas) f['tipo'] as String: f['n'] as int,
    };
  }
}
