// =============================================================================
//  pantalla_inicio.dart
//  Lo que Jhon ve al abrir la app.
//
//  EL ORDEN DE LA PANTALLA NO ES CASUAL. Responde a: que necesita saber esta
//  persona ahora mismo, a las cinco de la maniana, antes de ordeniar.
//
//   1. RETIRO DE LECHE. Es lo unico que si se ignora cuesta dinero de verdad:
//      leche con antibiotico en el tanque arruina la entrega completa.
//      Va primero y en rojo.
//
//   2. CAIDAS DE PRODUCCION. Vacas que produjeron menos que su propio
//      promedio. Es el precursor del algoritmo de la Fase 3, funcionando hoy
//      sin ningun sensor.
//
//   3. CONTADOR DE ETIQEUTAS UTILES. No le sirve a Jhon para manejar la finca,
//      pero convierte un trabajo abstracto en un numero que sube. Es lo que
//      sostiene la motivacion durante los meses en que no hay collar todavia.
//
//   4. ACCESO A REGISTRAR. Grande y siempre visible.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/dao/evento_salud_dao.dart';
import '../data/dao/produccion_dao.dart';
import '../data/dao/tratamiento_dao.dart';
import '../data/models/finca.dart';
import '../data/models/produccion_leche.dart';
import 'comunes.dart';
import 'pantalla_animal.dart';
import 'pantalla_evento.dart';
import 'pantalla_hato.dart';
import 'pantalla_por_completar.dart';
import 'pantalla_produccion.dart';

class PantallaInicio extends StatefulWidget {
  final Finca finca;

  const PantallaInicio({super.key, required this.finca});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  final _tratamientoDao = TratamientoDao();
  final _produccionDao = ProduccionDao();
  final _saludDao = EventoSaludDao();
  final _animalDao = AnimalDao();

  List<AnimalEnRetiro> _enRetiro = [];
  List<CaidaProduccion> _caidas = [];
  int _etiquetasUtiles = 0;
  int _porCompletar = 0;
  int _animales = 0;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    // Las cuatro consultas se lanzan en paralelo con Future.wait en vez de una
    // tras otra. Son independientes entre si, y en serie la pantalla tardaria
    // la suma de las cuatro en vez de lo que tarda la mas lenta.
    final resultados = await Future.wait([
      _tratamientoDao.enRetiroLeche(widget.finca.id),
      _produccionDao.detectarCaidas(fincaId: widget.finca.id),
      _saludDao.totalEtiquetasUtiles(),
      _saludDao.incompletos(widget.finca.id),
      _animalDao.contarActivos(widget.finca.id),
    ]);

    if (!mounted) return;

