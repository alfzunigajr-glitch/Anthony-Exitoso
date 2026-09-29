// =============================================================================
//  fechas_test.dart
//  Pruebas del helper de fechas.
//
//  POR QUE ESTE ARCHIVO ES DE LOS MAS IMPORTANTES:
//  un error aqui no rompe nada visible. La app funciona, guarda, muestra. Pero
//  las fechas quedan mal y el fallo aparece meses despues, cuando se intenten
//  alinear los eventos contra la senial del acelerometro y no cuadren. Para
//  entonces, seis meses de dataset ya estarian contaminados.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:app_ganado/core/fechas.dart';

void main() {
  group('aIso', () {
    test('incluye el desplazamiento horario', () {
      final f = DateTime(2026, 6, 10, 14, 30, 0);
      final texto = aIso(f);

      // ESTA ES LA PRUEBA CENTRAL DEL ARCHIVO.
      // DateTime.toIso8601String() de Dart devuelve '2026-06-10T14:30:00.000'
      // SIN offset, y ese es exactamente el fallo silencioso que fechas.dart
      // existe para evitar. Un dato sin offset es ambiguo.
      expect(texto.contains('+') || texto.contains('-', 10), isTrue,
          reason: 'La cadena debe llevar el desfase horario');

      // El formato completo: AAAA-MM-DDTHH:MM:SS seguido de +HH:MM o -HH:MM
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$')
            .hasMatch(texto),
        isTrue,
        reason: 'Formato inesperado: $texto',
      );
    });

    test('no agrega milisegundos', () {
      // toIso8601String() los agrega ('.000') y ensucian las comparaciones de
      // texto en SQL, donde las fechas se ordenan como cadenas.
      expect(aIso(DateTime(2026, 6, 10, 14, 30, 0)).contains('.'), isFalse);
    });

    test('rellena con cero a la izquierda', () {
      final texto = aIso(DateTime(2026, 1, 5, 9, 7, 3));

      // Sin padLeft saldria '2026-1-5T9:7:3', que no es ISO-8601 valido y
      // ademas ordena mal como texto: '9' iria despues de '10'.
      expect(texto.startsWith('2026-01-05T09:07:03'), isTrue,
          reason: 'Obtenido: $texto');
    });

    test('convierte UTC a hora local antes de formatear', () {
      final utc = DateTime.utc(2026, 6, 10, 17, 0, 0);
      final texto = aIso(utc);

      // La cadena debe representar la hora de reloj local, no la UTC. Si se
      // guardara en UTC, un ordenio de las 6 de la maniana aparecería como las
      // 11 y al agrupar por dia caeria en el dia equivocado.
      expect(texto.endsWith('Z'), isFalse);
      expect(desdeIso(texto), equals(utc.toLocal()));
    });
  });

  group('aFecha', () {
    test('devuelve solo el dia, sin hora', () {
      expect(aFecha(DateTime(2026, 6, 10, 14, 30)), equals('2026-06-10'));
    });

    test('ordena cronologicamente como texto', () {
      // Es la razon de usar AAAA-MM-DD y no DD/MM/AAAA: SQLite ordena las
      // fechas comparando cadenas, y solo este formato da el orden correcto.
      final fechas = [
        aFecha(DateTime(2026, 12, 1)),
        aFecha(DateTime(2026, 2, 15)),
        aFecha(DateTime(2025, 11, 30)),
      ]..sort();

      expect(fechas, equals(['2025-11-30', '2026-02-15', '2026-12-01']));
    });
  });

  group('desdeIso', () {
    test('devuelve null con texto nulo o vacio', () {
      // Muchas columnas son opcionales (ts_retiro, fecha_nacimiento). Devolver
      // null en vez de lanzar excepcion evita envolver cada lectura en un try.
      expect(desdeIso(null), isNull);
      expect(desdeIso(''), isNull);
    });

    test('ida y vuelta conserva el instante', () {
      final original = DateTime(2026, 6, 10, 14, 30, 45);

      // La prueba mas importante del grupo: lo que se escribe es lo que se lee.
      // Si esto falla, los tres timestamps del evento de salud quedan corridos
      // y el cruce contra la senial del sensor no sirve.
      expect(desdeIso(aIso(original)), equals(original));
    });

    test('devuelve null con texto corrupto en vez de lanzar excepcion', () {
      // Una fila mal escrita no debe tumbar la app entera.
      expect(desdeIso('no es una fecha'), isNull);
    });
  });
}
