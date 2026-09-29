// =============================================================================
//  pantalla_hato.dart
//  Lista del hato con buscador. Tarea T2 de docs/alcance.md.
//
//  DOS ESTADOS QUE IMPORTAN:
//
//  1. HATO VACIO. Es lo primero que se ve despues de configurar la finca. No
//     puede quedar una lista en blanco: la pantalla dice que hacer y el boton
//     lleva directo a cargar el primer animal.
//
//  2. BUSQUEDA. Sin texto se muestra el hato activo (listarActivos). Con texto
//     se busca tambien entre los que ya salieron (buscar), marcados como
//     "fuera del hato": a veces hay que registrar algo de un animal vendido.
//
//  Tocar un animal abre su ficha (pantalla_animal).
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/models/animal.dart';
import 'pantalla_animal_nuevo.dart';
import 'pantalla_animal.dart';

class PantallaHato extends StatefulWidget {
  final String fincaId;

  const PantallaHato({super.key, required this.fincaId});

  @override
  State<PantallaHato> createState() => _PantallaHatoState();
}

class _PantallaHatoState extends State<PantallaHato> {
  final _animalDao = AnimalDao();
  final _buscador = TextEditingController();

  List<Animal> _animales = [];
  int _activos = 0;
  bool _cargando = true;

  /// Si algo cambio en esta visita (altas o casos registrados). Se devuelve
  /// al salir para que la pantalla de inicio recargue sus contadores.
  bool _huboCambios = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _buscador.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final texto = _buscador.text.trim();

    // Las dos consultas son independientes: se lanzan juntas.
    final resultados = await Future.wait([
      texto.isEmpty
          ? _animalDao.listarActivos(widget.fincaId)
          : _animalDao.buscar(widget.fincaId, texto),
      _animalDao.contarActivos(widget.fincaId),
    ]);

    if (!mounted) return;

    // Si el texto cambio mientras la consulta corria, este resultado ya es
    // viejo. Se descarta para que una respuesta lenta no pise a una nueva.
    if (_buscador.text.trim() != texto) return;

    setState(() {
      _animales = resultados[0] as List<Animal>;
      _activos = resultados[1] as int;
      _cargando = false;
    });
  }

  Future<void> _agregar() async {
    final hubo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PantallaAnimalNuevo(fincaId: widget.fincaId),
      ),
    );
    if (hubo == true) {
      _huboCambios = true;
      _cargar();
    }
  }

  Future<void> _abrirFicha(Animal animal) async {
    final hubo = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PantallaAnimal(animal: animal)),
    );
    if (hubo == true) {
      _huboCambios = true;
      // Un parto o un secado cambian la categoria que muestra la lista.
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
          title: Text(_cargando ? 'Hato' : 'Hato · $_activos'),
        ),
        body: _cargando
            ? const Center(child: CircularProgressIndicator())
            : (_activos == 0 && _buscador.text.trim().isEmpty)
                ? _estadoVacio()
                : _lista(),

        // Con el hato vacio el boton ya esta en el centro de la pantalla;
        // repetirlo abajo seria ruido.
        bottomNavigationBar: (_cargando || _activos == 0) ? null : _barraAgregar(),
      ),
    );
  }

  Widget _lista() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Medida.md, Medida.sm, Medida.md, Medida.sm),
          child: TextField(
            controller: _buscador,
            style: Tipo.cuerpo,
            decoration: const InputDecoration(
              hintText: 'Buscar por arete o nombre',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => _cargar(),
          ),
        ),
        Expanded(
          child: _animales.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(Medida.lg),
                  child: Text(
                    'Ningún animal coincide con «${_buscador.text.trim()}».',
                    style: Tipo.cuerpoSuave,
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: Medida.md),
                  itemCount: _animales.length,
                  itemBuilder: (_, i) => _fila(_animales[i]),
                ),
        ),
      ],
    );
  }

  Widget _fila(Animal a) {
    return InkWell(
      onTap: () => _abrirFicha(a),
      child: Container(
        constraints: const BoxConstraints(minHeight: Medida.toque),
        padding: const EdgeInsets.symmetric(
            horizontal: Medida.sm, vertical: Medida.sm),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colores.borde)),
        ),
        child: Row(
          children: [
            // Ancho fijo para el arete: asi los nombres quedan alineados en
            // columna y el ojo recorre la lista mas rapido.
            SizedBox(
              width: 80,
              child: Text(
                a.areteInterno ?? '—',
                style: Tipo.cuerpo.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a.nombre != null && a.nombre!.isNotEmpty)
                    Text(a.nombre!, style: Tipo.cuerpo),
                  Text(
                    a.activo
                        ? CategoriaAnimal.etiqueta(a.categoria)
                        : '${CategoriaAnimal.etiqueta(a.categoria)} · fuera del hato',
                    style: Tipo.apoyo,
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

  Widget _estadoVacio() {
    return Padding(
      padding: const EdgeInsets.all(Medida.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Todavía no hay animales', style: Tipo.titulo),
          const SizedBox(height: Medida.sm),
          const Text(
            'Carga el hato una vez y después registrar un caso es buscar el '
            'arete. Puedes agregar varios seguidos.',
            style: Tipo.cuerpoSuave,
          ),
          const SizedBox(height: Medida.lg),
          ElevatedButton.icon(
            onPressed: _agregar,
            icon: const Icon(Icons.add),
            label: const Text('Agregar el primer animal'),
          ),
        ],
      ),
    );
  }

  Widget _barraAgregar() {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: const BoxDecoration(
        color: Colores.superficieAlta,
        border: Border(top: BorderSide(color: Colores.borde)),
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton.icon(
          onPressed: _agregar,
          icon: const Icon(Icons.add),
          label: const Text('Agregar animal'),
        ),
      ),
    );
  }
}