    setState(() {
      // Future.wait devuelve List<dynamic>, asi que cada resultado se convierte
      // al tipo que le corresponde segun el orden en que se pidieron.
      _enRetiro = resultados[0] as List<AnimalEnRetiro>;
      _caidas = resultados[1] as List<CaidaProduccion>;
      _etiquetasUtiles = resultados[2] as int;
      _porCompletar = (resultados[3] as List).length;
      _animales = resultados[4] as int;
      _cargando = false;
    });
  }

  Future<void> _registrarCaso() async {
    final huboCambios = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PantallaEvento(fincaId: widget.finca.id),
      ),
    );

    // Si se guardo algo, se recargan los datos para que el contador suba de
    // inmediato. Ver el numero cambiar es parte del incentivo.
    if (huboCambios == true) _cargar();
  }

  /// Abre una pantalla y recarga el inicio si alli se guardo algo.
  Future<void> _abrir(Widget pantalla) async {
    final huboCambios = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => pantalla),
    );
    if (huboCambios == true) _cargar();
  }

  Future<void> _abrirHato() => _abrir(PantallaHato(fincaId: widget.finca.id));

  /// Abre la ficha de un animal de las alertas. Se busca por id porque las
  /// alertas traen solo el id y la etiqueta, no el animal completo.
  Future<void> _abrirAnimal(String animalId) async {
    final animal = await _animalDao.porId(animalId);
    if (animal == null || !mounted) return;
    await _abrir(PantallaAnimal(animal: animal));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.finca.nombre),
        actions: [
          // Con texto y no solo icono: un icono de lista no dice "mis vacas"
          // a quien no usa apps a diario.
          TextButton.icon(
            onPressed: _abrirHato,
            icon: const Icon(Icons.format_list_bulleted),
            label: Text(_animales > 0 ? 'Hato · $_animales' : 'Hato'),
          ),
          const SizedBox(width: Medida.sm),
        ],
      ),

      body: _cargando
          ? const Center(child: CircularProgressIndicator())

          // RefreshIndicator permite recargar deslizando hacia abajo, que es
          // el gesto que la gente ya conoce de otras apps.
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(Medida.md),
                children: [
                  // Sin animales no se puede registrar nada: es lo primero
                  // que hay que resolver, asi que va antes que todo.
                  if (_animales == 0) ...[
                    _bloqueHatoVacio(),
                    const SizedBox(height: Medida.lg),
                  ],

                  if (_enRetiro.isNotEmpty) ...[
                    _bloqueRetiro(),
                    const SizedBox(height: Medida.lg),
                  ],

                  if (_caidas.isNotEmpty) ...[
                    _bloqueCaidas(),
                    const SizedBox(height: Medida.lg),
                  ],

                  // Estado vacio: cuando no hay nada urgente, la pantalla no
                  // debe quedar en blanco ni disculparse. Confirma que todo
                  // esta en orden, que es informacion util.
                  if (_animales > 0 && _enRetiro.isEmpty && _caidas.isEmpty) ...[
                    _bloqueTodoEnOrden(),
                    const SizedBox(height: Medida.lg),
                  ],

                  _bloqueProgreso(),
                  const SizedBox(height: Medida.xl),
                ],
              ),
            ),

      // El boton de registrar vive abajo y siempre visible. Es la accion que
      // sostiene todo el proyecto: no puede estar escondida tras un menu.
      //
      // El ordenio va al lado, mas chico: se registra dos veces al dia, todos
      // los dias, y tenerlo a un toque es lo que hace que no se salte.
      bottomNavigationBar: BarraInferior(
        hijos: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: () =>
                      _abrir(PantallaProduccion(fincaId: widget.finca.id)),
                  child: const Text('Ordeño'),
                ),
              ),
              const SizedBox(width: Medida.sm),
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: _registrarCaso,
                  icon: const Icon(Icons.add),
                  label: const Text('Registrar caso'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  //  BLOQUES
  // ===========================================================================

  Widget _bloqueRetiro() {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: BoxDecoration(
        color: Colores.alertaClara,
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
        // Borde grueso solo a la izquierda: marca la urgencia sin encerrar el
        // contenido en una caja, que lo haria parecer una tarjeta mas.
        border: const Border(
          left: BorderSide(color: Colores.alerta, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No entregar esta leche',
            style: Tipo.subtitulo.copyWith(color: Colores.alerta),
          ),
          const SizedBox(height: Medida.xs),
          Text(
            '${_enRetiro.length} ${_enRetiro.length == 1 ? "vaca" : "vacas"} en periodo de retiro',
            style: Tipo.apoyo,
          ),
          const SizedBox(height: Medida.md),


          // Tocar una fila abre la ficha: ahi esta el caso y el tratamiento.
          ..._enRetiro.map((a) => InkWell(
              onTap: () => _abrirAnimal(a.animalId),
              child: Container(
                constraints: const BoxConstraints(minHeight: Medida.toque),
                padding: const EdgeInsets.only(bottom: Medida.sm),
                child: Row(
                  children: [
                    // El arete grande y a la izquierda: es el dato que el
                    // ordeniador tiene que reconocer de un vistazo mientras
                    // trabaja.
                    SizedBox(
                      width: 90,
                      child: Text(
                        a.etiquetaAnimal,
                        style: Tipo.cuerpo.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(a.farmaco, style: Tipo.cuerpoSuave),
                    ),
                    Text(
                      a.diasRestantes == 0
                          ? 'hoy'
                          : '${a.diasRestantes} ${a.diasRestantes == 1 ? "día" : "días"}',
                      style: Tipo.cuerpo.copyWith(
                        color: Colores.alerta,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ))),
        ],
      ),
    );
  }

  Widget _bloqueCaidas() {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: BoxDecoration(
        color: Colores.atencionClaro,
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
        border: const Border(
          left: BorderSide(color: Colores.atencion, width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Produjeron menos de lo normal',
            style: Tipo.subtitulo.copyWith(color: Colores.atencion),
          ),
          const SizedBox(height: Medida.xs),
          const Text(
            'Comparado con su propio promedio de la última semana',
            style: Tipo.apoyo,
          ),
          const SizedBox(height: Medida.md),

          ..._caidas.map((c) => InkWell(
              onTap: () => _abrirAnimal(c.animalId),
              child: Container(
                constraints: const BoxConstraints(minHeight: Medida.toque),
                padding: const EdgeInsets.only(bottom: Medida.sm),
                child: Row(
                  children: [
                    SizedBox(
                      width: 90,
                      child: Text(
                        c.etiquetaAnimal,
                        style: Tipo.cuerpo.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        // toStringAsFixed(1) deja un decimal. Sin el, un valor
                        // como 33.333333 llenaria la fila entera.
                        '${c.litrosHoy.toStringAsFixed(1)} L '
                        'de ${c.promedioAnterior.toStringAsFixed(1)} L',
                        style: Tipo.cuerpoSuave,
                      ),
                    ),
                    Text(
                      '−${c.caidaPorcentaje.round()} %',
                      style: Tipo.cuerpo.copyWith(
                        color: Colores.atencion,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ))),
        ],
      ),
    );
  }

  Widget _bloqueHatoVacio() {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: BoxDecoration(
        color: Colores.atencionClaro,
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Primero, carga tu hato', style: Tipo.subtitulo),
          const SizedBox(height: Medida.xs),
          const Text(
            'Para registrar un caso hay que elegir el animal. Agrega tus '
            'vacas una vez; se puede cargar varias seguidas.',
            style: Tipo.cuerpoSuave,
          ),
          const SizedBox(height: Medida.md),
          OutlinedButton.icon(
            onPressed: _abrirHato,
            icon: const Icon(Icons.add),
            label: const Text('Agregar animales'),
          ),
        ],
      ),
    );
  }

  Widget _bloqueTodoEnOrden() {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: BoxDecoration(
        color: Colores.primarioClaro,
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colores.primario),
          SizedBox(width: Medida.md),
          Expanded(
            child: Text(
              'Toda la leche se puede entregar y nadie bajó de producción.',
              style: Tipo.cuerpo,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bloqueProgreso() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Datos para el algoritmo', style: Tipo.subtitulo),
        const SizedBox(height: Medida.md),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_etiquetasUtiles', style: Tipo.cifra),
                  const SizedBox(height: Medida.xs),
                  const Text('casos completos', style: Tipo.apoyo),
                ],
              ),
            ),

            if (_porCompletar > 0)
              Expanded(
                // Tocable: la lista de casos a completar es el siguiente paso
                // natural despues de ver el numero.
                child: InkWell(
                  onTap: () =>
                      _abrir(PantallaPorCompletar(fincaId: widget.finca.id)),
                  borderRadius: BorderRadius.circular(Medida.bordeRadio),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$_porCompletar',
                        style: Tipo.cifra.copyWith(color: Colores.atencion),
                      ),
                      const SizedBox(height: Medida.xs),
                      Text(
                        'por completar ›',
                        style: Tipo.apoyo.copyWith(color: Colores.atencion),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        // El objetivo se nombra explicitamente. Un contador sin meta no motiva
        // a nadie; con meta se convierte en algo que se quiere alcanzar.
        const SizedBox(height: Medida.md),
        Text(
          _etiquetasUtiles < 25
              ? 'Faltan ${25 - _etiquetasUtiles} para tener con qué probar si el collar funciona.'
              : 'Ya hay suficientes casos para empezar a probar el collar.',
          style: Tipo.cuerpoSuave,
        ),
      ],
    );
  }
}
