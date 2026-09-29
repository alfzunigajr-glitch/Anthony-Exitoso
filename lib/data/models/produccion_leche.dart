// =============================================================================
//  produccion_leche.dart
//  Modelo de la tabla `produccion_leche`.
//
//  POR QUE ESTA TABLA VALE TANTO PARA EL PROYECTO:
//  la caida de produccion es un indicador temprano de enfermedad casi tan bueno
//  como la rumia, y es un dato que la finca YA toma todos los dias sin trabajo
//  extra. Es la variable de contraste gratuita: cuando el collar detecte una
//  anomalia, se podra comprobar si la produccion tambien cayo. Dos senales
//  independientes apuntando al mismo dia es mucho mas convincente que una.
//
//  Registro POR ORDENIO, no por dia: la caida suele aparecer primero en un solo
//  ordenio, y promediar el dia la esconderia.
// =============================================================================

import '../../core/fechas.dart';

class ProduccionLeche {
  final String id;
  final String animalId;

  /// Solo la fecha, formato 'AAAA-MM-DD'. Se guarda como DateTime pero al
  /// escribir se recorta con aFecha(): nadie registra el segundo exacto.
  final DateTime fecha;

  /// 1 = manianero, 2 = tarde.
  final int ordenio;

  final double litros;

  /// Hora real del ordenio, si se conoce. Opcional.
  /// Cuando exista el collar servira para alinear el pico de actividad del
  /// traslado al establo con la hora real del ordenio.
  final DateTime? tsOrdenio;

  final DateTime creadoEn;

  const ProduccionLeche({
    required this.id,
    required this.animalId,
    required this.fecha,
    required this.ordenio,
    required this.litros,
    this.tsOrdenio,
    required this.creadoEn,
  });

  factory ProduccionLeche.desdeFila(Map<String, Object?> f) {
    return ProduccionLeche(
      id:        f['id'] as String,
      animalId:  f['animal_id'] as String,
      fecha:     desdeIso(f['fecha'] as String)!,
      ordenio:   f['ordenio'] as int,

      // Columna REAL: puede llegar como int si el valor guardado no tenia
      // decimales. `as num` acepta ambos.
      litros:    (f['litros'] as num).toDouble(),

      tsOrdenio: desdeIso(f['ts_ordenio'] as String?),
      creadoEn:  desdeIso(f['creado_en'] as String)!,
    );
  }

  Map<String, Object?> aFila() => {
        'id':         id,
        'animal_id':  animalId,

        // aFecha y no aIso: esta columna guarda el dia, no el instante.
        // Mezclar formatos en la misma columna rompe el ordenamiento.
        'fecha':      aFecha(fecha),

        'ordenio':    ordenio,
        'litros':     litros,
        'ts_ordenio': tsOrdenio == null ? null : aIso(tsOrdenio!),
        'creado_en':  aIso(creadoEn),
      };
}

/// Resultado de la deteccion de caidas de produccion.
class CaidaProduccion {
  final String animalId;
  final String etiquetaAnimal;
  final DateTime fecha;
  final double litrosHoy;
  final double promedioAnterior;

  /// Cuanto cayo, en porcentaje. 15.0 significa que produjo 15 % menos.
  final double caidaPorcentaje;

  const CaidaProduccion({
    required this.animalId,
    required this.etiquetaAnimal,
    required this.fecha,
    required this.litrosHoy,
    required this.promedioAnterior,
    required this.caidaPorcentaje,
  });
}
