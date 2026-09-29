// =============================================================================
//  diagnostico.dart
//  Modelo y DAO de `catalogo_diagnostico`.
//
//  Esta tabla es el vocabulario cerrado de la app. Sin ella, "mastitis",
//  "Mastitis" y "mastits" serían tres clases distintas para el algoritmo y una
//  sola para el humano.
//
//  Es la única tabla que la app casi no escribe y lee todo el tiempo: alimenta
//  el desplegable del formulario de eventos. Por eso lleva caché en memoria.
// =============================================================================

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

/// Sistemas corporales. Sirven para agrupar el desplegable y que el usuario no
/// tenga que recorrer quince opciones sueltas.
class SistemaCorporal {
  static const mamario      = 'MAMARIO';
  static const locomotor    = 'LOCOMOTOR';
  static const respiratorio = 'RESPIRATORIO';
  static const digestivo    = 'DIGESTIVO';
  static const reproductivo = 'REPRODUCTIVO';
  static const metabolico   = 'METABOLICO';
  static const parasitario  = 'PARASITARIO';
  static const otro         = 'OTRO';

  /// Nombre legible para los encabezados de grupo en la interfaz.
  static String etiqueta(String codigo) {
    switch (codigo) {
      case mamario:      return 'Mamario';
      case locomotor:    return 'Locomotor';
      case respiratorio: return 'Respiratorio';
      case digestivo:    return 'Digestivo';
      case reproductivo: return 'Reproductivo';
      case metabolico:   return 'Metabólico';
      case parasitario:  return 'Parasitario';
      default:           return 'Otro';
    }
  }
}

class Diagnostico {
  final String codigo;
  final String nombre;
  final String sistema;

  /// Si esta patología deprime la rumia. Es la señal que el collar pretende
  /// detectar, así que marca qué eventos entran al análisis del algoritmo
  /// de salud y cuáles solo sirven de contexto.
  final bool afectaRumia;

  /// Si altera el patrón de movimiento. La cojera es el caso claro.
  final bool afectaActividad;

  /// 'AGUDO', 'CRONICO' o 'SUBCLINICO'.
  /// Lo subclínico casi nunca tiene un inicio datable, así que como etiqueta
  /// de entrenamiento vale mucho menos que un cuadro agudo.
  final String? curso;

  final bool activo;

  const Diagnostico({
    required this.codigo,
    required this.nombre,
    required this.sistema,
    this.afectaRumia = false,
    this.afectaActividad = false,
    this.curso,
    this.activo = true,
  });

  factory Diagnostico.desdeFila(Map<String, Object?> f) {
    return Diagnostico(
      codigo:          f['codigo'] as String,
      nombre:          f['nombre'] as String,
      sistema:         f['sistema'] as String,
      afectaRumia:     (f['afecta_rumia'] as int? ?? 0) == 1,
      afectaActividad: (f['afecta_actividad'] as int? ?? 0) == 1,
      curso:           f['curso'] as String?,
      activo:          (f['activo'] as int? ?? 1) == 1,
    );
  }

  Map<String, Object?> aFila() => {
        'codigo':           codigo,
        'nombre':           nombre,
        'sistema':          sistema,
        'afecta_rumia':     afectaRumia ? 1 : 0,
        'afecta_actividad': afectaActividad ? 1 : 0,
        'curso':            curso,
        'activo':           activo ? 1 : 0,
      };

  /// Si este diagnóstico es candidato a producir señal medible por el collar.
  /// Se usa en la pantalla de conteo para separar los eventos que le sirven al
  /// algoritmo de los que solo son historial clínico.
  bool get esRelevanteParaSensor => afectaRumia || afectaActividad;
}

class DiagnosticoDao {
  Future<Database> get _db async => AppDatabase.instancia.db;

