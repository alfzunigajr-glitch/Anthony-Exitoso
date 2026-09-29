// =============================================================================
//  pantalla_produccion.dart
//  Captura del ordenio, vaca por vaca. Tarea T5 de docs/alcance.md.
//
//  Alimenta detectarCaidas(), el precursor del algoritmo de la Fase 3 que se
//  puede probar hoy sin ningun sensor.
//
//  PENSADA PARA DIGITAR TREINTA NUMEROS SEGUIDOS:
//
//  1. UNA LISTA CON UN CAMPO POR VACA, no una pantalla por vaca. La tecla
//     "siguiente" del teclado salta al campo de la vaca de abajo: se digita
//     todo el ordenio sin tocar la pantalla.
//
//  2. EL CONTADOR "FALTAN N" ARRIBA. Es lo que hace que el registro se
//     complete en vez de quedar a medias: se ve cuanto falta.
//
//  3. SE ACEPTA COMA DECIMAL. En Ecuador "12,5" es como se escribe; rechazarla
//     obligaria a la persona a adivinar que la app espera un punto.
//
//  4. REABRIR EL MISMO ORDENIO MUESTRA LO YA ANOTADO, y guardar de nuevo
//     corrige en vez de duplicar (el DAO usa UPSERT).
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/dao/produccion_dao.dart';
import '../data/models/animal.dart';
import 'comunes.dart';

class PantallaProduccion extends StatefulWidget {
  final String fincaId;

  const PantallaProduccion({super.key, required this.fincaId});

  @override
  State<PantallaProduccion> createState() => _PantallaProduccionState();
}

class _PantallaProduccionState extends State<PantallaProduccion> {
  final _animalDao = AnimalDao();
  final _produccionDao = ProduccionDao();

  DateTime _fecha = DateTime.now();

  /// Antes del mediodia se asume el ordenio de la maniana. Es el que se esta
  /// registrando casi siempre a esa hora, y ahorra un toque.
  int _ordenio = DateTime.now().hour < 12 ? 1 : 2;

  List<Animal> _vacas = [];

  /// Un campo y un foco por vaca, indexados por el id del animal.
  final Map<String, TextEditingController> _campos = {};
  final Map<String, FocusNode> _focos = {};

