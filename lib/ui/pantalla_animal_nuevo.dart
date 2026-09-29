// =============================================================================
//  pantalla_animal_nuevo.dart
//  Alta de un animal. Tarea T1 de docs/alcance.md.
//
//  PARA QUE SE USA DE VERDAD: cargar el hato completo la primera vez, unos
//  treinta animales seguidos. Por eso el formulario esta pensado para repetir:
//
//  1. SOLO CUATRO DATOS OBLIGATORIOS: arete, sexo, categoria e ingreso.
//     Lo demas va plegado en "Mas datos". Cada campo visible de mas es una
//     razon para dejar la carga del hato para otro dia.
//
//  2. "GUARDAR Y AGREGAR OTRO" ES EL BOTON PRINCIPAL.
//     Al guardar se conservan sexo, categoria, raza y fecha de ingreso, que
//     casi siempre se repiten de un animal al siguiente, y el cursor vuelve al
//     arete. Cargar el siguiente animal es escribir un numero y tocar un boton.
//
//  3. EL SEXO VA ANTES QUE LA CATEGORIA y la filtra: una hembra ve cinco
//     categorias, un macho dos. Ademas hace imposible guardar un toro hembra.
//
//  4. EL ARETE REPETIDO SE EXPLICA JUNTO AL CAMPO, no con un error generico.
//     La base lo rechaza por la restriccion UNIQUE; la pantalla solo lo dice.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/models/animal.dart';
import 'comunes.dart';

class PantallaAnimalNuevo extends StatefulWidget {
  final String fincaId;

  const PantallaAnimalNuevo({super.key, required this.fincaId});

  @override
  State<PantallaAnimalNuevo> createState() => _PantallaAnimalNuevoState();
}

class _PantallaAnimalNuevoState extends State<PantallaAnimalNuevo> {
  final _animalDao = AnimalDao();

  final _arete = TextEditingController();
  final _nombre = TextEditingController();
  final _areteOficial = TextEditingController();

  // El foco del arete se guarda para devolverlo alli despues de cada guardado.
  final _focoArete = FocusNode();

  // ---- Estado del formulario -----------------------------------------------
  String? _sexo;
  String? _categoria;
  String? _raza;
  DateTime _fechaIngreso = DateTime.now();
  DateTime? _fechaNacimiento;
  bool _nacimientoEstimado = false;

  // ---- Estado de la interfaz -----------------------------------------------
  bool _masDatos = false;
  bool _guardando = false;
  String? _errorArete;

  /// Cuantos animales se guardaron en esta visita. Si es mas de cero, al salir
  /// se avisa a la pantalla anterior para que recargue su lista.
  int _guardados = 0;

  @override
  void dispose() {
    _arete.dispose();
    _nombre.dispose();
    _areteOficial.dispose();
    _focoArete.dispose();
    super.dispose();
  }

  /// Arete normalizado: sin espacios y en mayusculas. La restriccion UNIQUE
  /// distingue 'v-18' de 'V-18'; sin esto se colarian duplicados que para
  /// una persona son el mismo arete.
  String get _areteLimpio => _arete.text.trim().toUpperCase();

  bool get _completo =>
      _areteLimpio.isNotEmpty && _sexo != null && _categoria != null;

