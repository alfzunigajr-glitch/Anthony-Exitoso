// =============================================================================
//  finca.dart
//  Modelo y DAO de la tabla `finca`.
//
//  Hoy habrá una sola fila (la finca de Jhon), pero se maneja como tabla
//  normal porque el día que entre una segunda finca no habrá que migrar nada.
//  Modelo y DAO van juntos en un archivo por ser pocas líneas; los objetos
//  grandes sí se separan.
// =============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/fechas.dart';
import '../db/app_database.dart';

class Finca {
  final String id;
  final String nombre;
  final String? propietario;
  final String? provincia;
  final String? canton;
  final double? latitud;
  final double? longitud;

  /// Altitud en metros sobre el nivel del mar.
  /// No es un dato decorativo: en la Sierra la altura afecta el consumo de
  /// batería del collar y el comportamiento térmico del animal. Cuando haya
  /// varias fincas, será una variable a controlar en el análisis.
  final int? altitudMsnm;

  final DateTime creadoEn;

  const Finca({
    required this.id,
    required this.nombre,
    this.propietario,
    this.provincia,
    this.canton,
    this.latitud,
    this.longitud,
    this.altitudMsnm,
    required this.creadoEn,
  });

  factory Finca.desdeFila(Map<String, Object?> f) {
    return Finca(
      id:          f['id'] as String,
      nombre:      f['nombre'] as String,
      propietario: f['propietario'] as String?,
      provincia:   f['provincia'] as String?,
      canton:      f['canton'] as String?,

      // Las columnas REAL de SQLite llegan a Dart como double, pero un valor
      // entero guardado en columna REAL puede llegar como int. `as num?`
      // acepta ambos y toDouble() normaliza. El `?.` deja pasar el null.
      latitud:  (f['latitud'] as num?)?.toDouble(),
      longitud: (f['longitud'] as num?)?.toDouble(),

      altitudMsnm: f['altitud_msnm'] as int?,
      creadoEn:    desdeIso(f['creado_en'] as String)!,
    );
  }

  Map<String, Object?> aFila() => {
        'id':           id,
        'nombre':       nombre,
        'propietario':  propietario,
        'provincia':    provincia,
        'canton':       canton,
        'latitud':      latitud,
        'longitud':     longitud,
        'altitud_msnm': altitudMsnm,
        'creado_en':    aIso(creadoEn),
      };
}

class FincaDao {
  static const _uuid = Uuid();

  Future<Database> get _db async => AppDatabase.instancia.db;

  /// Devuelve la finca activa, o null si la app todavía no fue configurada.
  ///
  /// Es lo primero que consulta la app al arrancar: si devuelve null, hay que
  /// mostrar la pantalla de configuración inicial en vez de la lista del hato.
  Future<Finca?> actual() async {
    final db = await _db;

    final filas = await db.query(
      'finca',
      where: 'eliminado = 0',
      orderBy: 'creado_en ASC',  // La primera creada es la principal
      limit: 1,
    );

    if (filas.isEmpty) return null;
    return Finca.desdeFila(filas.first);
  }

  Future<Finca> crear({
    required String nombre,
    String? propietario,
    String? provincia,
    String? canton,
    double? latitud,
    double? longitud,
    int? altitudMsnm,
  }) async {
    final db = await _db;

    final finca = Finca(
      id: _uuid.v4(),
      nombre: nombre,
      propietario: propietario,
      provincia: provincia,
      canton: canton,
      latitud: latitud,
      longitud: longitud,
      altitudMsnm: altitudMsnm,
      creadoEn: DateTime.now(),
    );

    await db.insert('finca', finca.aFila());
    return finca;
  }

  Future<void> actualizar(Finca finca) async {
    final db = await _db;
    await db.update(
      'finca',
      finca.aFila(),
      where: 'id = ?',
      whereArgs: [finca.id],
    );
  }
}
