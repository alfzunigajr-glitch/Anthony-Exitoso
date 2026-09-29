// =============================================================================
//  ayuda_pruebas.dart
//  Andamiaje compartido por todas las pruebas.
//
//  QUE RESUELVE:
//  sqflite normalmente corre sobre Android o iOS. Para probar en el computador
//  hace falta sqflite_common_ffi, que usa la biblioteca nativa de SQLite del
//  sistema. Asi las pruebas corren en segundos con `flutter test`, sin emulador.
//
//  Cada prueba arranca con una base EN MEMORIA totalmente vacia. Nada de lo
//  que hace una prueba puede afectar a otra, y no queda basura en el disco.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:app_ganado/core/fechas.dart';
import 'package:app_ganado/data/db/app_database.dart';
import 'package:app_ganado/data/models/diagnostico.dart';

/// Prepara el entorno. Se llama UNA vez, en el main() de cada archivo de prueba.
void prepararEntorno() {
  // Inicializa el enlace con Flutter. Es obligatorio ANTES de usar rootBundle:
  // sin esta linea, cargar los .sql desde assets falla con un error que no
  // menciona los assets por ningun lado y cuesta rastrear.
  TestWidgetsFlutterBinding.ensureInitialized();

  // Carga la implementacion nativa de SQLite para escritorio.
  sqfliteFfiInit();

  // Reemplaza la fabrica global. A partir de aqui, cualquier openDatabase()
  // de la app usa FFI en vez de intentar hablar con Android. Por eso el codigo
  // de produccion no necesita saber que esta en una prueba.
  databaseFactory = databaseFactoryFfi;
}

/// Abre una base limpia en memoria. Se llama en el setUp() de cada prueba.
Future<void> baseLimpia() async {
  // Si quedo una conexion de la prueba anterior, se cierra.
  await AppDatabase.instancia.cerrar();

  // inMemoryDatabasePath es la constante ':memory:'. SQLite trabaja en RAM y
  // todo desaparece al cerrar la conexion.
  AppDatabase.rutaDePrueba = inMemoryDatabasePath;

  // El catalogo de diagnosticos se cachea en memoria de forma estatica. Si no
  // se limpia, la segunda prueba leeria el catalogo de la primera, que ya no
  // existe en la base nueva.
  DiagnosticoDao.limpiarCache();

  // Forzar la apertura ejecuta las migraciones y deja el esquema listo.
  await AppDatabase.instancia.db;
}

/// Cierra la base. Se llama en el tearDown().
Future<void> cerrarBase() async {
  await AppDatabase.instancia.cerrar();
}

// =============================================================================
//  DATOS DE PRUEBA
// =============================================================================

/// Fecha de referencia FIJA, no DateTime.now().
///
/// POR QUE IMPORTA: una prueba que use la hora real puede pasar hoy y fallar
/// manianiana, o fallar solo si corre a medianoche. Con una fecha fija, el
/// resultado es siempre el mismo. Se elige un miercoles al mediodia para no
/// caer en un cambio de dia por el desfase horario.
final fechaBase = DateTime(2026, 6, 10, 12, 0, 0);

/// Devuelve una fecha desplazada respecto de [fechaBase].
/// `haceDias(3)` da tres dias antes; `haceDias(-2)` da dos dias despues.
DateTime haceDias(int dias) => fechaBase.subtract(Duration(days: dias));

/// Texto ISO listo para insertar directamente con SQL crudo.
String isoHace(int dias) => aIso(haceDias(dias));
