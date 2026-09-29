// =============================================================================
//  tratamiento.dart
//  Modelo de la tabla `tratamiento`.
//
//  POR QUE ES UNA TABLA SEPARADA DE evento_salud:
//  un episodio puede llevar varias aplicaciones en dias distintos. Meterlo en
//  la misma fila obligaria a inventar columnas farmaco_1, farmaco_2, farmaco_3.
//
//  POR QUE IMPORTA PARA EL ALGORITMO:
//  el tratamiento ALTERA la senial. Un antiinflamatorio sube la rumia por
//  razones farmacologicas, no porque el animal se haya curado. Para interpretar
//  bien la serie del acelerometro hay que saber cuando se aplico que cosa.
//
//  POR QUE IMPORTA PARA JHON, HOY:
//  el retiro de leche. Es la unica funcion de la Fase 1 con valor practico
//  inmediato y la que hace que valga la pena abrir la app aunque el collar
//  todavia no exista.
// =============================================================================

import '../../core/fechas.dart';

/// Vias de administracion.
class ViaAdministracion {
  static const intramuscular = 'IM';
  static const intravenosa   = 'IV';
  static const subcutanea    = 'SC';
  static const oral          = 'ORAL';
  static const intramamaria  = 'INTRAMAMARIA';
  static const topica        = 'TOPICA';

  static const todas = [
    intramuscular, intravenosa, subcutanea, oral, intramamaria, topica,
  ];

  static String nombre(String via) {
    switch (via) {
      case intramuscular: return 'Intramuscular';
      case intravenosa:   return 'Intravenosa';
      case subcutanea:    return 'Subcutánea';
      case oral:          return 'Oral';
      case intramamaria:  return 'Intramamaria';
      case topica:        return 'Tópica';
      default:            return via;
    }
  }
}

class Tratamiento {
  final String id;
  final String eventoSaludId;
  final DateTime tsAplicacion;

  final String farmaco;           // Nombre comercial, como lo dice el frasco
  final String? principioActivo;  // Normalizado: el comercial cambia de marca
  final double? dosis;
  final String? unidadDosis;      // 'ml', 'mg', 'g', 'UI'
  final String? via;

  /// Dias que debe retirarse la leche tras la aplicacion.
  /// Es el dato que alimenta la alerta.
  final int? diasRetiroLeche;
  final int? diasRetiroCarne;

  final String? aplicadoPor;
  final DateTime creadoEn;

  const Tratamiento({
    required this.id,
    required this.eventoSaludId,
    required this.tsAplicacion,
    required this.farmaco,
    this.principioActivo,
    this.dosis,
    this.unidadDosis,
    this.via,
    this.diasRetiroLeche,
    this.diasRetiroCarne,
    this.aplicadoPor,
    required this.creadoEn,
  });

  factory Tratamiento.desdeFila(Map<String, Object?> f) {
    return Tratamiento(
      id:              f['id'] as String,
      eventoSaludId:   f['evento_salud_id'] as String,
      tsAplicacion:    desdeIso(f['ts_aplicacion'] as String)!,
      farmaco:         f['farmaco'] as String,
      principioActivo: f['principio_activo'] as String?,

      // La columna es REAL. Un valor entero guardado ahi puede llegar como
      // int, asi que `as num?` acepta ambos y toDouble() normaliza.
      dosis:           (f['dosis'] as num?)?.toDouble(),

      unidadDosis:     f['unidad_dosis'] as String?,
      via:             f['via'] as String?,
      diasRetiroLeche: f['dias_retiro_leche'] as int?,
      diasRetiroCarne: f['dias_retiro_carne'] as int?,
      aplicadoPor:     f['aplicado_por'] as String?,
      creadoEn:        desdeIso(f['creado_en'] as String)!,
    );
  }

  Map<String, Object?> aFila() => {
        'id':                id,
        'evento_salud_id':   eventoSaludId,

        // Hora completa: si se aplica a las 6 de la manana o a las 6 de la
        // tarde cambia el ordenio a partir del cual empieza el retiro.
        'ts_aplicacion':     aIso(tsAplicacion),

        'farmaco':           farmaco,
        'principio_activo':  principioActivo,
        'dosis':             dosis,
        'unidad_dosis':      unidadDosis,
        'via':               via,
        'dias_retiro_leche': diasRetiroLeche,
        'dias_retiro_carne': diasRetiroCarne,
        'aplicado_por':      aplicadoPor,
        'creado_en':         aIso(creadoEn),
      };

  /// Fecha hasta la cual NO se puede entregar la leche.
  /// Devuelve null si el farmaco no tiene periodo de retiro.
  DateTime? get retiroLecheHasta {
    if (diasRetiroLeche == null) return null;

    // Duration(days:) suma dias calendario reales. Sumar milisegundos a mano
    // fallaria en cambios de horario; Ecuador no los tiene, pero la forma
    // correcta cuesta lo mismo.
    return tsAplicacion.add(Duration(days: diasRetiroLeche!));
  }

  DateTime? get retiroCarneHasta {
    if (diasRetiroCarne == null) return null;
    return tsAplicacion.add(Duration(days: diasRetiroCarne!));
  }

  /// Si la leche de este animal sigue en periodo de retiro ahora mismo.
  bool get enRetiroLeche {
    final hasta = retiroLecheHasta;
    if (hasta == null) return false;

    // isAfter compara instantes completos, no solo la fecha.
    return hasta.isAfter(DateTime.now());
  }

  /// Dias que faltan para poder entregar la leche. 0 si ya se puede.
  int get diasRestantesRetiro {
    final hasta = retiroLecheHasta;
    if (hasta == null) return 0;

    // Dias de calendario, no bloques de 24 h: ver diasCalendarioHasta.
    // Si el periodo ya paso devuelve 0, nunca "faltan -3 dias".
    return diasCalendarioHasta(hasta);
  }
}
