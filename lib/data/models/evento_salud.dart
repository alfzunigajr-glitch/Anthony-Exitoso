// =============================================================================
//  evento_salud.dart
//  Modelo de la tabla `evento_salud`. Es el objeto más importante de la app:
//  cada instancia es, potencialmente, una etiqueta de entrenamiento.
// =============================================================================

import '../../core/fechas.dart';

/// Cuán confiable es `tsInicioEstimado`.
///
/// POR QUÉ ESTO EXISTE:
/// nadie sabe la hora exacta en que empezó una mastitis. Si la app obligara a
/// poner una hora precisa, el usuario inventaría una y el modelo se entrenaría
/// con ruido disfrazado de dato. Este campo permite ser honesto y luego filtrar
/// por calidad.
class PrecisionTs {
  static const exacto      = 'EXACTO';
  static const masMenos6h  = 'MAS_MENOS_6H';
  static const masMenos1d  = 'MAS_MENOS_1D';
  static const masMenos3d  = 'MAS_MENOS_3D';
  static const desconocido = 'DESCONOCIDO';

  static const todas = [exacto, masMenos6h, masMenos1d, masMenos3d, desconocido];

  /// Precisiones aceptadas para entrenar. Debe coincidir EXACTAMENTE con el
  /// filtro de la vista v_etiquetas_entrenamiento en el archivo .sql.
  /// Si un día cambia una, hay que cambiar la otra.
  static const utilesParaEntrenar = [exacto, masMenos6h, masMenos1d];

  /// Texto para mostrar en el desplegable de la app.
  static String etiqueta(String valor) {
    switch (valor) {
      case exacto:      return 'Hora exacta';
      case masMenos6h:  return 'Aproximado (± 6 horas)';
      case masMenos1d:  return 'Aproximado (± 1 día)';
      case masMenos3d:  return 'Aproximado (± 3 días)';
      default:          return 'No lo sé';
    }
  }
}

/// Cómo se llegó al diagnóstico. Determina si el evento sirve para medir
/// desempeño o solo para explorar.
class MetodoDiagnostico {
  static const clinico     = 'CLINICO';
  static const laboratorio = 'LABORATORIO';
  static const necropsia   = 'NECROPSIA';
  static const presuntivo  = 'PRESUNTIVO';

  static const todos = [clinico, laboratorio, necropsia, presuntivo];
}

class EventoSalud {
  final String id;
  final String animalId;

  /// Código del catálogo. La clave foránea garantiza que solo pueden usarse
  /// códigos existentes. Como 'ABORTO' NO está en el catálogo, es imposible
  /// registrar un aborto por esta vía: va en `evento_reproductivo` y solo ahí.
  final String diagnosticoCodigo;

  // ---- LOS TRES TIEMPOS ----------------------------------------------------

  /// (1) Cuándo empezó de verdad. Es la etiqueta: el instante alrededor del
  /// cual se buscará la anomalía en la señal del acelerómetro.
  /// Nullable porque a veces sencillamente no se sabe.
  final DateTime? tsInicioEstimado;

  /// (2) Cuándo alguien lo notó a simple vista.
  /// ESTA ES LA MARCA QUE EL ALGORITMO DEBE VENCER. Sin este dato no se puede
  /// demostrar que el collar se adelanta al ojo humano, que es toda la
  /// propuesta de valor del proyecto. Por eso es obligatorio.
  final DateTime tsDeteccionHumana;

  /// (3) Cuándo se digitó en la app. Lo pone la app sola, el usuario no lo ve.
  /// Sirve para medir el retraso de digitación: si un evento se registra cinco
  /// días tarde, su tsInicioEstimado es mucho menos confiable.
  final DateTime tsRegistro;

  final String precisionTsInicio;

  // ---- Calidad del diagnóstico ---------------------------------------------
  final String metodoDiagnostico;
  final bool confirmado;         // Solo true si lo confirmó el veterinario
  final String? confirmadoPor;
  final int? severidad;          // 1 leve, 2 moderado, 3 grave

  // ---- Cierre del episodio -------------------------------------------------
  final DateTime? tsResolucion;
  final String? desenlace;       // 'RECUPERADO','CRONICO','DESCARTE','MUERTE'

  final String? notas;
  final String? fotoRuta;
  final String? creadoPor;
  final DateTime modificadoEn;

  const EventoSalud({
    required this.id,
    required this.animalId,
    required this.diagnosticoCodigo,
    this.tsInicioEstimado,
    required this.tsDeteccionHumana,
    required this.tsRegistro,
    this.precisionTsInicio = PrecisionTs.desconocido,
    required this.metodoDiagnostico,
    this.confirmado = false,
    this.confirmadoPor,
    this.severidad,
    this.tsResolucion,
    this.desenlace,
    this.notas,
    this.fotoRuta,
    this.creadoPor,
    required this.modificadoEn,
  });

