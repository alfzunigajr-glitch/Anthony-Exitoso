// =============================================================================
//  animal_dao.dart
//  DAO = Data Access Object. Todas las consultas SQL sobre `animal` viven aquí.
//
//  POR QUÉ EXISTE ESTA CAPA:
//  Si las pantallas ejecutaran SQL directamente, el día que cambie una columna
//  habría que buscarla por toda la app. Con el DAO, la pantalla pide
//  "dame el hato activo" y no sabe ni le importa cómo está escrita la consulta.
//
//  REGLA DE ESTE ARCHIVO: ninguna consulta usa DELETE. Todo borrado es lógico
//  (eliminado = 1). Una etiqueta que desaparece del dataset rompe el
//  entrenamiento sin dejar rastro de por qué.
// =============================================================================

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/fechas.dart';
import '../db/app_database.dart';
import '../models/animal.dart';

class AnimalDao {
  // Generador de UUID v4. Es `static` porque una sola instancia sirve para
  // toda la app; crear una nueva en cada llamada sería desperdicio.
  static const _uuid = Uuid();

  /// Acceso a la conexión compartida.
  Future<Database> get _db async => AppDatabase.instancia.db;

  // ===========================================================================
  //  LECTURA
  // ===========================================================================

  /// Hato activo de una finca, ordenado por arete.
  ///
  /// Es la consulta más frecuente de la app: alimenta la pantalla de inicio.
  Future<List<Animal>> listarActivos(String fincaId) async {
    final db = await _db;

    final filas = await db.query(
      'animal',

      // `where` con signos de interrogación, NUNCA concatenando texto.
      // Concatenar ("WHERE finca_id = '$fincaId'") abre la puerta a inyección
      // SQL y además rompe con cualquier valor que contenga una comilla.
      where: 'finca_id = ? AND activo = 1 AND eliminado = 0',

      // Los valores van aparte, en el mismo orden que los '?'.
      // sqflite los escapa por su cuenta.
      whereArgs: [fincaId],

      // COLLATE NOCASE ordena ignorando mayúsculas, para que 'v-18' y 'V-18'
      // queden juntos en la lista en vez de separados.
      orderBy: 'arete_interno COLLATE NOCASE',
    );

    // .map convierte cada fila en un Animal; .toList() materializa el resultado.
    // Sin toList(), map devuelve un iterable perezoso que se recalcularía en
    // cada recorrido.
    return filas.map(Animal.desdeFila).toList();
  }

  /// Busca un animal por su UUID. Devuelve null si no existe.
  Future<Animal?> porId(String id) async {
    final db = await _db;

    final filas = await db.query(
      'animal',
      where: 'id = ? AND eliminado = 0',
      whereArgs: [id],

      // limit: 1 detiene la búsqueda en el primer resultado. Como id es clave
      // primaria nunca habrá más de uno, pero se lo indicamos al motor igual.
      limit: 1,
    );

    // isEmpty en vez de comprobar length == 0: es lo idiomático en Dart.
    if (filas.isEmpty) return null;
    return Animal.desdeFila(filas.first);
  }

  /// Búsqueda por texto sobre arete oficial, arete interno y nombre.
  ///
  /// Pensada para el buscador de la pantalla principal: el usuario escribe
  /// "18" o "Lucera" y aparece el animal.
  Future<List<Animal>> buscar(String fincaId, String texto) async {
    final db = await _db;

    // LIKE con '%' a ambos lados busca el texto en cualquier posición.
    // El patrón se arma aquí y viaja como parámetro, no concatenado en el SQL.
    final patron = '%${texto.trim()}%';

    final filas = await db.query(
      'animal',
      where: '''
        finca_id = ?
        AND eliminado = 0
        AND (
              arete_interno LIKE ? COLLATE NOCASE
           OR arete_oficial LIKE ? COLLATE NOCASE
           OR nombre        LIKE ? COLLATE NOCASE
        )
      ''',
      // El patrón se repite tres veces porque hay tres '?' en la condición.
      whereArgs: [fincaId, patron, patron, patron],
      orderBy: 'activo DESC, arete_interno COLLATE NOCASE',
      // activo DESC pone primero los animales que siguen en el hato: es lo que
      // el usuario busca el 95 % de las veces.
      limit: 50,
    );

    return filas.map(Animal.desdeFila).toList();
  }

