// =============================================================================
//  esquema_test.dart
//  Pruebas de la base: que las migraciones corran, que las restricciones
//  bloqueen lo que deben, y que la duplicacion sea imposible.
//
//  Cada prueba de aqui corresponde a una decision de disenio del archivo .sql.
//  Si alguna falla, el dataset de la Fase 3 queda comprometido.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:app_ganado/core/fechas.dart';
import 'package:app_ganado/data/db/app_database.dart';

import 'ayuda_pruebas.dart';

void main() {
  prepararEntorno();

  setUp(baseLimpia);
  tearDown(cerrarBase);

  group('migraciones', () {
    test('crea todas las tablas, vistas y triggers', () async {
      final db = await AppDatabase.instancia.db;

      // sqlite_master es el catalogo interno de SQLite: guarda la definicion
      // de todo objeto de la base. Consultarlo es la forma de comprobar que
      // el esquema quedo completo.
      Future<int> contar(String tipo) async {
        final r = await db.rawQuery(
          "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = ?", [tipo]);
        return Sqflite.firstIntValue(r) ?? 0;
      }

      expect(await contar('table'), greaterThanOrEqualTo(11));

      // 5 vistas: v_hato_activo, v_posibles_duplicados, v_etiquetas,
      // v_etiquetas_entrenamiento y v_conteo_eventos.
      expect(await contar('view'), equals(5));

      // 2 triggers anti-solape (INSERT y UPDATE). Si sale 0, el partidor de
      // sentencias rompio los triggers al cortar por el ';' de su interior.
      expect(await contar('trigger'), equals(2),
          reason: 'Los triggers no sobrevivieron al partidor de sentencias');
    });

    test('las claves foraneas estan activas', () async {
      final db = await AppDatabase.instancia.db;
      final r = await db.rawQuery('PRAGMA foreign_keys');

      // Si esto devuelve 0, TODA la proteccion contra duplicacion deja de
      // funcionar en silencio. sqflite las trae desactivadas por defecto y hay
      // que encenderlas en onConfigure, en cada apertura.
      expect(Sqflite.firstIntValue(r), equals(1),
          reason: 'Sin claves foraneas, se podria registrar ABORTO como salud');
    });

    test('el catalogo trae los 15 diagnosticos', () async {
      final db = await AppDatabase.instancia.db;
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM catalogo_diagnostico');

      // 14 del esquema v1 mas PROL_CERV del parche v1.1.
      expect(Sqflite.firstIntValue(r), equals(15));
    });

    test('PROL_CERV existe y ABORTO no', () async {
      final db = await AppDatabase.instancia.db;

      final prol = await db.query('catalogo_diagnostico',
          where: 'codigo = ?', whereArgs: ['PROL_CERV']);
      expect(prol, hasLength(1));

      // La AUSENCIA de ABORTO no es un olvido: es el mecanismo que impide
      // registrarlo dos veces. Sin fila en el catalogo, la clave foranea de
      // evento_salud lo rechaza.
      final aborto = await db.query('catalogo_diagnostico',
          where: 'codigo = ?', whereArgs: ['ABORTO']);
      expect(aborto, isEmpty,
          reason: 'ABORTO debe vivir solo en evento_reproductivo');
    });
  });

  group('proteccion contra duplicacion', () {
    // Ids que reutilizan varias pruebas del grupo.
    late String fincaId;
    late String animalId;

    setUp(() async {
      final db = await AppDatabase.instancia.db;

      fincaId = 'finca-prueba';
      animalId = 'animal-prueba';

      await db.insert('finca', {
        'id': fincaId,
        'nombre': 'Finca de prueba',
        'creado_en': aIso(fechaBase),
      });

      await db.insert('animal', {
        'id': animalId,
        'finca_id': fincaId,
        'arete_interno': 'V-18',
        'sexo': 'H',
        'categoria': 'VACA_LACTANCIA',
        'fecha_ingreso': aFecha(haceDias(400)),
        'creado_en': aIso(fechaBase),
        'modificado_en': aIso(fechaBase),
      });
    });

    test('ABORTO no puede registrarse como evento de salud', () async {
      final db = await AppDatabase.instancia.db;

      // Esta insercion DEBE fallar. Si pasara, el mismo aborto quedaria en dos
      // tablas y todo conteo de etiquetas lo contaria dos veces.
      expect(
        () => db.insert('evento_salud', {
          'id': 'evt-1',
          'animal_id': animalId,
          'diagnostico_codigo': 'ABORTO',
          'ts_deteccion_humana': aIso(haceDias(5)),
          'ts_registro': aIso(haceDias(5)),
          'metodo_diagnostico': 'CLINICO',
          'modificado_en': aIso(fechaBase),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('dos asignaciones solapadas del mismo dispositivo se rechazan', () async {
      final db = await AppDatabase.instancia.db;

      await db.insert('dispositivo', {
        'id': 'disp-1',
        'numero_serie': 'SN-001',
        'fecha_alta': aFecha(haceDias(60)),
        'creado_en': aIso(fechaBase),
      });

      // Primera asignacion: 60 a 10 dias atras.
      await db.insert('asignacion_dispositivo', {
        'id': 'asig-1',
        'dispositivo_id': 'disp-1',
        'animal_id': animalId,
        'ts_colocacion': aIso(haceDias(60)),
        'ts_retiro': aIso(haceDias(10)),
        'creado_en': aIso(fechaBase),
      });

      // Segunda que se cruza con la anterior: el trigger debe abortarla.
      //
      // POR QUE ES CRITICO: la vista de entrenamiento hace LEFT JOIN contra
      // esta tabla. Con dos asignaciones solapadas, cada evento generaria DOS
      // filas y el conteo se inflaria sin que nada avise.
      expect(
        () => db.insert('asignacion_dispositivo', {
          'id': 'asig-2',
          'dispositivo_id': 'disp-1',
          'animal_id': animalId,
          'ts_colocacion': aIso(haceDias(30)),
          'ts_retiro': aIso(haceDias(20)),
          'creado_en': aIso(fechaBase),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('dos asignaciones consecutivas sin cruce si se aceptan', () async {
      final db = await AppDatabase.instancia.db;

      await db.insert('dispositivo', {
        'id': 'disp-2',
        'numero_serie': 'SN-002',
        'fecha_alta': aFecha(haceDias(60)),
        'creado_en': aIso(fechaBase),
      });

      await db.insert('asignacion_dispositivo', {
        'id': 'asig-3',
        'dispositivo_id': 'disp-2',
        'animal_id': animalId,
        'ts_colocacion': aIso(haceDias(60)),
        'ts_retiro': aIso(haceDias(31)),
        'creado_en': aIso(fechaBase),
      });

      // Empieza DESPUES de que termino la anterior: es el caso legitimo de
      // rotar un collar de una vaca a otra. El trigger no debe estorbarlo.
      await db.insert('asignacion_dispositivo', {
        'id': 'asig-4',
        'dispositivo_id': 'disp-2',
        'animal_id': animalId,
        'ts_colocacion': aIso(haceDias(30)),
        'ts_retiro': aIso(haceDias(1)),
        'creado_en': aIso(fechaBase),
      });

      final r = await db.query('asignacion_dispositivo',
          where: 'dispositivo_id = ?', whereArgs: ['disp-2']);
      expect(r, hasLength(2));
    });

    test('el mismo arete no se repite dentro de la finca', () async {
      final db = await AppDatabase.instancia.db;

      // UNIQUE(finca_id, arete_interno). Es el error de digitacion mas comun
      // al dar de alta animales, y debe avisar en vez de guardarse callado.
      expect(
        () => db.insert('animal', {
          'id': 'animal-2',
          'finca_id': fincaId,
          'arete_interno': 'V-18',
          'sexo': 'H',
          'categoria': 'VACA_LACTANCIA',
          'fecha_ingreso': aFecha(haceDias(100)),
          'creado_en': aIso(fechaBase),
          'modificado_en': aIso(fechaBase),
        }),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('v_etiquetas no duplica al combinar salud con reproductivo', () async {
      final db = await AppDatabase.instancia.db;

      // Un evento en cada tabla.
      await db.insert('evento_salud', {
        'id': 'evt-salud',
        'animal_id': animalId,
        'diagnostico_codigo': 'MAST_CLIN',
        'ts_inicio_estimado': aIso(haceDias(8)),
        'ts_deteccion_humana': aIso(haceDias(7)),
        'ts_registro': aIso(haceDias(7)),
        'precision_ts_inicio': 'MAS_MENOS_6H',
        'metodo_diagnostico': 'CLINICO',
        'confirmado': 1,
        'modificado_en': aIso(fechaBase),
      });

      await db.insert('evento_reproductivo', {
        'id': 'evt-repro',
        'animal_id': animalId,
        'tipo': 'ABORTO',
        'ts_evento': aIso(haceDias(30)),
        'precision_ts': 'MAS_MENOS_1D',
        'creado_en': aIso(fechaBase),
        'modificado_en': aIso(fechaBase),
      });

      // La comprobacion clave: el numero de filas debe ser igual al numero de
      // etiquetas distintas. Si difieren, el UNION ALL esta duplicando.
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS filas, COUNT(DISTINCT etiqueta_id) AS distintas '
        'FROM v_etiquetas',
      );

      expect(r.first['filas'], equals(r.first['distintas']));
      expect(r.first['filas'], equals(2));
    });

    test('SERVICIO y PALPACION no entran como etiquetas', () async {
      final db = await AppDatabase.instancia.db;

      for (final tipo in ['SERVICIO', 'PALPACION', 'SECADO']) {
        await db.insert('evento_reproductivo', {
          'id': 'evt-$tipo',
          'animal_id': animalId,
          'tipo': tipo,
          'ts_evento': aIso(haceDias(20)),
          'precision_ts': 'EXACTO',
          'creado_en': aIso(fechaBase),
          'modificado_en': aIso(fechaBase),
        });
      }

      // Son datos de manejo, no etiquetas: no producen por si mismos un cambio
      // de comportamiento que el collar deba aprender a reconocer.
      final r = await db.rawQuery('SELECT COUNT(*) AS n FROM v_etiquetas');
      expect(Sqflite.firstIntValue(r), equals(0));
    });
  });
}
