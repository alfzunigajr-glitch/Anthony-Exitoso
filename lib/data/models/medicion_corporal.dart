// =============================================================================
//  medicion_corporal.dart
//  Modelo y DAO de `medicion_corporal`: peso y condicion corporal.
//
//  Es el DAO mas simple de la Fase 1, por eso modelo y acceso van juntos.
//  Su utilidad para el proyecto es indirecta pero real: la condicion corporal
//  al parto predice buena parte de la patologia del posparto. Cuando haya que
//  decidir a que vacas ponerles collar, este dato ayuda a elegir las de mayor
//  riesgo.
// =============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/fechas.dart';
import '../db/app_database.dart';

/// Como se obtuvo el peso.
///
/// IMPORTA MAS DE LO QUE PARECE: la cinta bovina tiene un error del 5 al 10 %.
/// Si no se sabe con que se midio, una diferencia de 20 kg entre dos fechas
/// podria ser un cambio real del animal o simplemente el error del instrumento.
class MetodoPeso {
  static const bascula  = 'BASCULA';
  static const cinta    = 'CINTA';
  static const estimado = 'ESTIMADO';

  static const todos = [bascula, cinta, estimado];

  static String nombre(String m) {
    switch (m) {
      case bascula:  return 'Báscula';
      case cinta:    return 'Cinta bovina';
      case estimado: return 'Estimado a ojo';
      default:       return m;
    }
  }
}

class MedicionCorporal {
  final String id;
  final String animalId;
  final DateTime fecha;
  final double? pesoKg;
  final String? metodoPeso;

  /// Condicion corporal en escala 1 a 5, en pasos de 0.25.
  /// Por eso es double y no int: 3.25 y 3.5 son valores validos y distintos.
  final double? condicionCorporal;

  final DateTime creadoEn;

  const MedicionCorporal({
    required this.id,
    required this.animalId,
    required this.fecha,
    this.pesoKg,
    this.metodoPeso,
    this.condicionCorporal,
    required this.creadoEn,
  });

  factory MedicionCorporal.desdeFila(Map<String, Object?> f) {
    return MedicionCorporal(
      id:                f['id'] as String,
      animalId:          f['animal_id'] as String,
      fecha:             desdeIso(f['fecha'] as String)!,
      pesoKg:            (f['peso_kg'] as num?)?.toDouble(),
      metodoPeso:        f['metodo_peso'] as String?,
      condicionCorporal: (f['condicion_corporal'] as num?)?.toDouble(),
      creadoEn:          desdeIso(f['creado_en'] as String)!,
    );
  }

  Map<String, Object?> aFila() => {
        'id':                 id,
        'animal_id':          animalId,
        'fecha':              aFecha(fecha),
        'peso_kg':            pesoKg,
        'metodo_peso':        metodoPeso,
        'condicion_corporal': condicionCorporal,
        'creado_en':          aIso(creadoEn),
      };

  /// Si la medicion es lo bastante precisa para comparar contra otra fecha.
  /// Solo la bascula lo es; la cinta y el ojo tienen demasiado error.
  bool get esComparable => metodoPeso == MetodoPeso.bascula;
}

class MedicionCorporalDao {
  static const _uuid = Uuid();

  Future<Database> get _db async => AppDatabase.instancia.db;

  Future<MedicionCorporal> crear({
    required String animalId,
    required DateTime fecha,
    double? pesoKg,
    String? metodoPeso,
    double? condicionCorporal,
  }) async {
    final db = await _db;

    final medicion = MedicionCorporal(
      id: _uuid.v4(),
      animalId: animalId,
      fecha: fecha,
      pesoKg: pesoKg,
      metodoPeso: metodoPeso,
      condicionCorporal: condicionCorporal,
      creadoEn: DateTime.now(),
    );

    await db.insert('medicion_corporal', medicion.aFila());
    return medicion;
  }

  /// Historial de mediciones de un animal, de la mas reciente hacia atras.
  Future<List<MedicionCorporal>> porAnimal(String animalId) async {
    final db = await _db;

    final filas = await db.query(
      'medicion_corporal',
      where: 'animal_id = ? AND eliminado = 0',
      whereArgs: [animalId],
      orderBy: 'fecha DESC',
    );

    return filas.map(MedicionCorporal.desdeFila).toList();
  }

  /// Ultima medicion registrada. Devuelve null si nunca se peso.
  Future<MedicionCorporal?> ultima(String animalId) async {
    final db = await _db;

    final filas = await db.query(
      'medicion_corporal',
      where: 'animal_id = ? AND eliminado = 0',
      whereArgs: [animalId],
      orderBy: 'fecha DESC',
      limit: 1,
    );

    if (filas.isEmpty) return null;
    return MedicionCorporal.desdeFila(filas.first);
  }

  Future<void> eliminar(String id) async {
    final db = await _db;
    await db.update(
      'medicion_corporal',
      {'eliminado': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
