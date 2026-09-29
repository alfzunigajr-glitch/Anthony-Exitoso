// =============================================================================
//  pantalla_completar_evento.dart
//  Completar un caso guardado a medias. Parte de la tarea T6.
//
//  Un caso "incompleto" existe pero todavia no sirve para entrenar: le falta
//  la confirmacion, la fecha de inicio, o la fecha que tiene es demasiado
//  vaga. Esta pantalla pide solo eso.
//
//  LA PREGUNTA DE "CUANDO EMPEZO" MIRA HACIA ATRAS DESDE LA DETECCION, no
//  desde hoy. Si el caso se noto hace tres dias, "el dia anterior" significa
//  hace cuatro dias. Preguntarlo desde hoy obligaria a la persona a hacer la
//  cuenta, y la cuenta mal hecha es una etiqueta corrida un dia.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/evento_salud_dao.dart';
import '../data/models/evento_salud.dart';
import 'comunes.dart';

class PantallaCompletarEvento extends StatefulWidget {
  final EventoSalud evento;

  /// 'Cojera · V-31'
  final String titulo;

  const PantallaCompletarEvento({
    super.key,
    required this.evento,
    required this.titulo,
  });

  @override
  State<PantallaCompletarEvento> createState() =>
      _PantallaCompletarEventoState();
}

class _PantallaCompletarEventoState extends State<PantallaCompletarEvento> {
  final _dao = EventoSaludDao();

  MomentoInicio? _momento;
  late bool _confirmado = widget.evento.confirmado;
  late int? _severidad = widget.evento.severidad;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    // Si el caso ya traia una precision, se marca la opcion equivalente para
    // que la persona vea lo que se habia dicho y solo cambie lo que falte.
    final previa = widget.evento.precisionTsInicio;
    for (final m in MomentoInicio.opcionesDesdeDeteccion) {
      if (m.precision == previa &&
          (widget.evento.tsInicioEstimado != null || m.horasAtras < 0)) {
        _momento = m;
      }
    }
  }

  /// Si con lo elegido el caso pasa a servir. Replica sirveParaEntrenar para
  /// mostrarlo ANTES de guardar, igual que pantalla_evento.
  bool get _servira =>
      _confirmado &&
      _momento != null &&
      _momento!.horasAtras >= 0 &&
      PrecisionTs.utilesParaEntrenar.contains(_momento!.precision);

  Future<void> _guardar() async {
    if (_guardando) return;
    setState(() => _guardando = true);

    final e = widget.evento;
    final momento = _momento;

    await _dao.completar(
      eventoId: e.id,
      // Sin respuesta nueva se conserva lo que ya habia.
      tsInicioEstimado: momento == null
          ? e.tsInicioEstimado
          : momento.calcularFecha(desde: e.tsDeteccionHumana),
      precisionTsInicio: momento?.precision ?? e.precisionTsInicio,
      confirmado: _confirmado,
      severidad: _severidad,
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.evento;

    return Scaffold(
      appBar: AppBar(title: const Text('Completar caso')),
      body: ListView(
        padding: const EdgeInsets.all(Medida.md),
        children: [
          Text(widget.titulo, style: Tipo.subtitulo),
          const SizedBox(height: Medida.xs),
          Text('Se notó el ${fechaHora(e.tsDeteccionHumana)}',
              style: Tipo.cuerpoSuave),
          const SizedBox(height: Medida.lg),
          const TituloSeccion(
            '¿Cuándo empezó?',
            apoyo: 'Contando desde que se notó. Si no se sabe, dilo: '
                'es mejor que adivinar.',
          ),
          SelectorMomento(
            opciones: MomentoInicio.opcionesDesdeDeteccion,
            elegido: _momento,
            onElegir: (m) => setState(() => _momento = m),
          ),
          const SizedBox(height: Medida.md),
          SwitchListTile(
            value: _confirmado,
            onChanged: (v) => setState(() => _confirmado = v),
            title: const Text('Diagnóstico confirmado', style: Tipo.cuerpo),
            subtitle: const Text(
              'Actívalo solo si lo revisaste como veterinario',
              style: Tipo.apoyo,
            ),
            activeThumbColor: Colores.primario,
            contentPadding: EdgeInsets.zero,
          ),
          if (_confirmado) ...[
            const SizedBox(height: Medida.sm),
            const TituloSeccion('Gravedad'),
            Row(
              children: [
                for (final n in [1, 2, 3]) ...[
                  Expanded(
                    child: Opcion(
                      texto: const {1: 'Leve', 2: 'Moderado', 3: 'Grave'}[n]!,
                      elegida: _severidad == n,
                      onTap: () => setState(() => _severidad = n),
                    ),
                  ),
                  if (n < 3) const SizedBox(width: Medida.sm),
                ],
              ],
            ),
          ],
          const SizedBox(height: Medida.xl),
        ],
      ),
      bottomNavigationBar: BarraInferior(
        hijos: [
          Padding(
            padding: const EdgeInsets.only(bottom: Medida.sm),
            child: Row(
              children: [
                Icon(
                  _servira ? Icons.check_circle : Icons.info_outline,
                  size: 20,
                  color: _servira ? Colores.primario : Colores.atencion,
                ),
                const SizedBox(width: Medida.sm),
                Expanded(
                  child: Text(
                    _servira
                        ? 'Con esto, el caso sirve para el algoritmo'
                        : 'Se guarda igual; seguirá en “por completar”.',
                    style: Tipo.apoyo.copyWith(
                      color: _servira ? Colores.primario : Colores.atencion,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _guardando ? null : _guardar,
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}
