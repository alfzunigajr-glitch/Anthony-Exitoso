// =============================================================================
//  evento_reproductivo.dart
//  Modelo de la tabla `evento_reproductivo`.
//
//  Una sola tabla para todo el ciclo, distinguida por el campo `tipo`.
//  Alternativa descartada: una tabla por tipo. Serían cinco tablas casi
//  idénticas y cualquier consulta cronológica necesitaría un UNION de cinco.
//
//  IMPORTANTE: el aborto vive AQUÍ y solo aquí. El código 'ABORTO' no existe
//  en catalogo_diagnostico, así que la clave foránea de evento_salud lo
//  rechaza. Esa omisión es el mecanismo que impide contarlo dos veces.
// =============================================================================

import '../../core/fechas.dart';
import 'evento_salud.dart' show PrecisionTs;

/// Tipos de evento reproductivo.
class TipoRepro {
  static const celo      = 'CELO';
  static const servicio  = 'SERVICIO';
  static const palpacion = 'PALPACION';
  static const parto     = 'PARTO';
  static const aborto    = 'ABORTO';
  static const secado    = 'SECADO';

  static const todos = [celo, servicio, palpacion, parto, aborto, secado];

  /// Tipos que la vista v_etiquetas toma como etiqueta de entrenamiento.
  /// Debe coincidir con el filtro `r.tipo IN (...)` del archivo .sql.
  static const etiquetas = [aborto, parto, celo];

  static String nombre(String tipo) {
    switch (tipo) {
      case celo:      return 'Celo';
      case servicio:  return 'Servicio';
      case palpacion: return 'Palpación';
      case parto:     return 'Parto';
      case aborto:    return 'Aborto';
      case secado:    return 'Secado';
      default:        return tipo;
    }
  }
}

/// Cómo se detectó el celo. Importa mucho más de lo que parece: cuando llegue
/// el collar, esta columna permite comparar la detección visual contra la del
/// sensor sobre el mismo animal y el mismo ciclo.
class MetodoDeteccionCelo {
  static const visual    = 'VISUAL';
  static const monta     = 'MONTA';
  static const parche    = 'PARCHE';
  static const podometro = 'PODOMETRO';
  static const sensor    = 'SENSOR';   // Reservado para la Fase 3

  static const todos = [visual, monta, parche, podometro, sensor];

  /// Los que una persona puede elegir hoy. SENSOR queda fuera: lo escribira
  /// el collar en la Fase 3, nunca una persona.
  static const manuales = [visual, monta, parche, podometro];

  static String nombre(String metodo) {
    switch (metodo) {
      case visual:
        return 'Observación';
      case monta:
        return 'Se deja montar';
      case parche:
        return 'Parche detector';
      case podometro:
        return 'Podómetro';
      case sensor:
        return 'Collar';
      default:
        return metodo;
    }
  }
}

/// Tipo de servicio (columna `servicio_tipo`).
class TipoServicio {
  static const montaNatural = 'MONTA_NATURAL';
  static const ia = 'IA';

  static const todos = [montaNatural, ia];

  static String nombre(String tipo) {
    switch (tipo) {
      case montaNatural:
        return 'Monta natural';
      case ia:
        return 'Inseminación';
      default:
        return tipo;
    }
  }
}

/// Resultado de una palpación.
class ResultadoPalpacion {
  static const preniada = 'PRENIADA';
  static const vacia    = 'VACIA';
  static const dudosa   = 'DUDOSA';

  static const todos = [preniada, vacia, dudosa];

  static String nombre(String resultado) {
    switch (resultado) {
      case preniada:
        return 'Preñada';
      case vacia:
        return 'Vacía';
      case dudosa:
        return 'Dudosa';
      default:
        return resultado;
    }
  }
}

/// Escala de dificultad de parto (columna `dificultad_parto`, 1 a 4).
class DificultadParto {
  static const todas = [1, 2, 3, 4];

  static String nombre(int valor) {
    switch (valor) {
      case 1:
        return 'Sin ayuda';
      case 2:
        return 'Ayuda leve';
      case 3:
        return 'Ayuda fuerte';
      case 4:
        return 'Veterinario';
      default:
        return '$valor';
    }
  }
}

