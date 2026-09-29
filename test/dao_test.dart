// =============================================================================
//  dao_test.dart
//  Pruebas de las consultas de los DAOs.
//
//  Se concentran en las cuatro consultas con logica no trivial. El resto de
//  metodos son inserciones y lecturas directas: si el esquema esta bien, no
//  tienen donde fallar.
// =============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:app_ganado/core/fechas.dart';
import 'package:app_ganado/data/dao/animal_dao.dart';
import 'package:app_ganado/data/dao/evento_reproductivo_dao.dart';
import 'package:app_ganado/data/dao/evento_salud_dao.dart';
import 'package:app_ganado/data/dao/produccion_dao.dart';
import 'package:app_ganado/data/dao/tratamiento_dao.dart';
import 'package:app_ganado/data/models/animal.dart';
import 'package:app_ganado/data/models/evento_reproductivo.dart';
import 'package:app_ganado/data/models/evento_salud.dart';
import 'package:app_ganado/data/models/finca.dart';

import 'ayuda_pruebas.dart';

void main() {
  prepararEntorno();

  // `late` promete que la variable se asigna antes de usarse. Permite
  // declararla aqui y llenarla en el setUp sin marcarla como nullable.
  late FincaDao fincaDao;
  late AnimalDao animalDao;
  late EventoSaludDao saludDao;
  late EventoReproductivoDao reproDao;
  late TratamientoDao tratamientoDao;
  late ProduccionDao produccionDao;

  late Finca finca;
  late Animal v18;
  late Animal v22;

  setUp(() async {
    await baseLimpia();

    fincaDao = FincaDao();
    animalDao = AnimalDao();
    saludDao = EventoSaludDao();
    reproDao = EventoReproductivoDao();
    tratamientoDao = TratamientoDao();
    produccionDao = ProduccionDao();

    finca = await fincaDao.crear(nombre: 'Finca de prueba');

    v18 = await animalDao.crear(
      fincaId: finca.id,
      sexo: 'H',
      categoria: CategoriaAnimal.vacaLactancia,
      fechaIngreso: haceDias(400),
      areteInterno: 'V-18',
      nombre: 'Lucera',
    );

    v22 = await animalDao.crear(
      fincaId: finca.id,
      sexo: 'H',
      categoria: CategoriaAnimal.vacaLactancia,
      fechaIngreso: haceDias(380),
      areteInterno: 'V-22',
      nombre: 'Manchada',
    );
  });

  tearDown(cerrarBase);

  // ===========================================================================
  group('AnimalDao', () {
    test('listarActivos devuelve solo los del hato, ordenados', () async {
      final lista = await animalDao.listarActivos(finca.id);

      expect(lista, hasLength(2));
      expect(lista.first.areteInterno, equals('V-18'));
    });

    test('registrarSalida saca del hato sin borrar el historial', () async {
      await animalDao.registrarSalida(
        animalId: v22.id,
        fecha: haceDias(1),
        motivo: 'MUERTE',
      );

      // Ya no aparece en el hato activo...
      expect(await animalDao.listarActivos(finca.id), hasLength(1));

      // ...pero el registro sigue existiendo.
      //
      // POR QUE IMPORTA: un animal que murio de mastitis es de las etiquetas
      // mas valiosas del dataset. Borrarlo seria perder justo el caso mas
      // severo y mas facil de confirmar.
      final recuperado = await animalDao.porId(v22.id);
      expect(recuperado, isNotNull);
      expect(recuperado!.motivoSalida, equals('MUERTE'));
    });

    test('buscar encuentra por arete y por nombre', () async {
      expect(await animalDao.buscar(finca.id, '18'), hasLength(1));
      expect(await animalDao.buscar(finca.id, 'lucera'), hasLength(1));
      expect(await animalDao.buscar(finca.id, 'inexistente'), isEmpty);
    });

    test('crear con un arete repetido lanza AreteRepetido', () async {
      // La pantalla de alta depende de esta excepcion para explicar el error
      // junto al campo. Si llegara la DatabaseException cruda, la app
      // mostraria un error tecnico o se cerraria.
      expect(
        () => animalDao.crear(
          fincaId: finca.id,
          sexo: Sexo.hembra,
          categoria: CategoriaAnimal.vacaSeca,
          fechaIngreso: haceDias(1),
          areteInterno: 'V-18',
        ),
        throwsA(isA<AreteRepetido>()
            .having((e) => e.arete, 'arete', equals('V-18'))),
      );
    });

    test('el mismo arete en otra finca si se acepta', () async {
      final otra = await fincaDao.crear(nombre: 'Otra finca');

      final animal = await animalDao.crear(
        fincaId: otra.id,
        sexo: Sexo.hembra,
        categoria: CategoriaAnimal.vacaSeca,
        fechaIngreso: haceDias(1),
        areteInterno: 'V-18',
      );

      expect(animal.areteInterno, equals('V-18'));
    });
  });

  // ===========================================================================
  group('EventoSaludDao', () {
    test('sirveParaEntrenar exige confirmacion y fecha precisa', () async {
      // Caso completo: confirmado y con precision aceptable.
      final bueno = await saludDao.crear(
        animalId: v18.id,
        diagnosticoCodigo: 'MAST_CLIN',
        tsInicioEstimado: haceDias(8),
        tsDeteccionHumana: haceDias(7),
        precisionTsInicio: PrecisionTs.masMenos6h,
        metodoDiagnostico: MetodoDiagnostico.clinico,
        confirmado: true,
      );
      expect(bueno.sirveParaEntrenar, isTrue);
      expect(bueno.motivoNoSirve, isNull);

      // Sin confirmar: no sirve para medir desempenio.
      final sinConfirmar = await saludDao.crear(
        animalId: v22.id,
        diagnosticoCodigo: 'COJERA',
        tsInicioEstimado: haceDias(5),
        tsDeteccionHumana: haceDias(4),
        precisionTsInicio: PrecisionTs.exacto,
        metodoDiagnostico: MetodoDiagnostico.presuntivo,
      );
      expect(sinConfirmar.sirveParaEntrenar, isFalse);
      expect(sinConfirmar.motivoNoSirve, contains('confirmación'));

      // Fecha demasiado imprecisa: no se puede buscar una anomalia en una
      // ventana de 48 horas si el inicio tiene un margen de 3 dias.
      final impreciso = await saludDao.crear(
        animalId: v22.id,
        diagnosticoCodigo: 'NEUMONIA',
        tsInicioEstimado: haceDias(10),
        tsDeteccionHumana: haceDias(9),
        precisionTsInicio: PrecisionTs.masMenos3d,
        metodoDiagnostico: MetodoDiagnostico.clinico,
        confirmado: true,
      );
      expect(impreciso.sirveParaEntrenar, isFalse);
    });

    test('horasHastaDeteccionVisual mide la marca a vencer', () async {
      final evento = await saludDao.crear(
        animalId: v18.id,
        diagnosticoCodigo: 'MAST_CLIN',
        // Inicio a las 12:00 del dia 8 atras; deteccion 36 horas despues.
        tsInicioEstimado: haceDias(8),
        tsDeteccionHumana: haceDias(8).add(const Duration(hours: 36)),
        precisionTsInicio: PrecisionTs.masMenos6h,
        metodoDiagnostico: MetodoDiagnostico.clinico,
        confirmado: true,
      );

      // ESTE NUMERO ES LA PROPUESTA DE VALOR DEL PROYECTO. Si el collar avisa
      // antes de estas 36 horas, hay producto.
      expect(evento.horasHastaDeteccionVisual, closeTo(36.0, 0.1));
    });

    test('buscarPosiblesDuplicados avisa sin bloquear', () async {
      await saludDao.crear(
        animalId: v18.id,
        diagnosticoCodigo: 'MAST_CLIN',
        tsDeteccionHumana: haceDias(5),
        metodoDiagnostico: MetodoDiagnostico.clinico,
      );

      // Mismo animal, mismo diagnostico, 2 dias despues: sospechoso.
      // Es el caso real de Anthony y Jhon registrando el mismo episodio.
      final sospechosos = await saludDao.buscarPosiblesDuplicados(
        animalId: v18.id,
        diagnosticoCodigo: 'MAST_CLIN',
        fechaDeteccion: haceDias(3),
      );
      expect(sospechosos, hasLength(1));
      expect(sospechosos.first.diasDeDiferencia, closeTo(2.0, 0.1));

      // A 20 dias ya es otro episodio legitimo: no debe avisar.
      final lejano = await saludDao.buscarPosiblesDuplicados(
        animalId: v18.id,
        diagnosticoCodigo: 'MAST_CLIN',
        fechaDeteccion: haceDias(25),
      );
      expect(lejano, isEmpty);
    });

    test('incompletos lista los casos recuperables', () async {
      await saludDao.crear(
        animalId: v18.id,
        diagnosticoCodigo: 'MAST_CLIN',
        tsInicioEstimado: haceDias(8),
        tsDeteccionHumana: haceDias(7),
        precisionTsInicio: PrecisionTs.masMenos6h,
        metodoDiagnostico: MetodoDiagnostico.clinico,
        confirmado: true,
      );

      // Sin fecha de inicio: hoy no sirve, pero con una edicion de treinta
      // segundos si serviria. Recuperar estos casos es de lo mas rentable
      // que puede hacer la app.
      await saludDao.crear(
        animalId: v22.id,
        diagnosticoCodigo: 'COJERA',
        tsDeteccionHumana: haceDias(4),
        metodoDiagnostico: MetodoDiagnostico.clinico,
        confirmado: true,
      );

      final pendientes = await saludDao.incompletos(finca.id);
      expect(pendientes, hasLength(1));
      expect(pendientes.first.animalId, equals(v22.id));
    });

    test('completar lo saca de incompletos sin tocar deteccion ni registro',
        () async {
      final caso = await saludDao.crear(
        animalId: v22.id,
        diagnosticoCodigo: 'COJERA',
        tsDeteccionHumana: haceDias(4),
        metodoDiagnostico: MetodoDiagnostico.presuntivo,
      );

      await saludDao.completar(
        eventoId: caso.id,
        tsInicioEstimado: haceDias(5),
        precisionTsInicio: PrecisionTs.masMenos1d,
        confirmado: true,
        severidad: 2,
      );

      final completo = (await saludDao.porId(caso.id))!;
      expect(completo.sirveParaEntrenar, isTrue);
      expect(completo.metodoDiagnostico, equals(MetodoDiagnostico.clinico));
      expect(await saludDao.incompletos(finca.id), isEmpty);

      // Regla 6 de CLAUDE.md: completar cambia lo que se sabe del inicio, no
      // cuando alguien lo noto ni cuando se digito.
      expect(completo.tsDeteccionHumana, equals(caso.tsDeteccionHumana));
      expect(aIso(completo.tsRegistro), equals(aIso(caso.tsRegistro)));
    });

    test('completar sin confirmar lo deja pendiente y sin gravedad', () async {
      final caso = await saludDao.crear(
        animalId: v22.id,
        diagnosticoCodigo: 'COJERA',
        tsDeteccionHumana: haceDias(4),
        metodoDiagnostico: MetodoDiagnostico.presuntivo,
      );

      await saludDao.completar(
        eventoId: caso.id,
        tsInicioEstimado: haceDias(4),
        precisionTsInicio: PrecisionTs.exacto,
        confirmado: false,
        severidad: 3,
      );

      final sigue = (await saludDao.porId(caso.id))!;
      expect(sigue.sirveParaEntrenar, isFalse);
      expect(sigue.severidad, isNull);
      expect(await saludDao.incompletos(finca.id), hasLength(1));
    });
  });

  // ===========================================================================
  group('TratamientoDao · retiro de leche', () {
    test('manda el farmaco con el periodo mas largo', () async {
      final evento = await saludDao.crear(
        animalId: v18.id,
        diagnosticoCodigo: 'MAST_CLIN',
        tsDeteccionHumana: haceDias(2),
        metodoDiagnostico: MetodoDiagnostico.clinico,
        confirmado: true,
      );

      // Dos farmacos sobre el mismo episodio, con retiros distintos.
      await tratamientoDao.crear(
        eventoSaludId: evento.id,
        tsAplicacion: DateTime.now().subtract(const Duration(days: 2)),
        farmaco: 'Mastijet',
        diasRetiroLeche: 5,
      );
      await tratamientoDao.crear(
        eventoSaludId: evento.id,
        tsAplicacion: DateTime.now().subtract(const Duration(days: 1)),
        farmaco: 'Penicilina',
        diasRetiroLeche: 8,
      );

      final enRetiro = await tratamientoDao.enRetiroLeche(finca.id);

      // Una sola fila por animal, con el retiro que termina mas tarde.
      // Si mostrara el de 5 dias, se entregaria leche con antibiotico y eso
      // le cuesta la entrega completa al ganadero.
      expect(enRetiro, hasLength(1));
      expect(enRetiro.first.farmaco, equals('Penicilina'));
      expect(enRetiro.first.diasRestantes, greaterThan(5));
    });

    test('excluye a los que ya cumplieron el periodo', () async {
      final evento = await saludDao.crear(
        animalId: v22.id,
        diagnosticoCodigo: 'COJERA',
        tsDeteccionHumana: haceDias(20),
        metodoDiagnostico: MetodoDiagnostico.clinico,
      );

      await tratamientoDao.crear(
        eventoSaludId: evento.id,
        tsAplicacion: DateTime.now().subtract(const Duration(days: 20)),
        farmaco: 'Oxitetraciclina',
        diasRetiroLeche: 5,
      );

      // 20 dias transcurridos con retiro de 5: la leche ya se puede entregar.
      expect(await tratamientoDao.enRetiroLeche(finca.id), isEmpty);
    });
  });

  // ===========================================================================
  group('EventoReproductivoDao · confirmacion de celos', () {
    test('confirma el celo que llevo a prenez', () async {
      // Cadena completa: celo -> servicio al dia siguiente -> palpacion
      // prenada 34 dias despues.
      final celo = await reproDao.crear(
        animalId: v18.id,
        tipo: TipoRepro.celo,
        tsEvento: haceDias(60),
        precisionTs: PrecisionTs.exacto,
        metodoDeteccion: MetodoDeteccionCelo.visual,
      );
      await reproDao.crear(
        animalId: v18.id,
        tipo: TipoRepro.servicio,
        tsEvento: haceDias(59),
        servicioTipo: 'IA',
      );
      await reproDao.crear(
        animalId: v18.id,
        tipo: TipoRepro.palpacion,
        tsEvento: haceDias(25),
        resultado: ResultadoPalpacion.preniada,
      );

      // Celo sin servicio posterior: pudo ser un falso positivo del observador.
      await reproDao.crear(
        animalId: v22.id,
        tipo: TipoRepro.celo,
        tsEvento: haceDias(40),
        metodoDeteccion: MetodoDeteccionCelo.visual,
      );

      final confirmados =
          await reproDao.confirmarCelosRetroactivo(fincaId: finca.id);

      // Solo el primero. Es la unica etiqueta de celo con la que se puede
      // medir el algoritmo sin enganiarse.
      expect(confirmados, hasLength(1));
      expect(confirmados.first.celoId, equals(celo.id));
    });

    test('registrarAborto guarda en reproductivo, no en salud', () async {
      await reproDao.registrarAborto(
        animalId: v22.id,
        fecha: haceDias(15),
      );

      final repro = await reproDao.porAnimal(v22.id);
      expect(repro, hasLength(1));
      expect(repro.first.tipo, equals(TipoRepro.aborto));

      // Y no dejo rastro en la tabla de salud: cero riesgo de doble conteo.
      expect(await saludDao.porAnimal(v22.id), isEmpty);
    });

    test('diasEnLeche cuenta desde el ultimo parto', () async {
      await reproDao.crear(
        animalId: v18.id,
        tipo: TipoRepro.parto,
        tsEvento: DateTime.now().subtract(const Duration(days: 45)),
        criasNacidas: 1,
      );

      expect(await reproDao.diasEnLeche(v18.id), equals(45));

      // Nunca pario: null, no cero. Cero significaria "pario hoy".
      expect(await reproDao.diasEnLeche(v22.id), isNull);
    });
  });

  // ===========================================================================
  group('ProduccionDao', () {
    test('guardar corrige sin duplicar la fila', () async {
      final fecha = haceDias(1);

      await produccionDao.guardar(
        animalId: v18.id, fecha: fecha, ordenio: 1, litros: 12.0);

      // Se corrige un numero mal anotado.
      await produccionDao.guardar(
        animalId: v18.id, fecha: fecha, ordenio: 1, litros: 14.5);

      final serie = await produccionDao.porAnimal(v18.id, hoy: fechaBase);

      // Una sola fila con el valor corregido. Con INSERT a secas, la segunda
      // llamada habria fallado por la restriccion UNIQUE y el ordeniador no
      // habria podido corregir su propio error.
      expect(serie, hasLength(1));
      expect(serie.first.litros, equals(14.5));
    });

    test('detectarCaidas compara cada vaca contra si misma', () async {
      // V-18: siete dias a 30 L, ultimo dia 20 L.
      for (var d = 8; d >= 2; d--) {
        await produccionDao.guardar(
          animalId: v18.id, fecha: haceDias(d), ordenio: 1, litros: 15.0);
        await produccionDao.guardar(
          animalId: v18.id, fecha: haceDias(d), ordenio: 2, litros: 15.0);
      }
      await produccionDao.guardar(
        animalId: v18.id, fecha: haceDias(1), ordenio: 1, litros: 10.0);
      await produccionDao.guardar(
        animalId: v18.id, fecha: haceDias(1), ordenio: 2, litros: 10.0);

      // V-22: estable en 20 L. Produce MENOS que V-18 en valor absoluto, pero
      // esta perfectamente sana. Por eso la comparacion es contra el propio
      // animal y no contra el promedio del hato.
      for (var d = 8; d >= 1; d--) {
        await produccionDao.guardar(
          animalId: v22.id, fecha: haceDias(d), ordenio: 1, litros: 10.0);
        await produccionDao.guardar(
          animalId: v22.id, fecha: haceDias(d), ordenio: 2, litros: 10.0);
      }

      final alertas = await produccionDao.detectarCaidas(fincaId: finca.id, hoy: fechaBase);

      expect(alertas, hasLength(1));
      expect(alertas.first.animalId, equals(v18.id));
      expect(alertas.first.caidaPorcentaje, closeTo(33.3, 1.0));
    });

    test('no alerta con menos de 3 dias de historia', () async {
      // Con dos dias de datos, un promedio no significa nada y una alerta
      // seria ruido que enseniaria a ignorar la pantalla.
      await produccionDao.guardar(
        animalId: v18.id, fecha: haceDias(2), ordenio: 1, litros: 30.0);
      await produccionDao.guardar(
        animalId: v18.id, fecha: haceDias(1), ordenio: 1, litros: 5.0);

      expect(await produccionDao.detectarCaidas(fincaId: finca.id, hoy: fechaBase), isEmpty);
    });

    test('faltantes lista las vacas sin registrar en el ordenio', () async {
      final hoy = haceDias(0);

      await produccionDao.guardar(
        animalId: v18.id, fecha: hoy, ordenio: 1, litros: 15.0);

      final pendientes = await produccionDao.faltantes(
        fincaId: finca.id, fecha: hoy, ordenio: 1);

      // Solo falta V-22. Mostrar este contador en pantalla es lo que hace que
      // el registro se complete en vez de quedar a medias.
      expect(pendientes, hasLength(1));
      expect(pendientes.first, equals(v22.id));
    });

    test('delOrdenio devuelve solo ese dia y ese ordenio', () async {
      final hoy = haceDias(0);
      await produccionDao.guardar(
        animalId: v18.id, fecha: hoy, ordenio: 1, litros: 15.5);
      // Otro ordenio y otro dia: no deben aparecer.
      await produccionDao.guardar(
        animalId: v22.id, fecha: hoy, ordenio: 2, litros: 9.0);
      await produccionDao.guardar(
        animalId: v22.id, fecha: haceDias(1), ordenio: 1, litros: 8.0);

      final anotado = await produccionDao.delOrdenio(
        fincaId: finca.id, fecha: hoy, ordenio: 1);

      expect(anotado, equals({v18.id: 15.5}));
    });
  });
}
