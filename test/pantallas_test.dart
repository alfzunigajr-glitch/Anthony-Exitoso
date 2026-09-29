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
import 'package:app_ganado/data/dao/evento_reproductivo_dao.dart';
import 'package:app_ganado/data/dao/evento_salud_dao.dart';
import 'package:app_ganado/data/dao/produccion_dao.dart';
import 'package:app_ganado/data/dao/tratamiento_dao.dart';
import 'package:app_ganado/data/models/animal.dart';
import 'package:app_ganado/data/models/evento_reproductivo.dart';
import 'package:app_ganado/data/models/evento_salud.dart';
import 'package:app_ganado/data/models/finca.dart';
import 'package:app_ganado/ui/pantalla_animal.dart';
import 'package:app_ganado/ui/pantalla_animal_nuevo.dart';
import 'package:app_ganado/ui/pantalla_completar_evento.dart';
import 'package:app_ganado/ui/pantalla_hato.dart';
import 'package:app_ganado/ui/pantalla_produccion.dart';
import 'package:app_ganado/ui/pantalla_repro.dart';
import 'package:app_ganado/ui/pantalla_tratamiento.dart';

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

  // ===========================================================================
  //  T3 a T8
  // ===========================================================================

  /// Vaca en ordenio con un caso de mastitis sin completar.
  Future<(Animal, EventoSalud)> vacaConCaso(WidgetTester tester) async {
    final r = await tester.runAsync(() async {
      final vaca = await AnimalDao().crear(
        fincaId: finca.id,
        sexo: Sexo.hembra,
        categoria: CategoriaAnimal.vacaLactancia,
        fechaIngreso: DateTime(2025, 1, 1),
        areteInterno: 'V-12',
        nombre: 'Canela',
      );
      final caso = await EventoSaludDao().crear(
        animalId: vaca.id,
        diagnosticoCodigo: 'MAST_CLIN',
        tsDeteccionHumana: DateTime.now().subtract(const Duration(hours: 3)),
        metodoDiagnostico: MetodoDiagnostico.presuntivo,
      );
      return (vaca, caso);
    });
    return r!;
  }

  group('Tratamiento', () {
    testWidgets('con retiro de leche avisa hasta cuándo y lo guarda',
        (tester) async {
      tamanioTelefono(tester);
      final (vaca, caso) = await vacaConCaso(tester);

      await abrir(
        tester,
        PantallaTratamiento(
          fincaId: finca.id,
          eventoSaludId: caso.id,
          titulo: 'Mastitis · V-12',
        ),
      );

      await tester.enterText(find.byType(TextField).first, 'Mastijet');
      await tester.pump();

      // Cuatro toques al "+" de los dias de leche (el primero de la pantalla).
      final mas = find.byIcon(Icons.add).first;
      for (var i = 0; i < 4; i++) {
        await tocar(tester, mas);
      }
      expect(find.text('4'), findsOneWidget);

      await tocar(tester, find.text('Guardar tratamiento'));
      await tester.pump();

      expect(find.text('No entregar la leche'), findsOneWidget);

      final retiro = await tester.runAsync(
          () => TratamientoDao().retiroDeAnimal(vaca.id));
      expect(retiro, isNotNull);
      expect(retiro!.farmaco, equals('Mastijet'));
    });
  });

  group('Ordeño', () {
    testWidgets('cuenta las que faltan, acepta coma y marca errores',
        (tester) async {
      tamanioTelefono(tester);
      await tester.runAsync(() async {
        final dao = AnimalDao();
        for (final arete in ['V-01', 'V-02']) {
          await dao.crear(
            fincaId: finca.id,
            sexo: Sexo.hembra,
            categoria: CategoriaAnimal.vacaLactancia,
            fechaIngreso: DateTime(2025, 1, 1),
            areteInterno: arete,
          );
        }
        // Una vacona: no se ordenia, no debe aparecer.
        await dao.crear(
          fincaId: finca.id,
          sexo: Sexo.hembra,
          categoria: CategoriaAnimal.vacona,
          fechaIngreso: DateTime(2025, 1, 1),
          areteInterno: 'T-09',
        );
      });

      await abrir(tester, PantallaProduccion(fincaId: finca.id));

      expect(find.text('Faltan 2 de 2'), findsOneWidget);
      expect(find.text('T-09'), findsNothing);

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), '12,5');
      await tester.pump();
      expect(find.text('Faltan 1 de 2'), findsOneWidget);

      // Un cero de mas: se marca y no deja guardar.
      await tester.enterText(campos.at(1), '100');
      await tester.pump();
      expect(find.text('Revisar'), findsOneWidget);

      await tester.enterText(campos.at(1), '10');
      await tester.pump();
      expect(find.text('Todas anotadas (2)'), findsOneWidget);

      await tocar(tester, find.text('Guardar ordeño (2)'));

      // El ordenio por defecto depende de la hora: se leen los dos.
      final hoy = DateTime.now();
      final anotado = await tester.runAsync(() async => {
            ...await ProduccionDao()
                .delOrdenio(fincaId: finca.id, fecha: hoy, ordenio: 1),
            ...await ProduccionDao()
                .delOrdenio(fincaId: finca.id, fecha: hoy, ordenio: 2),
          });
      expect(anotado!.values.toList()..sort(), equals([10.0, 12.5]));
    });
  });

  group('Completar caso', () {
    testWidgets('con inicio y confirmación pasa a servir', (tester) async {
      tamanioTelefono(tester);
      final (_, caso) = await vacaConCaso(tester);

      await abrir(
        tester,
        PantallaCompletarEvento(evento: caso, titulo: 'Mastitis · V-12'),
      );

      await tocar(tester, find.text('El día anterior'));
      await tocar(tester, find.text('Diagnóstico confirmado'));
      expect(
        find.text('Con esto, el caso sirve para el algoritmo'),
        findsOneWidget,
      );

      await tocar(tester, find.text('Guardar'));

      final guardado =
          await tester.runAsync(() => EventoSaludDao().porId(caso.id));
      expect(guardado!.sirveParaEntrenar, isTrue);
      // El inicio se cuenta desde la deteccion, no desde ahora.
      expect(
        guardado.tsDeteccionHumana.difference(guardado.tsInicioEstimado!),
        equals(const Duration(hours: 24)),
      );
    });
  });

  group('Reproducción', () {
    testWidgets('un parto guarda el evento y pasa la vaca a ordeño',
        (tester) async {
      tamanioTelefono(tester);
      final vaca = (await tester.runAsync(() => AnimalDao().crear(
            fincaId: finca.id,
            sexo: Sexo.hembra,
            categoria: CategoriaAnimal.vacaSeca,
            fechaIngreso: DateTime(2025, 1, 1),
            areteInterno: 'V-33',
          )))!;

      await abrir(tester, PantallaRepro(animal: vaca));

      await tocar(tester, find.text('Parto'));
      await tocar(tester, find.text('Ayer'));
      await tocar(tester, find.text('Sin ayuda'));
      await tocar(tester, find.text('Guardar'));

      final eventos = await tester.runAsync(
          () => EventoReproductivoDao().porAnimal(vaca.id));
      expect(eventos, hasLength(1));
      expect(eventos!.first.tipo, equals(TipoRepro.parto));
      expect(eventos.first.precisionTs, equals(PrecisionTs.masMenos1d));
      expect(eventos.first.dificultadParto, equals(1));

      final despues = await tester.runAsync(() => AnimalDao().porId(vaca.id));
      expect(despues!.categoria, equals(CategoriaAnimal.vacaLactancia));
    });
  });

  group('Ficha', () {
    testWidgets('muestra retiro, casos y lo que falta', (tester) async {
      tamanioTelefono(tester);
      final (vaca, caso) = await vacaConCaso(tester);
      await tester.runAsync(() => TratamientoDao().crear(
            eventoSaludId: caso.id,
            tsAplicacion: DateTime.now().subtract(const Duration(hours: 2)),
            farmaco: 'Mastijet',
            diasRetiroLeche: 4,
          ));

      await abrir(tester, PantallaAnimal(animal: vaca));

      expect(find.text('No entregar su leche'), findsOneWidget);
      expect(find.text('Mastitis clinica'), findsOneWidget);
      expect(find.text('Falta confirmación del veterinario'), findsOneWidget);
      expect(find.text('Completar'), findsOneWidget);
      expect(find.text('Evento reproductivo'), findsOneWidget);
    });
  });
}
