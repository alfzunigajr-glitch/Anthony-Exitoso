// =============================================================================
//  app_database.dart
//  Punto único de acceso a la base SQLite de la app.
//
//  RESPONSABILIDADES:
//   - Abrir la base una sola vez y reutilizar esa conexión.
//   - Activar los PRAGMAs obligatorios en cada apertura.
//   - Ejecutar las migraciones en orden cuando cambia la versión del esquema.
//   - Leer los archivos .sql desde assets y partirlos en sentencias.
//
//  DECISIÓN DE DISEÑO: el esquema vive en archivos .sql dentro de assets/,
//  no como cadenas de texto dentro de este archivo Dart. Motivo: el .sql es
//  la fuente única de verdad. Se puede abrir con cualquier herramienta SQL,
//  revisar y versionar. Duplicarlo en Dart garantiza que tarde o temprano las
//  dos copias se desincronicen.
// =============================================================================

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  // Constructor privado. El guion bajo impide que otras partes de la app
  // hagan `AppDatabase()` y creen una segunda instancia con su propia
  // conexión: dos conexiones a la misma base pueden bloquearse entre sí.
  AppDatabase._();

  /// Instancia única (patrón singleton). `static final` significa que se crea
  /// una sola vez en toda la vida de la app y se comparte.
  static final AppDatabase instancia = AppDatabase._();

  /// Nombre del archivo físico dentro del almacenamiento privado de la app.
  static const String _nombreArchivo = 'ganado.db';

  /// Versión actual del esquema.
  /// Al subir este número, sqflite ejecuta `onUpgrade` en el próximo arranque.
  ///   1 -> esquema inicial
  ///   2 -> parche: prolapso, aborto sin duplicar, triggers anti-solape
  static const int _version = 2;

  /// Conexión abierta. Es nullable porque antes del primer `abrir()` no existe.
  Database? _db;

  /// Ruta alternativa, solo para pruebas.
  ///
  /// POR QUÉ EXISTE: las pruebas necesitan una base limpia en cada caso, y
  /// crear archivos reales las volvería lentas y dejaría basura en el disco.
  /// Poniendo aquí `inMemoryDatabasePath`, SQLite trabaja en RAM y todo
  /// desaparece al cerrar.
  ///
  /// En producción vale null y no cambia nada. Es un punto de inyección
  /// mínimo: la alternativa sería pasar la ruta por constructor a lo largo de
  /// toda la app solo para poder probarla, que es mucho ruido para lo que
  /// resuelve.
  static String? rutaDePrueba;

  /// Devuelve la conexión, abriéndola la primera vez.
  ///
  /// El `async` obliga a llamarla con `await`, pero a partir del segundo
  /// llamado devuelve la conexión ya abierta sin tocar el disco.
  Future<Database> get db async {
    // Si ya está abierta, se devuelve directamente.
    // El `!` le dice a Dart que en esta rama _db no puede ser null.
    if (_db != null) return _db!;
    _db = await _abrir();
    return _db!;
  }

  Future<Database> _abrir() async {
    // En pruebas, rutaDePrueba trae inMemoryDatabasePath y se salta el disco.
    // El operador ?? devuelve lo de la derecha solo si lo de la izquierda es
    // null, así que en producción esta línea se comporta como si no existiera.
    final ruta = rutaDePrueba ?? await _rutaEnDisco();

    return openDatabase(
      ruta,
      version: _version,

      // ---- onConfigure ---------------------------------------------------
      // Se ejecuta en CADA apertura, antes que onCreate y onUpgrade.
      // Es el único lugar correcto para las claves foráneas: sqflite las trae
      // desactivadas por defecto y hay que encenderlas en cada conexión, no
      // una sola vez al crear la base.
      //
      // Si esto falta, toda la protección contra duplicación del parche v1.1
      // deja de funcionar en silencio: se podría insertar 'ABORTO' como
      // evento de salud sin que nada se queje.
      onConfigure: (Database db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },

      // ---- onCreate ------------------------------------------------------
      // Se ejecuta UNA sola vez, cuando el archivo no existe todavía.
      // Aplica todas las migraciones desde cero, en orden.
      onCreate: (Database db, int version) async {
        for (var v = 1; v <= version; v++) {
          await _aplicarMigracion(db, v);
        }
      },

      // ---- onUpgrade -----------------------------------------------------
      // Se ejecuta cuando la base existente tiene una versión menor que
      // `_version`. Aplica solo las migraciones que faltan.
      //
      // Ejemplo: el teléfono de Jhon tiene la versión 1 instalada y se
      // actualiza la app a la versión 2. Aquí anterior=1 y nueva=2, así que
      // corre únicamente v2_parche.sql. Sus datos NO se tocan.
      //
      // Esto es lo que permite corregir el esquema sin pedirle a nadie que
      // borre la app y pierda meses de registros.
      onUpgrade: (Database db, int anterior, int nueva) async {
        for (var v = anterior + 1; v <= nueva; v++) {
          await _aplicarMigracion(db, v);
        }
      },

      // ---- onOpen --------------------------------------------------------
      // Se ejecuta al final de cada apertura, con el esquema ya listo.
      onOpen: (Database db) async {
        // WAL (Write-Ahead Logging) permite leer mientras se escribe: evita
        // que la pantalla se congele si se consulta una ficha justo cuando se
        // guarda otro registro. También resiste mejor que el teléfono se
        // apague a mitad de una escritura, cosa habitual en campo.
        //
        // Se usa rawQuery y no execute porque este PRAGMA DEVUELVE un valor
        // (el modo que quedó activo). Con execute, sqflite lanza excepción en
        // algunas versiones de Android.
        await db.rawQuery('PRAGMA journal_mode = WAL');
      },
    );
  }

  /// Ruta del archivo de base de datos en el almacenamiento del teléfono.
  Future<String> _rutaEnDisco() async {
    // getDatabasesPath() devuelve la carpeta privada de bases de datos que el
    // sistema operativo asigna a la app. En Android suele ser
    // /data/data/<paquete>/databases. Es privada: ninguna otra app la lee.
    final carpeta = await getDatabasesPath();

    // p.join arma la ruta con el separador correcto de cada sistema
    // (/ en Android, \ en Windows). Concatenar con '+' rompe en algún sistema.
    return p.join(carpeta, _nombreArchivo);
  }

  /// Lee el archivo .sql de la migración indicada y ejecuta sus sentencias.
  Future<void> _aplicarMigracion(Database db, int version) async {
    // Mapa de versión a archivo. Al agregar una migración v3, se añade aquí
    // la línea correspondiente y se sube la constante _version.
    const archivos = <int, String>{
      1: 'assets/sql/v1_esquema.sql',
      2: 'assets/sql/v2_parche.sql',
    };

    final ruta = archivos[version];
    // Si alguien sube _version sin registrar el archivo, es mejor fallar de
    // inmediato y ruidosamente que arrancar con un esquema incompleto.
    if (ruta == null) {
      throw StateError('No hay archivo SQL para la migración $version');
    }

    // rootBundle lee archivos empaquetados dentro del APK. Son de solo
    // lectura, que es exactamente lo que se quiere: el esquema no se modifica
    // en tiempo de ejecución.
    final contenido = await rootBundle.loadString(ruta);

    // Cada sentencia se ejecuta por separado. sqflite no acepta varias
    // sentencias en un solo execute().
    for (final sentencia in _partirSentencias(contenido)) {
      await db.execute(sentencia);
    }
  }

  /// Parte un archivo .sql en sentencias individuales.
  ///
  /// POR QUÉ NO BASTA CON `contenido.split(';')`:
  /// los triggers del parche v1.1 llevan punto y coma DENTRO de su cuerpo:
  ///
  ///     CREATE TRIGGER trg_asignacion_sin_solape
  ///     ...
  ///     BEGIN
  ///         SELECT RAISE(ABORT, '...');   <-- este punto y coma
  ///     END;                              <-- y este
  ///
  /// Partir por ';' cortaría el trigger en pedazos y cada pedazo daría error
  /// de sintaxis. Por eso se lleva la cuenta de los bloques BEGIN...END y solo
  /// se corta cuando el contador está en cero.
  List<String> _partirSentencias(String sql) {
    final sentencias = <String>[];
    final actual = StringBuffer();  // StringBuffer acumula texto sin crear
                                    // una cadena nueva en cada concatenación
    var profundidad = 0;            // Cuántos BEGIN hay abiertos ahora mismo

    for (final lineaCruda in sql.split('\n')) {
      // Se quita el comentario del final ANTES de cualquier evaluación.
      //
      // ESTE PASO NO ES OPCIONAL. El esquema tiene líneas como:
      //     observador  TEXT NOT NULL,   -- Dos personas etiquetan distinto;
      // El comentario termina en punto y coma. Si se evaluara la línea
      // completa, el partidor cortaría la tabla por la mitad y la app fallaría
      // al arrancar con un error de sintaxis muy difícil de rastrear.
      final linea = _quitarComentario(lineaCruda).trim();

      // Las líneas vacías y las que solo tenían comentario se descartan.
      // Los comentarios son valiosos en el .sql pero no aportan al motor.
      if (linea.isEmpty) continue;

      actual.writeln(linea);

      // Se compara en mayúsculas para que dé igual cómo esté escrito.
      final mayus = linea.toUpperCase();

      // Un BEGIN abre bloque. Se exige que la línea TERMINE en BEGIN para no
      // confundirse con 'BEGIN TRANSACTION' u otras apariciones sueltas.
      if (mayus.endsWith('BEGIN')) {
        profundidad++;
      }
      // 'END;' cierra el bloque del trigger.
      else if (mayus.startsWith('END;')) {
        profundidad--;
        if (profundidad == 0) {
          sentencias.add(actual.toString().trim());
          actual.clear();
        }
      }
      // Punto y coma fuera de cualquier bloque: fin de sentencia normal.
      else if (profundidad == 0 && linea.endsWith(';')) {
        sentencias.add(actual.toString().trim());
        actual.clear();
      }
    }

    // Si quedó texto sin cerrar con ';', se agrega igual. Cubre archivos que
    // terminan sin punto y coma final.
    final resto = actual.toString().trim();
    if (resto.isNotEmpty) sentencias.add(resto);

    return sentencias;
  }

  /// Quita el comentario `--` del final de una línea de SQL.
  ///
  /// POR QUÉ NO BASTA CON `linea.split('--').first`:
  /// un `--` puede aparecer DENTRO de una cadena de texto, y ahí no es un
  /// comentario sino parte del dato. Por ejemplo:
  ///     SELECT RAISE(ABORT, 'formato -- invalido');
  /// Cortar en el primer `--` dejaría una comilla sin cerrar y rompería la
  /// sentencia. Por eso se recorre carácter por carácter llevando la cuenta
  /// de si estamos dentro de comillas o fuera.
  String _quitarComentario(String linea) {
    var enComillas = false;

    // Se recorre hasta length - 1 porque en cada paso se miran DOS caracteres
    // (el actual y el siguiente) para detectar la secuencia '--'.
    for (var i = 0; i < linea.length - 1; i++) {
      final c = linea[i];

      // Comilla simple: entra o sale de una cadena de texto.
      //
      // SQL escapa las comillas duplicándolas ('') en vez de con barra
      // invertida. Este alternar maneja ese caso solo: '' se lee como dos
      // cambios seguidos, que deja el estado igual que al principio.
      if (c == "'") {
        enComillas = !enComillas;
        continue;
      }

      // Dos guiones seguidos FUERA de comillas: empieza el comentario.
      // Se devuelve todo lo anterior y se descarta el resto de la línea.
      if (!enComillas && c == '-' && linea[i + 1] == '-') {
        return linea.substring(0, i);
      }
    }

    // No había comentario: la línea entera es código.
    return linea;
  }

  /// Cierra la conexión. Se usa sobre todo en pruebas, para que cada prueba
  /// arranque con una base limpia. En uso normal la app no la cierra nunca.
  Future<void> cerrar() async {
    await _db?.close();
    _db = null;
  }
}