class EventoReproductivo {
  final String id;
  final String animalId;
  final String tipo;
  final DateTime tsEvento;
  final String precisionTs;

  /// Solo para tipo CELO.
  final String? metodoDeteccion;

  /// Solo para tipo PALPACION: 'PRENIADA', 'VACIA' o 'DUDOSA'.
  ///
  /// Un servicio seguido de palpación PRENIADA confirma retroactivamente que
  /// el celo era real. Esa es la única etiqueta de celo verdaderamente
  /// confiable que existe; todo lo demás es apreciación visual.
  final String? resultado;

  /// Solo para tipo SERVICIO.
  final String? servicioTipo;          // 'MONTA_NATURAL' o 'IA'
  final String? identificadorSemen;    // Código de pajuela o del toro
  final int? numeroServicio;           // 1.º, 2.º, 3.º de esta lactancia

  /// Solo para tipo PARTO.
  final int? criasNacidas;
  final int? dificultadParto;          // Escala 1 a 4

  final String? ejecutadoPor;
  final String? notas;
  final DateTime creadoEn;
  final DateTime modificadoEn;

  const EventoReproductivo({
    required this.id,
    required this.animalId,
    required this.tipo,
    required this.tsEvento,
    this.precisionTs = PrecisionTs.desconocido,
    this.metodoDeteccion,
    this.resultado,
    this.servicioTipo,
    this.identificadorSemen,
    this.numeroServicio,
    this.criasNacidas,
    this.dificultadParto,
    this.ejecutadoPor,
    this.notas,
    required this.creadoEn,
    required this.modificadoEn,
  });

  factory EventoReproductivo.desdeFila(Map<String, Object?> f) {
    return EventoReproductivo(
      id:                 f['id'] as String,
      animalId:           f['animal_id'] as String,
      tipo:               f['tipo'] as String,
      tsEvento:           desdeIso(f['ts_evento'] as String)!,
      precisionTs:        f['precision_ts'] as String? ?? PrecisionTs.desconocido,
      metodoDeteccion:    f['metodo_deteccion'] as String?,
      resultado:          f['resultado'] as String?,
      servicioTipo:       f['servicio_tipo'] as String?,
      identificadorSemen: f['identificador_semen'] as String?,
      numeroServicio:     f['numero_servicio'] as int?,
      criasNacidas:       f['crias_nacidas'] as int?,
      dificultadParto:    f['dificultad_parto'] as int?,
      ejecutadoPor:       f['ejecutado_por'] as String?,
      notas:              f['notas'] as String?,
      creadoEn:           desdeIso(f['creado_en'] as String)!,
      modificadoEn:       desdeIso(f['modificado_en'] as String)!,
    );
  }

  Map<String, Object?> aFila() => {
        'id':                  id,
        'animal_id':           animalId,
        'tipo':                tipo,

        // Hora completa con offset. Para el celo importa especialmente: la
        // ventana de inseminación es de horas, no de días, y cuando el collar
        // detecte celo habrá que comparar contra este instante exacto.
        'ts_evento':           aIso(tsEvento),

        'precision_ts':        precisionTs,
        'metodo_deteccion':    metodoDeteccion,
        'resultado':           resultado,
        'servicio_tipo':       servicioTipo,
        'identificador_semen': identificadorSemen,
        'numero_servicio':     numeroServicio,
        'crias_nacidas':       criasNacidas,
        'dificultad_parto':    dificultadParto,
        'ejecutado_por':       ejecutadoPor,
        'notas':               notas,
        'creado_en':           aIso(creadoEn),
        'modificado_en':       aIso(modificadoEn),
      };

  /// Si este evento entra como etiqueta de entrenamiento.
  ///
  /// SERVICIO, PALPACION y SECADO son datos de manejo, no etiquetas: no
  /// producen por sí mismos un cambio de comportamiento que el collar deba
  /// aprender a reconocer.
  bool get esEtiqueta => TipoRepro.etiquetas.contains(tipo);

  /// El parto no es una enfermedad, pero altera el comportamiento de forma
  /// brutal. Hay que conocerlo para EXCLUIR esa ventana del análisis de salud
  /// y no confundir un parto normal con un cuadro clínico.
  bool get esVentanaAExcluir => tipo == TipoRepro.parto;
}
