// =============================================================================
//  pantallas_test.dart
//  Pruebas de las pantallas del hato (T1 y T2).
//
//  Prueban lo que la persona ve y toca, contra una base real en memoria.
//
//  POR QUE runAsync: las pruebas de pantalla corren con un reloj falso que
//  solo avanza con pump(). La base de datos, en cambio, trabaja con tiempo
//  real. runAsync deja correr el tiempo real mientras la base responde; sin
//  eso la consulta nunca termina y la prueba se queda colgada.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_ganado/core/tema.dart';
import 'package:app_ganado/data/dao/animal_dao.dart';
import 'package:app_ganado/data/models/animal.dart';
import 'package:app_ganado/data/models/finca.dart';
import 'package:app_ganado/ui/pantalla_animal_nuevo.dart';
import 'package:app_ganado/ui/pantalla_hato.dart';

import 'ayuda_pruebas.dart';

void main() {
  prepararEntorno();

  late Finca finca;

  setUp(() async {
    await baseLimpia();
    finca = await FincaDao().crear(nombre: 'Finca de prueba');
  });

  tearDown(cerrarBase);

  /// Pantalla del tamanio de un telefono comun, para que los botones de abajo
  /// y las opciones queden a la vista como en el aparato real.
  void tamanioTelefono(WidgetTester tester) {
    tester.view.physicalSize = const Size(412 * 3, 915 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Toca y deja que la base termine de responder antes de redibujar.
  Future<void> tocar(WidgetTester tester, Finder objetivo) async {
    await tester.ensureVisible(objetivo);
    await tester.runAsync(() async {
      await tester.tap(objetivo);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  Future<void> abrir(WidgetTester tester, Widget pantalla) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(theme: construirTema(), home: pantalla));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  group('Alta de animal', () {
    testWidgets('guarda con los cuatro datos obligatorios y deja cargar otro',
        (tester) async {
      tamanioTelefono(tester);
      await abrir(tester, PantallaAnimalNuevo(fincaId: finca.id));

      final guardarOtro = find.text('Guardar y agregar otro');

      // Sin datos el boton esta deshabilitado.
      expect(
        tester.widget<ElevatedButton>(
          find.ancestor(of: guardarOtro, matching: find.byType(ElevatedButton)),
        ).onPressed,
        isNull,
      );

      // Minusculas a proposito: debe guardarse normalizado como V-18.
      await tester.enterText(find.byType(TextField).first, 'v-18');
      await tocar(tester, find.text('Hembra'));
      await tocar(tester, find.text('Vaca en ordeño'));
      await tocar(tester, guardarOtro);

      final hato = await tester.runAsync(
          () => AnimalDao().listarActivos(finca.id));
      expect(hato, hasLength(1));
      expect(hato!.first.areteInterno, equals('V-18'));
      expect(hato.first.categoria, equals(CategoriaAnimal.vacaLactancia));

      // Para el siguiente animal: arete vacio, categoria conservada.
      expect(find.text('V-18'), findsNothing);
      final opcion = tester.widget<Text>(find.text('Vaca en ordeño'));
      expect(opcion.style?.color, equals(Colors.white));
    });

    testWidgets('un arete repetido se explica junto al campo',
        (tester) async {
      await tester.runAsync(() => AnimalDao().crear(
            fincaId: finca.id,
            sexo: Sexo.hembra,
            categoria: CategoriaAnimal.vacaSeca,
            fechaIngreso: DateTime(2026, 1, 1),
            areteInterno: 'V-18',
          ));

      tamanioTelefono(tester);
      await abrir(tester, PantallaAnimalNuevo(fincaId: finca.id));

      await tester.enterText(find.byType(TextField).first, 'V-18');
      await tocar(tester, find.text('Hembra'));
      await tocar(tester, find.text('Vaca seca'));
      await tocar(tester, find.text('Guardar y agregar otro'));

      expect(
        find.text('Ya hay un animal con el arete V-18 en esta finca.'),
        findsOneWidget,
      );
      // Y no se guardo un segundo animal.
      final hato = await tester.runAsync(
          () => AnimalDao().listarActivos(finca.id));
      expect(hato, hasLength(1));
    });

    testWidgets('un macho no puede elegir categorias de hembra',
        (tester) async {
      tamanioTelefono(tester);
      await abrir(tester, PantallaAnimalNuevo(fincaId: finca.id));

      await tocar(tester, find.text('Macho'));

      expect(find.text('Toro'), findsOneWidget);
      expect(find.text('Vaca en ordeño'), findsNothing);
    });
  });

  group('Hato', () {
    testWidgets('vacio: invita a agregar el primer animal', (tester) async {
      tamanioTelefono(tester);
      await abrir(tester, PantallaHato(fincaId: finca.id));

      expect(find.text('Todavía no hay animales'), findsOneWidget);
      expect(find.text('Agregar el primer animal'), findsOneWidget);
    });

    testWidgets('con animales: lista y busca', (tester) async {
      final dao = AnimalDao();
      await tester.runAsync(() async {
        await dao.crear(
          fincaId: finca.id,
          sexo: Sexo.hembra,
          categoria: CategoriaAnimal.vacaLactancia,
          fechaIngreso: DateTime(2026, 1, 1),
          areteInterno: 'V-18',
          nombre: 'Lucera',
        );
        await dao.crear(
          fincaId: finca.id,
          sexo: Sexo.hembra,
          categoria: CategoriaAnimal.vacona,
          fechaIngreso: DateTime(2026, 1, 1),
          areteInterno: 'T-04',
        );
      });

      tamanioTelefono(tester);
      await abrir(tester, PantallaHato(fincaId: finca.id));

      expect(find.text('Hato · 2'), findsOneWidget);
      expect(find.text('Lucera'), findsOneWidget);
      expect(find.text('T-04'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.enterText(find.byType(TextField), 'luc');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(find.text('Lucera'), findsOneWidget);
      expect(find.text('T-04'), findsNothing);
    });
  });
}
