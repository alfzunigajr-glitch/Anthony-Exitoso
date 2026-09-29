// =============================================================================
//  pantalla_por_completar.dart
//  Casos que todavia no sirven para entrenar. Tarea T6 de docs/alcance.md.
//
//  Es la lista mas rentable de la app: cada fila es una etiqueta que ya se
//  pago (alguien vio el caso y lo anoto) y que con treinta segundos mas pasa
//  a servir. Cada fila dice que le falta, para que no haya que abrirla para
//  saberlo.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/dao/evento_salud_dao.dart';
import '../data/models/animal.dart';
import '../data/models/diagnostico.dart';
import '../data/models/evento_salud.dart';
import 'comunes.dart';
import 'pantalla_completar_evento.dart';

class PantallaPorCompletar extends StatefulWidget {
  final String fincaId;

  const PantallaPorCompletar({super.key, required this.fincaId});

  @override
  State<PantallaPorCompletar> createState() => _PantallaPorCompletarState();
}

class _PantallaPorCompletarState extends State<PantallaPorCompletar> {
  final _saludDao = EventoSaludDao();
  final _animalDao = AnimalDao();
  final _diagnosticoDao = DiagnosticoDao();

  List<EventoSalud> _casos = [];
  Map<String, Animal> _animales = {};
  Map<String, String> _nombres = {};
  bool _cargando = true;
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final casos = await _saludDao.incompletos(widget.fincaId);
    final catalogo = await _diagnosticoDao.listar();

    // Un animal por caso, sin repetir. Son pocos casos: una consulta por
    // animal es mas simple que una consulta nueva con JOIN solo para esto.
    final animales = <String, Animal>{};
    for (final id in casos.map((c) => c.animalId).toSet()) {
      final a = await _animalDao.porId(id);
      if (a != null) animales[id] = a;
    }

    if (!mounted) return;
    setState(() {
      _casos = casos;
      _animales = animales;
      _nombres = {for (final d in catalogo) d.codigo: d.nombre};
      _cargando = false;
    });
  }

  String _titulo(EventoSalud e) {
    final nombre = _nombres[e.diagnosticoCodigo] ?? e.diagnosticoCodigo;
    final animal = _animales[e.animalId]?.etiqueta ?? '—';
    return '$nombre · $animal';
  }

  Future<void> _abrir(EventoSalud e) async {
    final hubo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PantallaCompletarEvento(evento: e, titulo: _titulo(e)),
      ),
    );
    if (hubo == true) {
      _huboCambios = true;
      _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_huboCambios);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
              _cargando ? 'Por completar' : 'Por completar · ${_casos.length}'),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _casos.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(Medida.lg),
                    child: Text(
                      'Todos los casos están completos. Cada uno cuenta para '
                      'el algoritmo.',
                      style: Tipo.cuerpo,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(Medida.md),
                    itemCount: _casos.length,
                    itemBuilder: (_, i) => _fila(_casos[i]),
                  ),
      ),
    );
  }

  Widget _fila(EventoSalud e) {
    return InkWell(
      onTap: () => _abrir(e),
      child: Container(
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
                  Text(_titulo(e), style: Tipo.cuerpo),
                  Text(
                    '${e.motivoNoSirve ?? ""} · ${haceCuanto(e.tsDeteccionHumana)}',
                    style: Tipo.apoyo.copyWith(color: Colores.atencion),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colores.tintaSuave),
          ],
        ),
      ),
    );
  }
}
