// =============================================================================
//  pantalla_animal.dart
//  Ficha de un animal. Tarea T3 de docs/alcance.md.
//
//  EL ORDEN RESPONDE A QUE SE NECESITA AL ABRIRLA JUNTO A LA VACA:
//
//   1. RETIRO DE LECHE, si lo hay. Arriba y en rojo, igual que en el inicio:
//      es lo unico que si se pasa por alto cuesta la entrega completa.
//   2. QUIEN ES: categoria, edad y dias en leche. Los dias en leche importan
//      porque casi toda la patologia cae en las semanas despues del parto.
//   3. HISTORIAL SANITARIO, lo mas reciente arriba. Cada caso dice si ya
//      sirve para el algoritmo y, si no, que le falta. Desde el caso se
//      completa o se le agrega un tratamiento: son los dos pasos que siguen
//      a registrar un caso, y tenerlos aqui evita buscarlo en otra pantalla.
//   4. HISTORIAL REPRODUCTIVO.
//
//  Los botones de registrar van fijos abajo, con el animal ya elegido.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/dao/evento_reproductivo_dao.dart';
import '../data/dao/evento_salud_dao.dart';
import '../data/dao/tratamiento_dao.dart';
import '../data/models/animal.dart';
import '../data/models/diagnostico.dart';
import '../data/models/evento_reproductivo.dart';
import '../data/models/evento_salud.dart';
import '../data/models/tratamiento.dart';
import 'comunes.dart';
import 'pantalla_completar_evento.dart';
import 'pantalla_evento.dart';
import 'pantalla_repro.dart';
import 'pantalla_tratamiento.dart';

class PantallaAnimal extends StatefulWidget {
  final Animal animal;

  const PantallaAnimal({super.key, required this.animal});

  @override
  State<PantallaAnimal> createState() => _PantallaAnimalState();
}

class _PantallaAnimalState extends State<PantallaAnimal> {
  final _animalDao = AnimalDao();
  final _saludDao = EventoSaludDao();
  final _reproDao = EventoReproductivoDao();
  final _tratamientoDao = TratamientoDao();
  final _diagnosticoDao = DiagnosticoDao();

  late Animal _animal = widget.animal;
  AnimalEnRetiro? _retiro;
  int? _diasEnLeche;
  List<EventoSalud> _salud = [];
  List<EventoReproductivo> _repro = [];

  /// Tratamientos agrupados por el caso al que pertenecen, para mostrarlos
  /// debajo de cada caso sin una consulta por fila.
  Map<String, List<Tratamiento>> _tratamientos = {};

  /// Codigo de diagnostico -> nombre legible.
  Map<String, String> _nombres = {};

  bool _cargando = true;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final id = _animal.id;

    // Las seis consultas son independientes: se lanzan juntas.
    final r = await Future.wait([
      _animalDao.porId(id),
      _tratamientoDao.retiroDeAnimal(id),
      _reproDao.diasEnLeche(id),
      _saludDao.porAnimal(id),
      _reproDao.porAnimal(id),
      _tratamientoDao.porAnimal(id),
      _diagnosticoDao.listar(),
    ]);

    if (!mounted) return;

    final tratamientos = <String, List<Tratamiento>>{};
    for (final t in r[5] as List<Tratamiento>) {
      tratamientos.putIfAbsent(t.eventoSaludId, () => []).add(t);
    }

