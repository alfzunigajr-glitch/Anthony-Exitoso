// =============================================================================
//  main.dart
//  Punto de entrada.
//
//  Decide que mostrar al arrancar: si no hay finca configurada, la pantalla de
//  configuracion; si la hay, el inicio. Es la unica bifurcacion de arranque.
// =============================================================================

import 'package:flutter/material.dart';

import 'core/tema.dart';
import 'data/models/finca.dart';
import 'ui/pantalla_inicio.dart';

void main() {
  // ensureInitialized prepara el enlace con la plataforma antes de correr la
  // app. Hace falta porque la base de datos se abre durante el arranque, y sin
  // esta linea falla con un error que no menciona la base por ningun lado.
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const AppGanado());
}

class AppGanado extends StatelessWidget {
  const AppGanado({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Registro del hato',
      theme: construirTema(),

      // Oculta la cinta roja de "DEBUG" en la esquina. En el telefono de Jhon
      // solo genera dudas sobre si la app esta terminada.
      debugShowCheckedModeBanner: false,

      home: const _Arranque(),
    );
  }
}

/// Decide la primera pantalla segun si ya hay finca configurada.
class _Arranque extends StatefulWidget {
  const _Arranque();

  @override
  State<_Arranque> createState() => _ArranqueState();
}

class _ArranqueState extends State<_Arranque> {
  final _fincaDao = FincaDao();

  Finca? _finca;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _revisar();
  }

  Future<void> _revisar() async {
    // La primera llamada abre la base y ejecuta las migraciones. Puede tardar
    // un instante en el primer arranque; despues es inmediato.
    final finca = await _fincaDao.actual();

    if (!mounted) return;
    setState(() {
      _finca = finca;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_finca == null) {
      // onListo recarga el estado para pasar al inicio sin reiniciar la app.
      return _PantallaConfiguracion(onListo: _revisar);
    }

    return PantallaInicio(finca: _finca!);
  }
}

/// Configuracion inicial. Se muestra una sola vez, en el primer arranque.
///
/// Pide solo el nombre de la finca. Provincia, altitud y coordenadas se pueden
/// llenar despues: pedirlos aqui pondria cinco campos entre la persona y su
/// primer registro, y el primer registro es lo unico que importa ese dia.
class _PantallaConfiguracion extends StatefulWidget {
  final VoidCallback onListo;

  const _PantallaConfiguracion({required this.onListo});

  @override
  State<_PantallaConfiguracion> createState() => _PantallaConfiguracionState();
}

class _PantallaConfiguracionState extends State<_PantallaConfiguracion> {
  final _fincaDao = FincaDao();
  final _nombre = TextEditingController();
  final _propietario = TextEditingController();

  bool _guardando = false;

  @override
  void dispose() {
    _nombre.dispose();
    _propietario.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty || _guardando) return;

    setState(() => _guardando = true);

    await _fincaDao.crear(
      nombre: nombre,
      propietario: _propietario.text.trim().isEmpty
          ? null
          : _propietario.text.trim(),
    );

    widget.onListo();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Medida.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: Medida.xl),

              const Text('Registro del hato', style: Tipo.titulo),
              const SizedBox(height: Medida.sm),

              // El texto explica para que sirve la app en una linea, en
              // lenguaje de la persona que la va a usar. Nada de "plataforma"
              // ni "solucion".
              const Text(
                'Lleva el historial de cada animal y avisa cuándo no se puede '
                'entregar la leche.',
                style: Tipo.cuerpoSuave,
              ),

              const SizedBox(height: Medida.xl),

              TextField(
                controller: _nombre,
                autofocus: true,
                style: Tipo.cuerpo,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la finca',
                ),
                // Guarda al pulsar "listo" en el teclado, sin bajar al boton.
                onSubmitted: (_) => _guardar(),
              ),

              const SizedBox(height: Medida.md),

              TextField(
                controller: _propietario,
                style: Tipo.cuerpo,
                decoration: const InputDecoration(
                  labelText: 'Responsable (opcional)',
                ),
              ),

              const Spacer(),

              ElevatedButton(
                onPressed: _guardando ? null : _guardar,
                child: const Text('Empezar'),
              ),

              const SizedBox(height: Medida.md),
            ],
          ),
        ),
      ),
    );
  }
}
