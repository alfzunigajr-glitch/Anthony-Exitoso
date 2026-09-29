// =============================================================================
//  animal.dart
//  Modelo de la tabla `animal`.
//
//  QUÉ ES UN MODELO Y POR QUÉ NO SE TRABAJA CON MAPAS SUELTOS:
//  sqflite devuelve cada fila como un Map<String, Object?>. Si la app usara
//  esos mapas directamente, un error de tipeo como fila['arete_intero'] no
//  daría error al compilar: devolvería null y la app mostraría un campo vacío
//  sin explicación. Con una clase, el compilador detecta el error antes de
//  que la app llegue al teléfono.
//
//  Además concentra en un solo lugar la traducción entre los tipos de SQLite
//  (0/1 para booleanos, texto para fechas) y los tipos de Dart (bool, DateTime).
// =============================================================================

import '../../core/fechas.dart';

/// Categorías válidas. Se declaran como constantes en vez de escribir el texto
/// suelto en cada pantalla: así 'VACA_LACTANCIA' se escribe una sola vez y no
/// existe la posibilidad de que en otro archivo alguien ponga 'VACA_LACTANTE'
/// y genere una categoría fantasma que no aparece en ningún filtro.
class CategoriaAnimal {
  static const ternera       = 'TERNERA';
  static const vacona        = 'VACONA';
  static const vaquilla      = 'VAQUILLA';
  static const vacaLactancia = 'VACA_LACTANCIA';
  static const vacaSeca      = 'VACA_SECA';
  static const toro          = 'TORO';
  static const torete        = 'TORETE';

  /// Lista para llenar los desplegables de la interfaz.
  static const todas = [
    ternera, vacona, vaquilla, vacaLactancia, vacaSeca, toro, torete,
  ];
}

class Animal {
  // ---- Identidad -----------------------------------------------------------
  final String id;          // UUID interno. Nunca cambia, ni aunque cambie el arete.
  final String fincaId;

  // ---- Identificadores visibles en campo -----------------------------------
  // Son nullable (String?) porque un ternero recién nacido puede no tener
  // arete oficial todavía. Obligar a llenarlo bloquearía el registro justo
  // en el momento en que más importa registrar.
  final String? areteOficial;
  final String? areteInterno;
  final String? nombre;

  // ---- Datos biológicos ----------------------------------------------------
  final String sexo;                  // 'H' o 'M'
  final DateTime? fechaNacimiento;
  final bool nacimientoEstimado;      // true si la fecha es aproximada.
                                      // La edad es una variable predictora:
                                      // no da lo mismo un dato exacto que uno
                                      // calculado a ojo.
  final String? raza;
  final String? madreId;              // Apunta a otro Animal

  // ---- Estado en el hato ---------------------------------------------------
  final String categoria;
  final DateTime fechaIngreso;
  final bool activo;
  final DateTime? fechaSalida;
  final String? motivoSalida;

  // ---- Auditoría -----------------------------------------------------------
  final DateTime creadoEn;
  final DateTime modificadoEn;
  final String? creadoPor;

  // Todos los campos son `final`: una vez creado, el objeto no se modifica.
  // Para cambiar algo se usa copyWith(), que devuelve una copia nueva.
  // Ventaja: es imposible que una pantalla modifique por accidente un objeto
  // que otra pantalla está mostrando.
  const Animal({
    required this.id,
    required this.fincaId,
    this.areteOficial,
    this.areteInterno,
    this.nombre,
    required this.sexo,
    this.fechaNacimiento,
    this.nacimientoEstimado = false,
    this.raza,
    this.madreId,
    required this.categoria,
    required this.fechaIngreso,
    this.activo = true,
    this.fechaSalida,
    this.motivoSalida,
    required this.creadoEn,
    required this.modificadoEn,
    this.creadoPor,
  });

  /// Construye un Animal a partir de una fila de la base.
  ///
  /// `factory` significa que este constructor puede hacer trabajo antes de
  /// crear el objeto, en vez de solo asignar campos.
  factory Animal.desdeFila(Map<String, Object?> f) {
    return Animal(
      // `as String` afirma el tipo. Si la columna viniera con otro tipo, la
      // app falla aquí y no tres pantallas más adelante con un error confuso.
      id:           f['id'] as String,
      fincaId:      f['finca_id'] as String,
      areteOficial: f['arete_oficial'] as String?,
      areteInterno: f['arete_interno'] as String?,
      nombre:       f['nombre'] as String?,
      sexo:         f['sexo'] as String,

      // desdeIso maneja el null por su cuenta y devuelve null si el texto
      // está vacío, así que no hace falta comprobarlo antes.
      fechaNacimiento: desdeIso(f['fecha_nacimiento'] as String?),

      // SQLite no tiene booleanos: guarda 0 o 1. Esta comparación traduce
      // el entero a bool. El `?? 0` cubre el caso de columna nula.
      nacimientoEstimado: (f['nacimiento_estimado'] as int? ?? 0) == 1,

      raza:      f['raza'] as String?,
      madreId:   f['madre_id'] as String?,
      categoria: f['categoria'] as String,

      // fecha_ingreso es NOT NULL en el esquema, así que desdeIso no puede
      // devolver null. El `!` se lo confirma al compilador.
      fechaIngreso: desdeIso(f['fecha_ingreso'] as String)!,

      activo:       (f['activo'] as int? ?? 1) == 1,
      fechaSalida:  desdeIso(f['fecha_salida'] as String?),
      motivoSalida: f['motivo_salida'] as String?,
      creadoEn:     desdeIso(f['creado_en'] as String)!,
      modificadoEn: desdeIso(f['modificado_en'] as String)!,
      creadoPor:    f['creado_por'] as String?,
    );
  }

