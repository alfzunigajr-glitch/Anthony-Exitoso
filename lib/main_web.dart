// =============================================================================
//  main_web.dart
//  Punto de entrada SOLO para la version de prueba en el navegador, la que se
//  publica en Railway (ver docs/despliegue.md). El APK usa main.dart.
//
//  Cambia dos cosas respecto de main.dart y nada mas:
//   1. SQLite corre compilado a WebAssembly y guarda en el navegador
//      (IndexedDB) en vez de en el telefono. CADA NAVEGADOR TIENE SU PROPIA
//      BASE: lo que se registra en el computador no aparece en el celular.
//      Sirve para revisar la interfaz, no para cargar datos reales.
//   2. En el primer arranque carga una finca y un hato de EJEMPLO, para que
//      cada pantalla tenga algo que mostrar.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'data/dao/animal_dao.dart';
import 'data/dao/evento_reproductivo_dao.dart';
import 'data/dao/evento_salud_dao.dart';
import 'data/dao/produccion_dao.dart';
import 'data/dao/tratamiento_dao.dart';
import 'data/models/animal.dart';
import 'data/models/evento_reproductivo.dart';
import 'data/models/evento_salud.dart';
import 'data/models/finca.dart';
import 'main.dart' show AppGanado;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Sin web worker: la base corre en la misma pestania. Asi basta con publicar
  // sqlite3.wasm, sin el archivo del worker, y funciona tambien donde los
  // workers estan bloqueados.
  databaseFactory = databaseFactoryFfiWebNoWebWorker;

  await _sembrarEjemplo();
  runApp(const AppGanado());
}

Future<void> _sembrarEjemplo() async {
  final fincaDao = FincaDao();
  if (await fincaDao.actual() != null) return;

  final finca = await fincaDao.crear(nombre: 'Finca de ejemplo');
  final animales = AnimalDao();
  final ahora = DateTime.now();
  DateTime hace({int dias = 0, int horas = 0}) =>
      ahora.subtract(Duration(days: dias, hours: horas));

  Future<Animal> vaca(String arete, String nombre,
          {String categoria = CategoriaAnimal.vacaLactancia}) =>
      animales.crear(
        fincaId: finca.id,
        sexo: 'H',
        categoria: categoria,
        fechaIngreso: hace(dias: 400),
        areteInterno: arete,
        nombre: nombre,
        raza: Raza.holstein,
      );

  final v07 = await vaca('V-07', 'Estrella');
  final v12 = await vaca('V-12', 'Canela');
  final v18 = await vaca('V-18', 'Lucera');
  final v22 = await vaca('V-22', 'Paloma');
  final v31 = await vaca('V-31', 'Morena');
  await vaca('T-04', 'Bonita', categoria: CategoriaAnimal.vacona);

  final salud = EventoSaludDao();
  final tratamientos = TratamientoDao();

  // Caso completo y antiguo: cuenta para el algoritmo.
  await salud.crear(
    animalId: v07.id,
    diagnosticoCodigo: 'DIARREA',
    tsInicioEstimado: hace(dias: 10, horas: 2),
    tsDeteccionHumana: hace(dias: 10),
    precisionTsInicio: PrecisionTs.exacto,
    metodoDiagnostico: MetodoDiagnostico.clinico,
    confirmado: true,
    severidad: 1,
  );

  // Mastitis confirmada con antibiotico: leche en retiro.
  final mastitis = await salud.crear(
    animalId: v12.id,
    diagnosticoCodigo: 'MAST_CLIN',
    tsInicioEstimado: hace(dias: 2, horas: 6),
    tsDeteccionHumana: hace(dias: 2),
    precisionTsInicio: PrecisionTs.masMenos6h,
    metodoDiagnostico: MetodoDiagnostico.clinico,
    confirmado: true,
    severidad: 2,
  );
  await tratamientos.crear(
    eventoSaludId: mastitis.id,
    tsAplicacion: hace(dias: 2),
    farmaco: 'Cefalexina intramamaria',
    diasRetiroLeche: 4,
  );

  // Cojera sin confirmar: queda "por completar", tambien en retiro.
  final cojera = await salud.crear(
    animalId: v31.id,
    diagnosticoCodigo: 'COJERA',
    tsDeteccionHumana: hace(dias: 1),
    metodoDiagnostico: MetodoDiagnostico.presuntivo,
  );
  await tratamientos.crear(
    eventoSaludId: cojera.id,
    tsAplicacion: hace(dias: 1),
    farmaco: 'Oxitetraciclina',
    diasRetiroLeche: 5,
  );

  // Historia reproductiva: partos para que haya dias en leche, y un ciclo de
  // servicio y palpacion en V-07.
  final repro = EventoReproductivoDao();
  for (final (vaca, dias) in [(v07, 95), (v12, 40), (v18, 60), (v22, 150), (v31, 25)]) {
    await repro.crear(
      animalId: vaca.id,
      tipo: TipoRepro.parto,
      tsEvento: hace(dias: dias),
      precisionTs: PrecisionTs.masMenos1d,
      criasNacidas: 1,
      dificultadParto: 1,
    );
  }
  await repro.crear(
    animalId: v07.id,
    tipo: TipoRepro.celo,
    tsEvento: hace(dias: 50),
    precisionTs: PrecisionTs.masMenos6h,
    metodoDeteccion: MetodoDeteccionCelo.monta,
  );
  await repro.crear(
    animalId: v07.id,
    tipo: TipoRepro.servicio,
    tsEvento: hace(dias: 50),
    precisionTs: PrecisionTs.exacto,
    servicioTipo: TipoServicio.ia,
    numeroServicio: 1,
  );
  await repro.crear(
    animalId: v07.id,
    tipo: TipoRepro.palpacion,
    tsEvento: hace(dias: 5),
    precisionTs: PrecisionTs.exacto,
    resultado: ResultadoPalpacion.preniada,
  );

  // Ordenios de la ultima semana. V-18 baja de 30 a 21 litros el ultimo dia.
  final produccion = ProduccionDao();
  const base = {'V-07': 22.0, 'V-12': 18.0, 'V-18': 30.0, 'V-22': 20.0, 'V-31': 16.0};
  final porArete = {'V-07': v07, 'V-12': v12, 'V-18': v18, 'V-22': v22, 'V-31': v31};
  for (var d = 8; d >= 1; d--) {
    for (final e in base.entries) {
      final litrosDia = (e.key == 'V-18' && d == 1) ? 21.0 : e.value;
      for (final ordenio in [1, 2]) {
        await produccion.guardar(
          animalId: porArete[e.key]!.id,
          fecha: hace(dias: d),
          ordenio: ordenio,
          litros: litrosDia / 2,
        );
      }
    }
  }
}
