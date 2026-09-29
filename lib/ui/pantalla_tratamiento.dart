// =============================================================================
//  pantalla_tratamiento.dart
//  Registrar un medicamento aplicado. Tarea T4 de docs/alcance.md.
//
//  ES LA PANTALLA CON VALOR PRACTICO INMEDIATO PARA JHON: de aqui sale el
//  bloque "No entregar esta leche" del inicio. Sin tratamientos registrados,
//  ese bloque nunca muestra nada.
//
//  TRES DECISIONES:
//
//  1. LOS FARMACOS YA USADOS APARECEN ARRIBA. Tocar uno llena el nombre y sus
//     dias de retiro. La finca usa casi siempre los mismos cuatro o cinco
//     productos; escribirlos cada vez es la forma segura de que se registre
//     "Mastijet", "mastijet" y "Mastijet forte" para lo mismo.
//
//  2. LOS DIAS DE RETIRO VAN CON BOTONES DE MENOS Y MAS, no con teclado.
//
//  3. AL GUARDAR SE CONFIRMA HASTA CUANDO NO SE ENTREGA LA LECHE, con dia de
//     la semana y hora. Es la informacion que Jhon le tiene que pasar al
//     ordeniador, y la app se la da ya calculada.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/tratamiento_dao.dart';
import '../data/models/tratamiento.dart';
import 'comunes.dart';

class PantallaTratamiento extends StatefulWidget {
  final String fincaId;
  final String eventoSaludId;

  /// Para quien es: 'Mastitis clinica · V-12'. Se muestra arriba para que no
  /// haya duda de a que caso se esta agregando el medicamento.
  final String titulo;

  const PantallaTratamiento({
    super.key,
    required this.fincaId,
    required this.eventoSaludId,
    required this.titulo,
  });

  @override
  State<PantallaTratamiento> createState() => _PantallaTratamientoState();
}

class _PantallaTratamientoState extends State<PantallaTratamiento> {
  final _dao = TratamientoDao();
  final _farmaco = TextEditingController();

  DateTime _aplicacion = DateTime.now();
  int _retiroLeche = 0;
  int _retiroCarne = 0;
  String? _via;

  List<Map<String, Object?>> _frecuentes = [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargarFrecuentes();
  }

  @override
  void dispose() {
    _farmaco.dispose();
    super.dispose();
  }

  Future<void> _cargarFrecuentes() async {
    final lista = await _dao.farmacosFrecuentes(widget.fincaId);
    if (!mounted) return;
    setState(() => _frecuentes = lista);
  }

  void _usarFrecuente(Map<String, Object?> f) {
    setState(() {
      _farmaco.text = f['farmaco'] as String;
      // El retiro se precarga con el ultimo usado para ese farmaco. Se puede
      // cambiar: una dosis distinta puede llevar otro periodo.
      _retiroLeche = (f['dias_retiro_leche'] as int?) ?? _retiroLeche;
    });
  }

  Future<void> _elegirMomento() async {
    final hoy = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: _aplicacion,
      firstDate: hoy.subtract(const Duration(days: 60)),
      lastDate: hoy,
    );
    if (dia == null || !mounted) return;

    final hora = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_aplicacion),
    );
    if (!mounted) return;

    setState(() {
      _aplicacion = DateTime(
        dia.year,
        dia.month,
        dia.day,
        hora?.hour ?? _aplicacion.hour,
        hora?.minute ?? _aplicacion.minute,
      );
    });
  }

  bool get _completo => _farmaco.text.trim().isNotEmpty;

  Future<void> _guardar() async {
    if (!_completo || _guardando) return;
    setState(() => _guardando = true);

    final t = await _dao.crear(
      eventoSaludId: widget.eventoSaludId,
      tsAplicacion: _aplicacion,
      farmaco: _farmaco.text.trim(),
      via: _via,
      diasRetiroLeche: _retiroLeche,
      diasRetiroCarne: _retiroCarne,
    );

    if (!mounted) return;

    final hasta = t.retiroLecheHasta;
    if (hasta != null && hasta.isAfter(DateTime.now())) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('No entregar la leche'),
          content: Text(
            'La leche de este animal no se puede entregar hasta el '
            '${fechaHora(hasta)}.\n\nYa aparece en la pantalla de inicio.',
            style: Tipo.cuerpo,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      if (!mounted) return;
    }

    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tratamiento')),
      body: ListView(
        padding: const EdgeInsets.all(Medida.md),
        children: [
          Text(widget.titulo, style: Tipo.cuerpoSuave),
          const SizedBox(height: Medida.md),
          TextField(
            controller: _farmaco,
            autofocus: _frecuentes.isEmpty,
            style: Tipo.cuerpo,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Medicamento',
              hintText: 'Como dice el frasco',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_frecuentes.isNotEmpty) ...[
            const SizedBox(height: Medida.sm),
            const Text('Usados antes', style: Tipo.apoyo),
            const SizedBox(height: Medida.xs),
            Wrap(
              spacing: Medida.sm,
              runSpacing: Medida.sm,
              children: [
                for (final f in _frecuentes)
                  ActionChip(
                    label: Text(f['farmaco'] as String, style: Tipo.cuerpo),
                    onPressed: () => _usarFrecuente(f),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    padding: const EdgeInsets.all(Medida.sm),
                  ),
              ],
            ),
          ],
          const SizedBox(height: Medida.lg),
          FilaFecha(
            etiqueta: 'Aplicado',
            valor: fechaHora(_aplicacion),
            onTap: _elegirMomento,
          ),
          const SizedBox(height: Medida.lg),
          const TituloSeccion(
            'Retiro',
            apoyo: 'Lo indica la etiqueta del medicamento. 0 si no tiene.',
          ),
          Contador(
            etiqueta: 'Días de leche',
            valor: _retiroLeche,
            onCambio: (v) => setState(() => _retiroLeche = v),
          ),
          const SizedBox(height: Medida.sm),
          Contador(
            etiqueta: 'Días de carne',
            valor: _retiroCarne,
            maximo: 180,
            onCambio: (v) => setState(() => _retiroCarne = v),
          ),
          const SizedBox(height: Medida.lg),
          const TituloSeccion('Vía (opcional)'),
          GrillaOpciones<String>(
            valores: ViaAdministracion.todas,
            elegido: _via,
            etiqueta: ViaAdministracion.nombre,
            // Tocar la via elegida la quita: es opcional y tiene que poder
            // volver a quedar vacia.
            onElegir: (v) => setState(() => _via = _via == v ? null : v),
          ),
          const SizedBox(height: Medida.xl),
        ],
      ),
      bottomNavigationBar: BarraInferior(
        hijos: [
          ElevatedButton(
            onPressed: _completo && !_guardando ? _guardar : null,
            child: const Text('Guardar tratamiento'),
          ),
        ],
      ),
    );
  }
}