  bool _cargando = true;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _campos.values) {
      c.dispose();
    }
    for (final f in _focos.values) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);

    final activos = await _animalDao.listarActivos(widget.fincaId);
    final anotados = await _produccionDao.delOrdenio(
      fincaId: widget.fincaId,
      fecha: _fecha,
      ordenio: _ordenio,
    );

    // Solo las vacas en ordenio: es la misma regla que usa faltantes() en el
    // DAO, asi el contador de esta pantalla y el de la base coinciden.
    final vacas = activos
        .where((a) => a.categoria == CategoriaAnimal.vacaLactancia)
        .toList();

    for (final v in vacas) {
      _campos.putIfAbsent(v.id, TextEditingController.new);
      _focos.putIfAbsent(v.id, FocusNode.new);
      final litros = anotados[v.id];
      _campos[v.id]!.text = litros == null ? '' : _formatear(litros);
    }

    if (!mounted) return;
    setState(() {
      _vacas = vacas;
      _cargando = false;
    });
  }

  /// '12,5' o '12' (sin ',0'). Se muestra con coma, como se escribe aqui.
  String _formatear(double litros) {
    final texto = litros == litros.roundToDouble()
        ? litros.toStringAsFixed(0)
        : litros.toStringAsFixed(1);
    return texto.replaceAll('.', ',');
  }

  /// Lee un campo. null si esta vacio; double.nan si no es un numero valido.
  double? _leer(String id) {
    final texto = _campos[id]!.text.trim().replaceAll(',', '.');
    if (texto.isEmpty) return null;
    final v = double.tryParse(texto);
    // Mas de 80 L en un solo ordenio es un error de digitacion (un cero de
    // mas), no una vaca record. Se marca para corregir.
    if (v == null || v < 0 || v > 80) return double.nan;
    return v;
  }

  int get _faltan => _vacas.where((v) => _leer(v.id) == null).length;
  bool get _hayErrores => _vacas.any((v) => _leer(v.id)?.isNaN ?? false);
  int get _anotadas => _vacas.length - _faltan;

  Future<void> _elegirFecha() async {
    final hoy = DateTime.now();
    final dia = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: hoy.subtract(const Duration(days: 30)),
      lastDate: hoy,
    );
    if (dia == null || !mounted) return;
    _fecha = dia;
    _cargar();
  }

  Future<void> _guardar() async {
    if (_guardando || _hayErrores || _anotadas == 0) return;
    setState(() => _guardando = true);

    final registros = [
      for (final v in _vacas)
        if (_leer(v.id) != null)
          {
            'animal_id': v.id,
            'fecha': _fecha,
            'ordenio': _ordenio,
            'litros': _leer(v.id),
          },
    ];

    // Una sola transaccion para todo el ordenio (ver guardarLote).
    await _produccionDao.guardarLote(registros);

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ordeño')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(Medida.md),
            child: Column(
              children: [
                FilaFecha(
                  etiqueta: 'Día',
                  valor: fechaCorta(_fecha),
                  onTap: _elegirFecha,
                ),
                const SizedBox(height: Medida.sm),
                GrillaOpciones<int>(
                  valores: const [1, 2],
                  elegido: _ordenio,
                  etiqueta: (o) => o == 1 ? 'Mañana' : 'Tarde',
                  onElegir: (o) {
                    if (o == _ordenio) return;
                    _ordenio = o;
                    _cargar();
                  },
                ),
              ],
            ),
          ),
          if (!_cargando && _vacas.isNotEmpty) _contador(),
          Expanded(
            child: _cargando
                ? const Center(child: CircularProgressIndicator())
                : _vacas.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(Medida.lg),
                        child: Text(
                          'No hay vacas en ordeño. En el hato, las vacas '
                          'con categoría «Vaca en ordeño» aparecen aquí.',
                          style: Tipo.cuerpoSuave,
                        ),
                      )
                    : ListView.builder(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Medida.md),
                        itemCount: _vacas.length,
                        itemBuilder: (_, i) => _fila(i),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _vacas.isEmpty
          ? null
          : BarraInferior(
              hijos: [
                ElevatedButton(
                  onPressed: _guardando || _hayErrores || _anotadas == 0
                      ? null
                      : _guardar,
                  child: Text(_anotadas == 0
                      ? 'Guardar ordeño'
                      : 'Guardar ordeño ($_anotadas)'),
                ),
              ],
            ),
    );
  }

  Widget _contador() {
    final completo = _faltan == 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: Medida.md),
      padding: const EdgeInsets.all(Medida.sm),
      decoration: BoxDecoration(
        color: completo ? Colores.primarioClaro : Colores.atencionClaro,
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
      ),
      child: Text(
        completo
            ? 'Todas anotadas (${_vacas.length})'
            : 'Faltan $_faltan de ${_vacas.length}',
        style: Tipo.cuerpo.copyWith(
          fontWeight: FontWeight.w600,
          color: completo ? Colores.primario : Colores.atencion,
        ),
      ),
    );
  }

  Widget _fila(int i) {
    final v = _vacas[i];
    final ultima = i == _vacas.length - 1;
    final valor = _leer(v.id);

    return Container(
      constraints: const BoxConstraints(minHeight: Medida.toque + Medida.md),
      padding: const EdgeInsets.symmetric(vertical: Medida.xs),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colores.borde)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.areteInterno ?? '—',
                  style: Tipo.cuerpo.copyWith(fontWeight: FontWeight.w600),
                ),
                if (v.nombre != null) Text(v.nombre!, style: Tipo.apoyo),
              ],
            ),
          ),
          SizedBox(
            width: 130,
            child: TextField(
              controller: _campos[v.id],
              focusNode: _focos[v.id],
              style: Tipo.subtitulo,
              textAlign: TextAlign.end,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              // "Siguiente" salta a la vaca de abajo; en la ultima, cierra.
              textInputAction:
                  ultima ? TextInputAction.done : TextInputAction.next,
              onSubmitted: (_) {
                if (!ultima) _focos[_vacas[i + 1].id]!.requestFocus();
              },
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                suffixText: 'L',
                errorText: (valor?.isNaN ?? false) ? 'Revisar' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
