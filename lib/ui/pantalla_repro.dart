// =============================================================================
//  pantalla_repro.dart
//  Registrar un evento reproductivo. Tarea T8 de docs/alcance.md.
//
//  UN SOLO FORMULARIO PARA LOS SEIS TIPOS. Arriba se elige el tipo y debajo
//  aparecen solo los campos de ese tipo. Seis pantallas casi iguales serian
//  seis lugares donde mantener el mismo selector de fecha.
//
//  DECISIONES QUE PROTEGEN EL DATASET:
//
//  - El ABORTO se guarda con registrarAborto(), la unica via (regla 1 de
//    CLAUDE.md). Aqui no hay forma de mandarlo a evento_salud.
//  - El momento se elige igual que en pantalla_evento: respuestas en lenguaje
//    normal, precision deducida (regla 7). Sin "No lo se": la columna
//    ts_evento es obligatoria y un parto siempre tiene al menos un dia.
//  - En el CELO se pide como se detecto. Cuando llegue el collar, esa columna
//    es la que permite comparar ojo contra sensor.
//
//  EFECTO SOBRE LA CATEGORIA: un parto deja a la vaca "en ordenio" y un
//  secado la deja "seca". Se actualiza sola porque la categoria es la que
//  decide quien aparece en la captura de produccion; si hubiera que cambiarla
//  a mano, la vaca recien parida no apareceria en el ordenio de manana.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/dao/evento_reproductivo_dao.dart';
import '../data/models/animal.dart';
import '../data/models/evento_reproductivo.dart';
import 'comunes.dart';

class PantallaRepro extends StatefulWidget {
  final Animal animal;

  const PantallaRepro({super.key, required this.animal});

  @override
  State<PantallaRepro> createState() => _PantallaReproState();
}

class _PantallaReproState extends State<PantallaRepro> {
  final _reproDao = EventoReproductivoDao();
  final _animalDao = AnimalDao();

  final _semen = TextEditingController();
  final _notas = TextEditingController();

  String? _tipo;
  MomentoInicio? _momento;

  // Campos por tipo
  String? _metodoCelo;
  String? _servicioTipo;
  int _numeroServicio = 1;
  String? _resultado;
  int _crias = 1;
  int? _dificultad;

  bool _guardando = false;

  /// Las opciones de momento sin "No lo se": ts_evento no admite null.
  static final _momentos =
      MomentoInicio.opciones.where((m) => m.horasAtras >= 0).toList();

  @override
  void dispose() {
    _semen.dispose();
    _notas.dispose();
    super.dispose();
  }

  bool get _completo => _tipo != null && _momento != null;