  factory EventoSalud.desdeFila(Map<String, Object?> f) {
    return EventoSalud(
      id:                f['id'] as String,
      animalId:          f['animal_id'] as String,
      diagnosticoCodigo: f['diagnostico_codigo'] as String,
      tsInicioEstimado:  desdeIso(f['ts_inicio_estimado'] as String?),

      // Estas dos son NOT NULL en el esquema, de ahí el `!`.
      tsDeteccionHumana: desdeIso(f['ts_deteccion_humana'] as String)!,
      tsRegistro:        desdeIso(f['ts_registro'] as String)!,

      precisionTsInicio: f['precision_ts_inicio'] as String? ?? PrecisionTs.desconocido,
      metodoDiagnostico: f['metodo_diagnostico'] as String,
      confirmado:        (f['confirmado'] as int? ?? 0) == 1,
      confirmadoPor:     f['confirmado_por'] as String?,
      severidad:         f['severidad'] as int?,
      tsResolucion:      desdeIso(f['ts_resolucion'] as String?),
      desenlace:         f['desenlace'] as String?,
      notas:             f['notas'] as String?,
      fotoRuta:          f['foto_ruta'] as String?,
      creadoPor:         f['creado_por'] as String?,
      modificadoEn:      desdeIso(f['modificado_en'] as String)!,
    );
  }

  Map<String, Object?> aFila() {
    return {
      'id':                 id,
      'animal_id':          animalId,
      'diagnostico_codigo': diagnosticoCodigo,

      // Los tres timestamps van con hora completa y offset. Aquí sí importa la
      // hora: la ventana de análisis del acelerómetro es de 24 a 48 horas, así
      // que una diferencia de seis horas cambia por completo el tramo de señal
      // que se va a examinar.
      'ts_inicio_estimado':  tsInicioEstimado == null ? null : aIso(tsInicioEstimado!),
      'ts_deteccion_humana': aIso(tsDeteccionHumana),
      'ts_registro':         aIso(tsRegistro),

      'precision_ts_inicio': precisionTsInicio,
      'metodo_diagnostico':  metodoDiagnostico,
      'confirmado':          confirmado ? 1 : 0,
      'confirmado_por':      confirmadoPor,
      'severidad':           severidad,
      'ts_resolucion':       tsResolucion == null ? null : aIso(tsResolucion!),
      'desenlace':           desenlace,
      'notas':               notas,
      'foto_ruta':           fotoRuta,
      'creado_por':          creadoPor,
      'modificado_en':       aIso(modificadoEn),
    };
  }

  /// Horas que tardó el ojo humano en notar el evento desde su inicio estimado.
  ///
  /// Es la métrica contra la que se compara el algoritmo: si el collar avisa
  /// antes de este número de horas, hay producto. Devuelve null si no se
  /// conoce el inicio.
  double? get horasHastaDeteccionVisual {
    if (tsInicioEstimado == null) return null;

    // difference() da un Duration; inMinutes es más preciso que inHours porque
    // este último trunca (2 horas 50 minutos daría 2).
    final minutos = tsDeteccionHumana.difference(tsInicioEstimado!).inMinutes;

    // 60.0 con decimal fuerza división en punto flotante. Con 60 entero, Dart
    // haría división entera y perdería los minutos.
    return minutos / 60.0;
  }

  /// Si este evento entra en el conjunto de entrenamiento.
  ///
  /// Replica exactamente el filtro de v_etiquetas_entrenamiento del .sql.
  /// Se duplica a propósito para poder mostrar en la app, evento por evento,
  /// si cuenta o no. Ver un contador de "eventos que sí sirven" subiendo es
  /// el mejor incentivo posible para que Jhon registre bien.
  bool get sirveParaEntrenar {
    return confirmado
        && tsInicioEstimado != null
        && PrecisionTs.utilesParaEntrenar.contains(precisionTsInicio);
  }

  /// Explica por qué un evento no sirve todavía, para mostrarlo en pantalla.
  /// Devuelve null si sí sirve.
  String? get motivoNoSirve {
    if (!confirmado)              return 'Falta confirmación del veterinario';
    if (tsInicioEstimado == null) return 'Falta la fecha estimada de inicio';
    if (!PrecisionTs.utilesParaEntrenar.contains(precisionTsInicio)) {
      return 'La fecha de inicio es demasiado imprecisa';
    }
    return null;
  }
}