    setState(() {
      // Se relee el animal porque un parto o un secado le cambia la categoria.
      _animal = (r[0] as Animal?) ?? _animal;
      _retiro = r[1] as AnimalEnRetiro?;
      _diasEnLeche = r[2] as int?;
      _salud = r[3] as List<EventoSalud>;
      _repro = r[4] as List<EventoReproductivo>;
      _tratamientos = tratamientos;
      _nombres = {
        for (final d in r[6] as List<Diagnostico>) d.codigo: d.nombre,
      };
      _cargando = false;
    });
  }

  /// Abre una pantalla y recarga la ficha si alli se guardo algo.
  Future<void> _abrir(Widget pantalla) async {
    final hubo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => pantalla),
    );
    if (hubo == true) {
      _huboCambios = true;
      _cargar();
    }
  }

  String _nombreDiagnostico(String codigo) => _nombres[codigo] ?? codigo;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_huboCambios);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_animal.etiqueta)),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _cargar,
                child: ListView(
                  padding: const EdgeInsets.all(Medida.md),
                  children: [
                    if (_retiro != null) ...[
                      _bloqueRetiro(_retiro!),
                      const SizedBox(height: Medida.lg),
                    ],
                    _bloqueDatos(),
                    const SizedBox(height: Medida.lg),
                    _bloqueSalud(),
                    const SizedBox(height: Medida.lg),
                    _bloqueRepro(),
                    const SizedBox(height: Medida.xl),
                  ],
                ),
              ),
        bottomNavigationBar: _cargando ? null : _barra(),
      ),
    );
  }

  // ===========================================================================
  //  BLOQUES
  // ===========================================================================

  Widget _bloqueRetiro(AnimalEnRetiro r) {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: BoxDecoration(
        color: Colores.alertaClara,
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
        border: const Border(left: BorderSide(color: Colores.alerta, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No entregar su leche',
            style: Tipo.subtitulo.copyWith(color: Colores.alerta),
          ),
          const SizedBox(height: Medida.xs),
          Text('${r.farmaco} · hasta ${fechaHora(r.retiroHasta)}',
              style: Tipo.cuerpo),
        ],
      ),
    );
  }

  Widget _bloqueDatos() {
    final datos = <(String, String)>[
      ('Categoría', CategoriaAnimal.etiqueta(_animal.categoria)),
      if (_animal.edadDias != null)
        (
          'Edad',
          '${edadLegible(_animal.edadDias!)}'
              '${_animal.nacimientoEstimado ? " (aprox.)" : ""}'
        ),
      if (_diasEnLeche != null) ('Días en leche', '$_diasEnLeche'),
      if (_animal.raza != null) ('Raza', Raza.etiqueta(_animal.raza!)),
      if (_animal.areteOficial != null)
        ('Arete oficial', _animal.areteOficial!),
      ('En la finca desde', fechaCorta(_animal.fechaIngreso)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_animal.activo) ...[
          Text(
            'Fuera del hato'
            '${_animal.motivoSalida == null ? "" : " · ${_animal.motivoSalida!.toLowerCase()}"}',
            style: Tipo.cuerpo.copyWith(color: Colores.atencion),
          ),
          const SizedBox(height: Medida.sm),
        ],
        for (final (etiqueta, valor) in datos)
          Padding(
            padding: const EdgeInsets.only(bottom: Medida.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 150,
                  child: Text(etiqueta, style: Tipo.cuerpoSuave),
                ),
                Expanded(child: Text(valor, style: Tipo.cuerpo)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _bloqueSalud() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TituloSeccion('Salud'),
        if (_salud.isEmpty)
          const Text('Sin casos registrados.', style: Tipo.cuerpoSuave)
        else
          for (final e in _salud) ...[
            _tarjetaCaso(e),
            const SizedBox(height: Medida.sm),
          ],
      ],
    );
  }

  Widget _tarjetaCaso(EventoSalud e) {
    final tratamientos = _tratamientos[e.id] ?? const <Tratamiento>[];
    final falta = e.motivoNoSirve;
    final nombre = _nombreDiagnostico(e.diagnosticoCodigo);

    return Container(
      padding:
          const EdgeInsets.fromLTRB(Medida.md, Medida.md, Medida.sm, Medida.xs),
      decoration: BoxDecoration(
        color: Colores.superficieAlta,
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
        border: Border.all(color: Colores.borde),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nombre,
                  style: Tipo.cuerpo.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(haceCuanto(e.tsDeteccionHumana), style: Tipo.apoyo),
              const SizedBox(width: Medida.sm),
            ],
          ),
          const SizedBox(height: Medida.xs),

          // Estado para el algoritmo, en forma y color, no solo en texto:
          // se lee de un vistazo cuales casos faltan.
          Row(
            children: [
              Icon(
                falta == null ? Icons.check_circle : Icons.info_outline,
                size: 18,
                color: falta == null ? Colores.primario : Colores.atencion,
              ),
              const SizedBox(width: Medida.xs),
              Expanded(
                child: Text(
                  falta ?? 'Sirve para el algoritmo',
                  style: Tipo.apoyo.copyWith(
                    color: falta == null ? Colores.primario : Colores.atencion,
                  ),
                ),
              ),
            ],
          ),

          for (final t in tratamientos)
            Padding(
              padding: const EdgeInsets.only(top: Medida.xs),
              child: Text(
                '${t.farmaco} · ${fechaCorta(t.tsAplicacion)}'
                '${(t.diasRetiroLeche ?? 0) > 0 ? " · retiro ${t.diasRetiroLeche} d" : ""}',
                style: Tipo.apoyo,
              ),
            ),

          // Wrap y no Row: con letra grande del sistema o pantalla angosta
          // los dos botones no caben en una linea y el segundo baja. El ancho
          // completo es para que alignment.end los lleve a la derecha.
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.end,
              children: [
                if (falta != null)
                  TextButton(
                    onPressed: () => _abrir(PantallaCompletarEvento(
                      evento: e,
                      titulo: '$nombre · ${_animal.etiqueta}',
                    )),
                    child: const Text('Completar'),
                  ),
                TextButton(
                  onPressed: () => _abrir(PantallaTratamiento(
                    fincaId: _animal.fincaId,
                    eventoSaludId: e.id,
                    titulo: '$nombre · ${_animal.etiqueta}',
                  )),
                  child: const Text('Tratamiento'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueRepro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const TituloSeccion('Reproducción'),
        if (_repro.isEmpty)
          const Text('Sin eventos registrados.', style: Tipo.cuerpoSuave)
        else
          for (final r in _repro)
            Container(
              constraints: const BoxConstraints(minHeight: Medida.toque),
              padding: const EdgeInsets.symmetric(vertical: Medida.sm),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colores.borde)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(TipoRepro.nombre(r.tipo), style: Tipo.cuerpo),
                        if (_detalleRepro(r) != null)
                          Text(_detalleRepro(r)!, style: Tipo.apoyo),
                      ],
                    ),
                  ),
                  Text(haceCuanto(r.tsEvento), style: Tipo.apoyo),
                ],
              ),
            ),
      ],
    );
  }

  /// Linea de detalle segun el tipo: lo que distingue a ese evento.
  String? _detalleRepro(EventoReproductivo r) {
    switch (r.tipo) {
      case TipoRepro.palpacion:
        return r.resultado == null
            ? null
            : ResultadoPalpacion.nombre(r.resultado!);
      case TipoRepro.celo:
        return r.metodoDeteccion == null
            ? null
            : 'Detectado por ${MetodoDeteccionCelo.nombre(r.metodoDeteccion!).toLowerCase()}';
      case TipoRepro.servicio:
        final partes = [
          if (r.servicioTipo != null) TipoServicio.nombre(r.servicioTipo!),
          if (r.numeroServicio != null) '${r.numeroServicio}.º servicio',
          if (r.identificadorSemen != null) r.identificadorSemen!,
        ];
        return partes.isEmpty ? null : partes.join(' · ');
      case TipoRepro.parto:
        return r.criasNacidas == null
            ? null
            : '${r.criasNacidas} ${r.criasNacidas == 1 ? "cría" : "crías"}';
      default:
        return null;
    }
  }

  Widget _barra() {
    return BarraInferior(
      hijos: [
        ElevatedButton.icon(
          onPressed: () => _abrir(PantallaEvento(
            fincaId: _animal.fincaId,
            animalInicial: _animal,
          )),
          icon: const Icon(Icons.add),
          label: const Text('Registrar caso'),
        ),
        // Solo las hembras tienen eventos reproductivos en este esquema: el
        // toro no tiene celos, partos ni palpaciones propias.
        if (_animal.sexo == Sexo.hembra) ...[
          const SizedBox(height: Medida.sm),
          OutlinedButton(
            onPressed: () => _abrir(PantallaRepro(animal: _animal)),
            child: const Text('Evento reproductivo'),
          ),
        ],
      ],
    );
  }
}