  Future<void> _guardar() async {
    if (!_completo || _guardando) return;
    setState(() => _guardando = true);

    final animal = widget.animal;
    final fecha = _momento!.calcularFecha()!;
    final notas = _notas.text.trim().isEmpty ? null : _notas.text.trim();

    if (_tipo == TipoRepro.aborto) {
      await _reproDao.registrarAborto(
        animalId: animal.id,
        fecha: fecha,
        precisionTs: _momento!.precision,
        notas: notas,
      );
    } else {
      final semen = _semen.text.trim();
      await _reproDao.crear(
        animalId: animal.id,
        tipo: _tipo!,
        tsEvento: fecha,
        precisionTs: _momento!.precision,
        metodoDeteccion: _tipo == TipoRepro.celo ? _metodoCelo : null,
        servicioTipo: _tipo == TipoRepro.servicio ? _servicioTipo : null,
        numeroServicio: _tipo == TipoRepro.servicio ? _numeroServicio : null,
        identificadorSemen:
            _tipo == TipoRepro.servicio && semen.isNotEmpty ? semen : null,
        resultado: _tipo == TipoRepro.palpacion ? _resultado : null,
        criasNacidas: _tipo == TipoRepro.parto ? _crias : null,
        dificultadParto: _tipo == TipoRepro.parto ? _dificultad : null,
        notas: notas,
      );
    }

    // Ver el comentario de cabecera: la categoria sigue al ciclo.
    final nueva = switch (_tipo) {
      TipoRepro.parto => CategoriaAnimal.vacaLactancia,
      TipoRepro.secado => CategoriaAnimal.vacaSeca,
      _ => null,
    };
    if (nueva != null && nueva != animal.categoria) {
      await _animalDao.actualizar(animal.copyWith(categoria: nueva));
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Evento reproductivo')),
      body: ListView(
        padding: const EdgeInsets.all(Medida.md),
        children: [
          Text(widget.animal.etiqueta, style: Tipo.cuerpoSuave),
          const SizedBox(height: Medida.md),

          const TituloSeccion('¿Qué pasó?'),
          GrillaOpciones<String>(
            valores: TipoRepro.todos,
            elegido: _tipo,
            etiqueta: TipoRepro.nombre,
            onElegir: (t) => setState(() => _tipo = t),
          ),

          // El resto aparece cuando hay tipo: asi la pantalla guia el orden.
          if (_tipo != null) ...[
            const SizedBox(height: Medida.lg),
            const TituloSeccion('¿Cuándo?'),
            SelectorMomento(
              opciones: _momentos,
              elegido: _momento,
              onElegir: (m) => setState(() => _momento = m),
            ),
            ..._camposDelTipo(),
            const SizedBox(height: Medida.lg),
            TextField(
              controller: _notas,
              maxLines: 2,
              style: Tipo.cuerpo,
              decoration: const InputDecoration(labelText: 'Notas (opcional)'),
            ),
          ],
          const SizedBox(height: Medida.xl),
        ],
      ),
      bottomNavigationBar: BarraInferior(
        hijos: [
          ElevatedButton(
            onPressed: _completo && !_guardando ? _guardar : null,
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  List<Widget> _camposDelTipo() {
    switch (_tipo) {
      case TipoRepro.celo:
        return [
          const SizedBox(height: Medida.lg),
          const TituloSeccion(
            '¿Cómo se detectó?',
            apoyo:
                'Cuando llegue el collar, esto permite compararlo con el ojo.',
          ),
          GrillaOpciones<String>(
            valores: MetodoDeteccionCelo.manuales,
            elegido: _metodoCelo,
            etiqueta: MetodoDeteccionCelo.nombre,
            onElegir: (m) => setState(() => _metodoCelo = m),
          ),
        ];

      case TipoRepro.servicio:
        return [
          const SizedBox(height: Medida.lg),
          const TituloSeccion('Tipo de servicio'),
          GrillaOpciones<String>(
            valores: TipoServicio.todos,
            elegido: _servicioTipo,
            etiqueta: TipoServicio.nombre,
            onElegir: (t) => setState(() => _servicioTipo = t),
          ),
          const SizedBox(height: Medida.md),
          Contador(
            etiqueta: 'Número de servicio',
            valor: _numeroServicio,
            minimo: 1,
            maximo: 10,
            onCambio: (v) => setState(() => _numeroServicio = v),
          ),
          const SizedBox(height: Medida.md),
          TextField(
            controller: _semen,
            style: Tipo.cuerpo,
            decoration: const InputDecoration(
              labelText: 'Pajuela o toro (opcional)',
            ),
          ),
        ];

      case TipoRepro.palpacion:
        return [
          const SizedBox(height: Medida.lg),
          const TituloSeccion('Resultado'),
          GrillaOpciones<String>(
            valores: ResultadoPalpacion.todos,
            elegido: _resultado,
            etiqueta: ResultadoPalpacion.nombre,
            onElegir: (r) => setState(() => _resultado = r),
          ),
        ];

      case TipoRepro.parto:
        return [
          const SizedBox(height: Medida.lg),
          Contador(
            etiqueta: 'Crías',
            valor: _crias,
            minimo: 0,
            maximo: 4,
            onCambio: (v) => setState(() => _crias = v),
          ),
          const SizedBox(height: Medida.lg),
          const TituloSeccion(
            '¿Cómo fue el parto?',
            apoyo: 'Un parto difícil deja huella en el comportamiento de los '
                'días siguientes.',
          ),
          GrillaOpciones<int>(
            valores: DificultadParto.todas,
            elegido: _dificultad,
            etiqueta: DificultadParto.nombre,
            onElegir: (d) => setState(() => _dificultad = d),
          ),
        ];

      default:
        return const [];
    }
  }
}