  Future<void> _guardar({required bool otro}) async {
    if (!_completo || _guardando) return;

    setState(() {
      _guardando = true;
      _errorArete = null;
    });

    final arete = _areteLimpio;
    final nombre = _nombre.text.trim();
    final oficial = _areteOficial.text.trim();

    try {
      await _animalDao.crear(
        fincaId: widget.fincaId,
        sexo: _sexo!,
        categoria: _categoria!,
        fechaIngreso: _fechaIngreso,
        areteInterno: arete,
        nombre: nombre.isEmpty ? null : nombre,
        areteOficial: oficial.isEmpty ? null : oficial,
        raza: _raza,
        fechaNacimiento: _fechaNacimiento,
        nacimientoEstimado: _fechaNacimiento != null && _nacimientoEstimado,
      );
    } on AreteRepetido {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorArete = 'Ya hay un animal con el arete $arete en esta finca.';
      });
      _focoArete.requestFocus();
      return;
    }

    if (!mounted) return;
    _guardados++;

    if (!otro) {
      Navigator.of(context).pop(true);
      return;
    }

    // Se limpia solo lo que cambia de un animal a otro. Sexo, categoria, raza
    // e ingreso se conservan: al cargar el hato suelen repetirse.
    setState(() {
      _guardando = false;
      _arete.clear();
      _nombre.clear();
      _areteOficial.clear();
      _fechaNacimiento = null;
      _nacimientoEstimado = false;
    });
    _focoArete.requestFocus();

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          '$arete guardado. '
          '${_guardados == 1 ? "1 animal" : "$_guardados animales"} en esta carga.',
          style: Tipo.cuerpo.copyWith(color: Colors.white),
        ),
        duration: const Duration(seconds: 2),
      ));
  }

  Future<void> _elegirFecha({required bool ingreso}) async {
    final hoy = DateTime.now();
    final elegida = await showDatePicker(
      context: context,
      initialDate: ingreso ? _fechaIngreso : (_fechaNacimiento ?? hoy),
      // Ninguna vaca del hato actual nacio hace mas de 25 anios.
      firstDate: DateTime(hoy.year - 25),
      // No se puede ingresar ni nacer en el futuro.
      lastDate: hoy,
    );
    if (elegida == null || !mounted) return;
    setState(() {
      if (ingreso) {
        _fechaIngreso = elegida;
      } else {
        _fechaNacimiento = elegida;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // PopScope intercepta la flecha y el gesto de volver para devolver si se
    // guardo algo. Sin esto, la lista del hato no se enteraria y seguiria
    // mostrando el hato viejo.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_guardados > 0);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Nuevo animal')),
        body: ListView(
          padding: const EdgeInsets.all(Medida.md),
          children: [
            _seccionArete(),
            const SizedBox(height: Medida.lg),
            _seccionSexo(),
            if (_sexo != null) ...[
              const SizedBox(height: Medida.lg),
              _seccionCategoria(),
            ],
            const SizedBox(height: Medida.lg),
            _seccionIngreso(),
            const SizedBox(height: Medida.md),
            _seccionMasDatos(),
            const SizedBox(height: Medida.xl),
          ],
        ),
        bottomNavigationBar: _barraGuardar(),
      ),
    );
  }

  // ===========================================================================
  //  SECCIONES
  // ===========================================================================

  Widget _seccionArete() {
    return TextField(
      controller: _arete,
      focusNode: _focoArete,
      autofocus: true,
      style: Tipo.cuerpo,
      // Mayusculas en el teclado: los aretes internos suelen llevar letras
      // como V-18 o T-04.
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'Arete de la finca',
        hintText: 'Ej. V-18',
        errorText: _errorArete,
        errorMaxLines: 2,
      ),
      // Al corregir el arete, el aviso de repetido deja de aplicar.
      onChanged: (_) => setState(() => _errorArete = null),
    );
  }

  Widget _seccionSexo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Sexo', style: Tipo.subtitulo),
        const SizedBox(height: Medida.sm),
        Row(
          children: [
            Expanded(
              child: Opcion(
                texto: 'Hembra',
                elegida: _sexo == Sexo.hembra,
                onTap: () => _elegirSexo(Sexo.hembra),
              ),
            ),
            const SizedBox(width: Medida.sm),
            Expanded(
              child: Opcion(
                texto: 'Macho',
                elegida: _sexo == Sexo.macho,
                onTap: () => _elegirSexo(Sexo.macho),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _elegirSexo(String sexo) {
    setState(() {
      _sexo = sexo;
      // Si la categoria elegida no corresponde al sexo nuevo, se borra en vez
      // de dejar una combinacion imposible escondida.
      if (!CategoriaAnimal.paraSexo(sexo).contains(_categoria)) {
        _categoria = null;
      }
    });
  }

  Widget _seccionCategoria() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Categoría', style: Tipo.subtitulo),
        const SizedBox(height: Medida.sm),
        // LayoutBuilder da el ancho real disponible. Se usa en vez del ancho
        // de la pantalla para que las dos columnas cuadren tambien dentro de
        // un marco mas angosto.
        LayoutBuilder(
          builder: (context, limites) {
            final ancho = (limites.maxWidth - Medida.sm) / 2;
            return Wrap(
              spacing: Medida.sm,
              runSpacing: Medida.sm,
              children: [
                for (final c in CategoriaAnimal.paraSexo(_sexo!))
                  SizedBox(
                    width: ancho,
                    child: Opcion(
                      texto: CategoriaAnimal.etiqueta(c),
                      elegida: _categoria == c,
                      onTap: () => setState(() => _categoria = c),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _seccionIngreso() {
    return FilaFecha(
      etiqueta: 'Llegó a la finca',
      valor: fechaCorta(_fechaIngreso),
      onTap: () => _elegirFecha(ingreso: true),
    );
  }

  Widget _seccionMasDatos() {
    if (!_masDatos) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _masDatos = true),
          icon: const Icon(Icons.expand_more),
          label: const Text('Más datos (opcional)'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _nombre,
          style: Tipo.cuerpo,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        const SizedBox(height: Medida.md),
        TextField(
          controller: _areteOficial,
          style: Tipo.cuerpo,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Arete oficial (Agrocalidad)',
          ),
        ),
        const SizedBox(height: Medida.lg),

        const Text('Raza', style: Tipo.subtitulo),
        const SizedBox(height: Medida.sm),
        Wrap(
          spacing: Medida.sm,
          runSpacing: Medida.sm,
          children: [
            for (final r in Raza.todas)
              ChoiceChip(
                label: Text(Raza.etiqueta(r), style: Tipo.cuerpo),
                selected: _raza == r,
                // Tocar la raza elegida la quita: es un dato opcional y tiene
                // que poder volver a quedar vacio.
                onSelected: (si) => setState(() => _raza = si ? r : null),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(
                  horizontal: Medida.sm,
                  vertical: Medida.sm,
                ),
              ),
          ],
        ),
        const SizedBox(height: Medida.lg),

        FilaFecha(
          etiqueta: 'Nacimiento',
          valor: _fechaNacimiento == null
              ? 'Sin dato'
              : fechaCorta(_fechaNacimiento!),
          onTap: () => _elegirFecha(ingreso: false),
        ),

        // El interruptor solo tiene sentido si hay fecha. Mostrarlo sin fecha
        // invitaria a marcar "aproximada" sobre nada.
        if (_fechaNacimiento != null)
          SwitchListTile(
            value: _nacimientoEstimado,
            onChanged: (v) => setState(() => _nacimientoEstimado = v),
            title: const Text('La fecha es aproximada', style: Tipo.cuerpo),
            subtitle: const Text(
              'Actívalo si la calculaste a ojo',
              style: Tipo.apoyo,
            ),
            activeThumbColor: Colores.primario,
            contentPadding: EdgeInsets.zero,
          ),
      ],
    );
  }

  Widget _barraGuardar() {
    final habilitado = _completo && !_guardando;

    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: const BoxDecoration(
        color: Colores.superficieAlta,
        border: Border(top: BorderSide(color: Colores.borde)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: habilitado ? () => _guardar(otro: true) : null,
              child: const Text('Guardar y agregar otro'),
            ),
            const SizedBox(height: Medida.sm),
            OutlinedButton(
              onPressed: habilitado ? () => _guardar(otro: false) : null,
              child: const Text('Guardar y terminar'),
            ),
          ],
        ),
      ),
    );
  }
}
