// =============================================================================
//  fechas.dart
//  Conversión entre DateTime de Dart y el texto ISO-8601 que guarda SQLite.
//
//  POR QUÉ ESTE ARCHIVO EXISTE:
//  Dart tiene una trampa silenciosa. Esto:
//      DateTime.now().toIso8601String()
//  devuelve '2026-08-13T21:44:00.000' — SIN el desplazamiento horario.
//  El dato queda ambiguo: no se sabe si son las 21:44 de Quito o de Madrid.
//
//  Y si se usa .toUtc() primero, devuelve '...Z', que es correcto pero
//  desplaza la hora 5 horas. Un evento de las 6 de la mañana en el ordeño
//  aparecería como las 11, y al agrupar por día caería en el día equivocado.
//
//  Todo el esquema espera fechas con offset explícito ('-05:00'). Este archivo
//  es el ÚNICO lugar de la app autorizado a construir esas cadenas.
// =============================================================================

/// Convierte un [DateTime] al formato ISO-8601 con offset explícito.
///
/// Ejemplo de salida: `2026-08-13T21:44:07-05:00`
String aIso(DateTime fecha) {
  // Se trabaja siempre sobre la hora local. Si llega un DateTime en UTC se
  // convierte a local primero, para que la cadena represente la hora de reloj
  // que vio la persona en el campo.
  final f = fecha.isUtc ? fecha.toLocal() : fecha;

  // timeZoneOffset devuelve un Duration: la diferencia respecto de UTC.
  // En Ecuador continental es siempre -5 horas (no hay horario de verano).
  final desfase = f.timeZoneOffset;

  // El signo se calcula aparte porque abs() se aplica luego a horas y minutos.
  // isNegative es true para offsets al oeste de Greenwich, que es nuestro caso.
  final signo = desfase.isNegative ? '-' : '+';

  // abs() elimina el signo del Duration para poder formatear los números.
  // inHours da las horas completas: para -5h devuelve -5, y abs() lo deja en 5.
  final horas = desfase.abs().inHours;

  // inMinutes.remainder(60) da los minutos que sobran tras quitar las horas.
  // Importa para zonas con offset fraccionario (India +05:30, Nepal +05:45).
  // Ecuador siempre da 0, pero la fórmula queda correcta para cualquier zona.
  final minutos = desfase.abs().inMinutes.remainder(60);

  // _dosDigitos rellena con cero a la izquierda: 5 -> '05'.
  // Sin eso saldría '-5:0' en vez de '-05:00' y no sería ISO-8601 válido.
  final desfaseTexto = '$signo${_dosDigitos(horas)}:${_dosDigitos(minutos)}';

  // Se arma la parte de fecha y hora manualmente en lugar de usar
  // toIso8601String(), porque ese método agrega milisegundos ('.000') que no
  // aportan nada y ensucian las comparaciones de texto en SQL.
  final y = f.year.toString().padLeft(4, '0');
  final m = _dosDigitos(f.month);
  final d = _dosDigitos(f.day);
  final hh = _dosDigitos(f.hour);
  final mm = _dosDigitos(f.minute);
  final ss = _dosDigitos(f.second);

  return '$y-$m-${d}T$hh:$mm:$ss$desfaseTexto';
}

/// Marca de tiempo del momento actual. Es lo que se usa para `creado_en`,
/// `modificado_en` y `ts_registro`.
String ahora() => aIso(DateTime.now());

/// Convierte solo la fecha, sin hora. Formato `AAAA-MM-DD`.
///
/// Lo usan las columnas que guardan un día completo y no un instante:
/// `produccion_leche.fecha`, `animal.fecha_nacimiento`, `medicion_corporal.fecha`.
/// Mezclar formatos en una misma columna rompe el ordenamiento, así que cada
/// columna usa siempre la misma función.
String aFecha(DateTime fecha) {
  final f = fecha.isUtc ? fecha.toLocal() : fecha;
  return '${f.year.toString().padLeft(4, '0')}'
      '-${_dosDigitos(f.month)}'
      '-${_dosDigitos(f.day)}';
}

/// Lee de vuelta una cadena ISO-8601 de la base de datos a [DateTime].
///
/// Devuelve `null` si el texto es nulo o está vacío, porque muchas columnas
/// son opcionales (`ts_retiro`, `fecha_nacimiento`, `ts_resolucion`).
/// Devolver null en vez de lanzar excepción evita tener que envolver cada
/// lectura en un try/catch.
DateTime? desdeIso(String? texto) {
  if (texto == null || texto.isEmpty) return null;

  // DateTime.tryParse sí entiende el offset al leer (el problema de Dart es
  // solo al escribir). Devuelve null si el texto está corrupto en lugar de
  // lanzar una excepción, que es lo que queremos para no tumbar la app por
  // una fila mal escrita.
  final parseado = DateTime.tryParse(texto);

  // tryParse devuelve el instante en UTC cuando la cadena traía offset.
  // toLocal() lo devuelve a hora de Quito para mostrarlo en pantalla.
  return parseado?.toLocal();
}

/// Días de calendario que faltan hasta [hasta], contando desde hoy.
///
/// Se cuentan fechas, no bloques de 24 horas. `difference().inDays` trunca:
/// un retiro que termina en 1 día y 23 horas daría "1 día", y el ordeñador
/// entregaría leche con antibiótico un día antes. Con fechas de calendario,
/// si termina pasado mañana dice 2, y si termina hoy dice 0 ("hoy").
/// Nunca devuelve negativo.
int diasCalendarioHasta(DateTime hasta, {DateTime? desde}) {
  final a = (desde ?? DateTime.now()).toLocal();
  final b = hasta.toLocal();
  // Se comparan como fechas UTC a medianoche para que un cambio de horario
  // (en otros países) no reste una hora y cambie el resultado.
  final dias = DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
  return dias < 0 ? 0 : dias;
}

/// Rellena un número a dos dígitos: 7 -> '07'.
/// Se marca con guion bajo al inicio para que sea privado del archivo:
/// es un detalle interno y no debe usarse desde otras partes de la app.
String _dosDigitos(int n) => n.toString().padLeft(2, '0');