  /// Cuenta los animales activos. Para el encabezado de la pantalla.
  Future<int> contarActivos(String fincaId) async {
    final db = await _db;

    // rawQuery para funciones de agregación: db.query() no permite COUNT.
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM animal WHERE finca_id = ? AND activo = 1 AND eliminado = 0',
      [fincaId],
    );

    // Sqflite tiene un ayudante para leer un entero de la primera columna.
    // El `?? 0` cubre el caso improbable de que la consulta devuelva null.
    return Sqflite.firstIntValue(r) ?? 0;
  }

  // ===========================================================================
  //  ESCRITURA
  // ===========================================================================

  /// Da de alta un animal. Devuelve el objeto con su UUID ya asignado.
  ///
  /// El DAO genera el id y las marcas de tiempo, no la pantalla. Así ninguna
  /// pantalla puede olvidarse de ponerlas.
  Future<Animal> crear({
    required String fincaId,
    required String sexo,
    required String categoria,
    required DateTime fechaIngreso,
    String? areteOficial,
    String? areteInterno,
    String? nombre,
    DateTime? fechaNacimiento,
    bool nacimientoEstimado = false,
    String? raza,
    String? madreId,
    String? creadoPor,
  }) async {
    final db = await _db;
    final ahoraFecha = DateTime.now();

    final animal = Animal(
      // v4() genera un identificador aleatorio de 128 bits. La probabilidad de
      // que dos teléfonos generen el mismo es despreciable, y por eso no hace
      // falta coordinación entre dispositivos para que los ids no choquen.
      id: _uuid.v4(),
      fincaId: fincaId,
      areteOficial: areteOficial,
      areteInterno: areteInterno,
      nombre: nombre,
      sexo: sexo,
      fechaNacimiento: fechaNacimiento,
      nacimientoEstimado: nacimientoEstimado,
      raza: raza,
      madreId: madreId,
      categoria: categoria,
      fechaIngreso: fechaIngreso,
      activo: true,
      creadoEn: ahoraFecha,
      modificadoEn: ahoraFecha,
      creadoPor: creadoPor,
    );

    await db.insert(
      'animal',
      animal.aFila(),

      // abort = si la inserción viola una restricción, se lanza excepción.
      // Es lo que queremos: el esquema tiene UNIQUE(finca_id, arete_interno),
      // así que un arete repetido debe avisar al usuario, no guardarse callado.
      // Las otras opciones (replace, ignore) esconderían el problema.
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return animal;
  }

  /// Guarda los cambios de un animal existente.
  Future<void> actualizar(Animal animal) async {
    final db = await _db;

    // copyWith sin argumentos refresca `modificadoEn` a la hora actual,
    // porque ese es su valor por defecto.
    final actualizado = animal.copyWith();

    await db.update(
      'animal',
      actualizado.aFila(),
      where: 'id = ?',
      whereArgs: [animal.id],
    );
  }

  /// Registra la salida de un animal del hato.
  ///
  /// No borra nada: el animal queda con activo = 0 y su historial completo
  /// sigue disponible. Un animal que murió de mastitis es una de las etiquetas
  /// más valiosas del dataset; borrarlo sería perder justo el caso más severo.
  Future<void> registrarSalida({
    required String animalId,
    required DateTime fecha,
    required String motivo,   // 'VENTA', 'MUERTE', 'DESCARTE', 'ROBO'
  }) async {
    final db = await _db;

    await db.update(
      'animal',
      {
        'activo': 0,
        'fecha_salida': aFecha(fecha),
        'motivo_salida': motivo,
        'modificado_en': ahora(),
      },
      where: 'id = ?',
      whereArgs: [animalId],
    );
  }

  /// Borrado lógico. Solo para corregir un registro creado por error.
  ///
  /// Si el animal existió de verdad y salió del hato, corresponde
  /// registrarSalida(), no esto.
  Future<void> eliminar(String animalId) async {
    final db = await _db;

    await db.update(
      'animal',
      {'eliminado': 1, 'modificado_en': ahora()},
      where: 'id = ?',
      whereArgs: [animalId],
    );
  }
}