  /// Caché en memoria del catálogo completo.
  ///
  /// POR QUÉ SE CACHEA ESTA TABLA Y NINGUNA OTRA:
  /// el formulario de registro de eventos consulta el catálogo cada vez que se
  /// abre, y ese formulario es el que Jhon va a usar veinte veces al día junto
  /// a la vaca. Son quince filas que casi nunca cambian; ir al disco cada vez
  /// es trabajo desperdiciado en el momento en que más importa la velocidad.
  ///
  /// `static` para que la caché se comparta entre todas las instancias del DAO.
  static List<Diagnostico>? _cache;

  /// Todos los diagnósticos activos, ordenados por sistema y nombre.
  Future<List<Diagnostico>> listar({bool forzarRecarga = false}) async {
    // Si ya está en memoria y no se pide recarga, se devuelve directo.
    if (_cache != null && !forzarRecarga) return _cache!;

    final db = await _db;

    final filas = await db.query(
      'catalogo_diagnostico',
      where: 'activo = 1',
      // Ordenar por sistema agrupa el desplegable de forma natural: todo lo
      // mamario junto, todo lo locomotor junto.
      orderBy: 'sistema ASC, nombre COLLATE NOCASE ASC',
    );

    _cache = filas.map(Diagnostico.desdeFila).toList();
    return _cache!;
  }

  /// Diagnósticos agrupados por sistema, listo para un desplegable con
  /// encabezados de sección.
  ///
  /// Devuelve un Map donde la clave es el sistema y el valor la lista de
  /// diagnósticos de ese sistema.
  Future<Map<String, List<Diagnostico>>> agrupadosPorSistema() async {
    final todos = await listar();
    final mapa = <String, List<Diagnostico>>{};

    for (final d in todos) {
      // putIfAbsent crea la lista vacía la primera vez que aparece un sistema,
      // y devuelve la existente las siguientes. Evita tener que comprobar
      // si la clave ya existe antes de cada inserción.
      mapa.putIfAbsent(d.sistema, () => []).add(d);
    }

    return mapa;
  }

  /// Busca un diagnóstico por su código.
  Future<Diagnostico?> porCodigo(String codigo) async {
    final todos = await listar();

    // firstWhere lanza excepción si no encuentra nada, así que se usa
    // `where().firstOrNull` a través de un try. La forma más simple y clara
    // en Dart es recorrer con un bucle.
    for (final d in todos) {
      if (d.codigo == codigo) return d;
    }
    return null;
  }

  /// Agrega un diagnóstico nuevo al catálogo.
  ///
  /// CUÁNDO USAR ESTO: solo cuando Jhon detecte que falta una patología que sí
  /// atiende. Agregar códigos después de meses de registro obliga a revisar el
  /// histórico, así que conviene cerrar bien el catálogo antes de arrancar.
  Future<void> agregar(Diagnostico diagnostico) async {
    final db = await _db;

    await db.insert(
      'catalogo_diagnostico',
      diagnostico.aFila(),
      // abort: si el código ya existe, avisa. Reemplazarlo en silencio podría
      // cambiar el significado de eventos ya registrados con ese código.
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    // La caché queda obsoleta: se invalida para que la próxima lectura vaya
    // al disco. Olvidar esta línea haría que el diagnóstico nuevo no apareciera
    // en el desplegable hasta reiniciar la app.
    _cache = null;
  }

  /// Retira un diagnóstico del catálogo sin borrarlo.
  ///
  /// No se usa DELETE: los eventos ya registrados con ese código tienen clave
  /// foránea hacia aquí. Borrarlo rompería el historial. Con activo = 0
  /// desaparece del desplegable pero el historial sigue íntegro.
  Future<void> desactivar(String codigo) async {
    final db = await _db;

    await db.update(
      'catalogo_diagnostico',
      {'activo': 0},
      where: 'codigo = ?',
      whereArgs: [codigo],
    );

    _cache = null;
  }

  /// Vacía la caché a mano. Se usa en las pruebas, donde cada prueba arranca
  /// con una base distinta y la caché de la anterior daría resultados falsos.
  static void limpiarCache() => _cache = null;
}