  /// Convierte el objeto al mapa que espera sqflite para insertar o actualizar.
  ///
  /// Las claves son los nombres EXACTOS de las columnas. Un error aquí no lo
  /// detecta el compilador, así que es la parte del archivo que conviene
  /// revisar contra el .sql al agregar campos.
  Map<String, Object?> aFila() {
    return {
      'id':            id,
      'finca_id':      fincaId,
      'arete_oficial': areteOficial,
      'arete_interno': areteInterno,
      'nombre':        nombre,
      'sexo':          sexo,

      // Las fechas de nacimiento e ingreso se guardan como día suelto
      // ('AAAA-MM-DD') porque nadie registra la hora exacta de un nacimiento
      // ocurrido en el potrero. El operador `?.` evita llamar aFecha sobre null.
      'fecha_nacimiento': fechaNacimiento == null ? null : aFecha(fechaNacimiento!),

      // El bool vuelve a 0 o 1 para SQLite.
      'nacimiento_estimado': nacimientoEstimado ? 1 : 0,

      'raza':      raza,
      'madre_id':  madreId,
      'categoria': categoria,
      'fecha_ingreso': aFecha(fechaIngreso),
      'activo':        activo ? 1 : 0,
      'fecha_salida':  fechaSalida == null ? null : aFecha(fechaSalida!),
      'motivo_salida': motivoSalida,

      // Estas sí llevan hora completa con offset: son marcas de auditoría y
      // sirven para reconstruir el orden real en que ocurrieron las cosas.
      'creado_en':     aIso(creadoEn),
      'modificado_en': aIso(modificadoEn),
      'creado_por':    creadoPor,

      // 'eliminado' no se incluye a propósito. El borrado lógico lo maneja
      // el DAO con una sentencia UPDATE dedicada. Si estuviera aquí, cualquier
      // guardado normal podría revivir por accidente una fila borrada.
    };
  }

  /// Devuelve una copia con los campos indicados cambiados.
  ///
  /// Como los campos son `final`, esta es la forma de "modificar" un objeto.
  /// El patrón `campo ?? this.campo` significa: si llega un valor nuevo úsalo,
  /// si no, conserva el actual.
  ///
  /// LIMITACIÓN CONOCIDA: con este patrón no se puede poner un campo a null
  /// (pasar null se interpreta como "no cambiar"). Para los pocos casos donde
  /// haga falta borrar un valor, se usa una sentencia UPDATE directa en el DAO.
  Animal copyWith({
    String? areteOficial,
    String? areteInterno,
    String? nombre,
    String? raza,
    String? categoria,
    bool? activo,
    DateTime? fechaSalida,
    String? motivoSalida,
    DateTime? modificadoEn,
  }) {
    return Animal(
      id:                 id,
      fincaId:            fincaId,
      areteOficial:       areteOficial ?? this.areteOficial,
      areteInterno:       areteInterno ?? this.areteInterno,
      nombre:             nombre ?? this.nombre,
      sexo:               sexo,
      fechaNacimiento:    fechaNacimiento,
      nacimientoEstimado: nacimientoEstimado,
      raza:               raza ?? this.raza,
      madreId:            madreId,
      categoria:          categoria ?? this.categoria,
      fechaIngreso:       fechaIngreso,
      activo:             activo ?? this.activo,
      fechaSalida:        fechaSalida ?? this.fechaSalida,
      motivoSalida:       motivoSalida ?? this.motivoSalida,
      creadoEn:           creadoEn,
      // Si no se indica, se pone la hora actual: cualquier cambio actualiza
      // la marca de modificación sin que haya que acordarse de hacerlo.
      modificadoEn:       modificadoEn ?? DateTime.now(),
      creadoPor:          creadoPor,
    );
  }

  /// Etiqueta corta para mostrar en listas.
  /// Prioriza el arete interno porque es lo que el ordeñador usa a diario;
  /// si no hay, cae al nombre y por último a un fragmento del UUID.
  String get etiqueta {
    if (areteInterno != null && areteInterno!.isNotEmpty) {
      return nombre == null ? areteInterno! : '$areteInterno · $nombre';
    }
    if (nombre != null && nombre!.isNotEmpty) return nombre!;
    return id.substring(0, 8);
  }

  /// Edad en días. Devuelve null si no se conoce la fecha de nacimiento.
  int? get edadDias {
    if (fechaNacimiento == null) return null;
    return DateTime.now().difference(fechaNacimiento!).inDays;
  }
}
