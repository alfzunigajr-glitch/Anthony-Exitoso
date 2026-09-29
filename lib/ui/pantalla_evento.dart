// =============================================================================
//  pantalla_evento.dart
//  Registro de un evento sanitario.
//
//  ES LA PANTALLA MAS IMPORTANTE DE LA FASE 1. De ella depende la Compuerta 1:
//  si registrar un caso toma mas de treinta segundos, Jhon no lo hara, y sin
//  registro no hay dataset ni proyecto.
//
//  CUATRO DECISIONES DE DISENIO Y SU RAZON:
//
//  1. TODO EN UNA PANTALLA, sin navegacion.
//     Lo natural seria: lista de animales -> ficha -> boton -> formulario. Son
//     cuatro pasos. Aqui el animal se elige DENTRO del formulario, con
//     busqueda. Un paso.
//
//  2. EL USUARIO NUNCA ELIGE UNA "PRECISION".
//     El esquema necesita ts_inicio_estimado y precision_ts_inicio. Pedirlos
//     por separado, con un desplegable de cinco opciones tecnicas, es la forma
//     mas segura de que nadie los llene.
//     En vez de eso se pregunta CUANDO EMPEZO con botones en lenguaje normal
//     ("ahora", "esta maniana", "ayer"), y de esa eleccion se DEDUCEN las dos
//     columnas. El usuario responde una pregunta que entiende y la base recibe
//     el dato tecnico que necesita.
//
//  3. LOS DIAGNOSTICOS FRECUENTES, PRIMERO Y GRANDES.
//     Seis botones grandes cubren la mayoria de los casos reales. El catalogo
//     completo esta a un toque de distancia para lo demas.
//
//  4. SE PUEDE GUARDAR INCOMPLETO.
//     Un registro a medias es infinitamente mejor que ninguno: el caso queda
//     capturado y la app lo lista despues en "por completar". Exigir todos los
//     campos junto a la vaca garantiza que no se registre nada.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/fechas.dart';
import '../core/tema.dart';
import '../data/dao/animal_dao.dart';
import '../data/dao/evento_salud_dao.dart';
import '../data/models/animal.dart';
import '../data/models/diagnostico.dart';
import '../data/models/evento_salud.dart';

/// Opcion de "cuando empezo".
///
/// Cada opcion traduce lenguaje de campo a los dos campos que el esquema
/// necesita. Es el puente entre como piensa una persona y como guarda la base.
class _MomentoInicio {
  final String etiqueta;

  /// Cuantas horas atras se sitúa el inicio.
  final int horasAtras;

  /// Precision que implica esa respuesta.
  final String precision;

  const _MomentoInicio(this.etiqueta, this.horasAtras, this.precision);

  /// Las opciones, de mas reciente a mas antigua.
  ///
  /// "Ahora mismo" da precision EXACTO porque el usuario lo esta viendo.
  /// "Ayer" da +-1 dia, que sigue sirviendo para entrenar.
  /// "Hace varios dias" da +-3 dias: se guarda, pero la vista de entrenamiento
  /// lo excluye. Es honesto y mejor que inventar una hora.
  static const opciones = [
    _MomentoInicio('Ahora mismo', 0, PrecisionTs.exacto),
    _MomentoInicio('Esta mañana', 6, PrecisionTs.masMenos6h),
    _MomentoInicio('Ayer', 24, PrecisionTs.masMenos1d),
    _MomentoInicio('Hace 2 o 3 días', 60, PrecisionTs.masMenos3d),
    _MomentoInicio('No lo sé', -1, PrecisionTs.desconocido),
  ];

  /// Calcula la fecha real. Devuelve null para "No lo sé": esa columna admite
  /// null y es preferible a guardar una fecha falsa.
  DateTime? calcularFecha() {
    if (horasAtras < 0) return null;
    return DateTime.now().subtract(Duration(hours: horasAtras));
  }
}

class PantallaEvento extends StatefulWidget {
  final String fincaId;

  /// Animal preseleccionado. Llega con valor cuando se entra desde la ficha
  /// de un animal, y en null cuando se entra desde el boton general.
  final Animal? animalInicial;

  const PantallaEvento({
    super.key,
    required this.fincaId,
    this.animalInicial,
  });

  @override
  State<PantallaEvento> createState() => _PantallaEventoState();
}

class _PantallaEventoState extends State<PantallaEvento> {
  final _animalDao = AnimalDao();
  final _saludDao = EventoSaludDao();
  final _diagnosticoDao = DiagnosticoDao();

  // Controla el campo de busqueda de animal.
  final _buscador = TextEditingController();

  // ---- Estado del formulario -----------------------------------------------
  Animal? _animal;
  String? _codigoDiagnostico;
  _MomentoInicio? _momento;
  bool _confirmado = false;
  int? _severidad;
  final _notas = TextEditingController();

  // ---- Estado de la interfaz -----------------------------------------------
  List<Animal> _resultados = [];
  List<Diagnostico> _catalogo = [];
  bool _mostrarCatalogoCompleto = false;
  bool _guardando = false;

  /// Diagnosticos que se muestran como botones grandes.
  ///
  /// Esta lista deberia AJUSTARSE con los datos reales de Jhon una vez que
  /// haya un par de meses de registro: los seis mas frecuentes de su finca,
  /// no los seis que parecen mas comunes en general.
  static const _frecuentes = [
    'MAST_CLIN', 'COJERA', 'DIARREA', 'NEUMONIA', 'METRITIS', 'RET_PLAC',
  ];

  @override
  void initState() {
    super.initState();
    _animal = widget.animalInicial;
    _cargarCatalogo();
  }

  @override
  void dispose() {
    // Los controladores retienen memoria si no se liberan al cerrar la
    // pantalla. Olvidarlo es una fuga silenciosa que se nota tras un rato
    // de uso continuo.
    _buscador.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _cargarCatalogo() async {
    final lista = await _diagnosticoDao.listar();

    // mounted comprueba que la pantalla siga en el arbol. Si el usuario la
    // cerro mientras la consulta estaba en curso, llamar a setState lanzaria
    // una excepcion.
    if (!mounted) return;
    setState(() => _catalogo = lista);
  }

  Future<void> _buscarAnimal(String texto) async {
    if (texto.trim().isEmpty) {
      setState(() => _resultados = []);
      return;
    }

    final encontrados = await _animalDao.buscar(widget.fincaId, texto);
    if (!mounted) return;
    setState(() => _resultados = encontrados);
  }

  /// Si el formulario tiene lo minimo para guardar.
  ///
  /// Solo se exigen dos cosas: que animal y que le pasa. Todo lo demas puede
  /// completarse despues desde la lista de "por completar".
  bool get _puedeGuardar => _animal != null && _codigoDiagnostico != null;

  /// Si el registro va a servir como etiqueta de entrenamiento.
  /// Replica la logica de EventoSalud.sirveParaEntrenar para poder mostrarla
  /// ANTES de guardar.
  bool get _servira =>
      _confirmado &&
      _momento != null &&
      PrecisionTs.utilesParaEntrenar.contains(_momento!.precision);

  Future<void> _guardar() async {
    if (!_puedeGuardar || _guardando) return;

    setState(() => _guardando = true);

    final ahoraFecha = DateTime.now();
    final inicio = _momento?.calcularFecha();

    // Antes de guardar, se busca si ya hay un caso parecido.
    //
    // EL ESCENARIO QUE ESTO EVITA: Anthony registra la mastitis de la vaca 18
    // el martes y Jhon la registra el miercoles sin saber que ya estaba. Dos
    // filas para un solo episodio, y el conteo de etiquetas queda inflado.
    final duplicados = await _saludDao.buscarPosiblesDuplicados(
      animalId: _animal!.id,
      diagnosticoCodigo: _codigoDiagnostico!,
      fechaDeteccion: ahoraFecha,
    );

    if (duplicados.isNotEmpty && mounted) {
      // No se bloquea: una vaca SI puede enfermarse dos veces en un mes. Se
      // pregunta y decide la persona.
      final continuar = await _preguntarDuplicado(duplicados.first);
      if (continuar != true) {
        setState(() => _guardando = false);
        return;
      }
    }

    await _saludDao.crear(
      animalId: _animal!.id,
      diagnosticoCodigo: _codigoDiagnostico!,
      tsInicioEstimado: inicio,

      // ts_deteccion_humana es AHORA: el momento en que la persona lo esta
      // reportando. Es la marca contra la que se medira el collar.
      tsDeteccionHumana: ahoraFecha,

      precisionTsInicio: _momento?.precision ?? PrecisionTs.desconocido,
      metodoDiagnostico: _confirmado
          ? MetodoDiagnostico.clinico
          : MetodoDiagnostico.presuntivo,
      confirmado: _confirmado,
      severidad: _severidad,
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
    );

    if (!mounted) return;

    // pop(true) devuelve un valor a la pantalla anterior para que sepa que
    // hubo cambios y refresque su lista.
    Navigator.of(context).pop(true);
  }

  Future<bool?> _preguntarDuplicado(PosibleDuplicado d) {
    final dias = d.diasDeDiferencia.round();

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Es el mismo caso?'),
        content: Text(
          'Ya hay un registro de este diagnóstico en '
          '${_animal!.etiqueta} hace $dias ${dias == 1 ? "día" : "días"}.\n\n'
          'Si es el mismo episodio, cancela y edita el registro anterior. '
          'Si es un caso nuevo, continúa.',
          style: Tipo.cuerpo,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Es un caso nuevo'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registrar caso')),

      body: ListView(
        padding: const EdgeInsets.all(Medida.md),
        children: [
          _seccionAnimal(),
          const SizedBox(height: Medida.lg),

          // El resto del formulario aparece solo cuando hay animal elegido.
          // Mostrarlo todo de golpe abruma; asi la pantalla guia el orden.
          if (_animal != null) ...[
            _seccionDiagnostico(),
            const SizedBox(height: Medida.lg),
            _seccionMomento(),
            const SizedBox(height: Medida.lg),
            _seccionConfirmacion(),
            const SizedBox(height: Medida.lg),
            _seccionNotas(),
            const SizedBox(height: Medida.xl),
          ],
        ],
      ),

      // El boton de guardar vive fijo abajo, no al final del scroll: siempre
      // alcanzable con el pulgar sin tener que recorrer la pantalla.
      bottomNavigationBar: _barraGuardar(),
    );
  }

  // ===========================================================================
  //  SECCIONES
  // ===========================================================================

  Widget _seccionAnimal() {
    // Ya hay animal elegido: se muestra compacto con opcion de cambiarlo.
    if (_animal != null) {
      return Container(
        padding: const EdgeInsets.all(Medida.md),
        decoration: BoxDecoration(
          color: Colores.primarioClaro,
          borderRadius: BorderRadius.circular(Medida.bordeRadio),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_animal!.etiqueta, style: Tipo.subtitulo),
                  Text(_animal!.categoria.replaceAll('_', ' ').toLowerCase(),
                      style: Tipo.apoyo),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _animal = null;
                _buscador.clear();
                _resultados = [];
              }),
              child: const Text('Cambiar'),
            ),
          ],
        ),
      );
    }

    // Sin animal: buscador con foco automatico.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Qué animal?', style: Tipo.subtitulo),
        const SizedBox(height: Medida.sm),

        TextField(
          controller: _buscador,

          // El teclado se abre solo al entrar. Ahorra un toque, y en una
          // pantalla que apunta a treinta segundos cada toque cuenta.
          autofocus: true,

          // El teclado numerico aparece primero porque casi todos los aretes
          // son numeros, pero deja escribir letras para buscar por nombre.
          keyboardType: TextInputType.text,

          style: Tipo.cuerpo,
          decoration: const InputDecoration(
            hintText: 'Número de arete o nombre',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: _buscarAnimal,
        ),

        const SizedBox(height: Medida.sm),

        // Resultados de la busqueda, como filas altas y tocables.
        ..._resultados.map((a) => InkWell(
              onTap: () => setState(() {
                _animal = a;
                _resultados = [];

                // Se cierra el teclado: ya no hace falta y tapa media pantalla.
                FocusScope.of(context).unfocus();
              }),
              child: Container(
                height: Medida.toque,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: Medida.sm),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colores.borde)),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(a.etiqueta, style: Tipo.cuerpo)),
                    if (!a.activo)
                      Text('fuera del hato', style: Tipo.apoyo),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  Widget _seccionDiagnostico() {
    // Se filtra el catalogo dejando solo los frecuentes, en el orden definido
    // arriba y no en el orden en que vengan de la base.
    final frecuentes = _frecuentes
        .map((c) => _catalogo.where((d) => d.codigo == c))
        .expand((e) => e)
        .toList();

    final mostrados = _mostrarCatalogoCompleto ? _catalogo : frecuentes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Qué le pasa?', style: Tipo.subtitulo),
        const SizedBox(height: Medida.sm),

        // Wrap acomoda los botones en filas y salta de linea solo cuando hace
        // falta. Se adapta a cualquier ancho de pantalla sin calculos.
        Wrap(
          spacing: Medida.sm,
          runSpacing: Medida.sm,
          children: mostrados.map((d) {
            final elegido = _codigoDiagnostico == d.codigo;

            return InkWell(
              onTap: () => setState(() => _codigoDiagnostico = d.codigo),
              borderRadius: BorderRadius.circular(Medida.bordeRadio),
              child: Container(
                // Ancho fijo en dos columnas: se calcula restando el padding
                // de la pantalla y el espacio entre botones.
                width: (MediaQuery.of(context).size.width -
                        Medida.md * 2 -
                        Medida.sm) /
                    2,
                height: Medida.toqueGrande,
                padding: const EdgeInsets.all(Medida.sm),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: elegido ? Colores.primario : Colores.superficieAlta,
                  borderRadius: BorderRadius.circular(Medida.bordeRadio),
                  border: Border.all(
                    color: elegido ? Colores.primario : Colores.borde,
                    width: elegido ? 2 : 1,
                  ),
                ),
                child: Text(
                  d.nombre,
                  textAlign: TextAlign.center,
                  style: Tipo.cuerpo.copyWith(
                    color: elegido ? Colors.white : Colores.tinta,
                    fontWeight: elegido ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        if (!_mostrarCatalogoCompleto) ...[
          const SizedBox(height: Medida.sm),
          TextButton(
            onPressed: () => setState(() => _mostrarCatalogoCompleto = true),
            child: const Text('Ver todos los diagnósticos'),
          ),
        ],
      ],
    );
  }

  Widget _seccionMomento() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('¿Cuándo empezó?', style: Tipo.subtitulo),
        const SizedBox(height: Medida.xs),

        // Este texto de apoyo es importante: autoriza explicitamente a no
        // saber. Sin el, la gente inventa una fecha para "quedar bien" con el
        // formulario, y entrenar con una fecha inventada es peor que no tener
        // el dato.
        Text(
          'Tu mejor estimación. Si no lo sabes, dilo: es mejor que adivinar.',
          style: Tipo.apoyo,
        ),
        const SizedBox(height: Medida.sm),

        ..._MomentoInicio.opciones.map((m) {
          final elegido = _momento == m;

          return Padding(
            padding: const EdgeInsets.only(bottom: Medida.sm),
            child: InkWell(
              onTap: () => setState(() => _momento = m),
              borderRadius: BorderRadius.circular(Medida.bordeRadio),
              child: Container(
                height: Medida.toque,
                padding: const EdgeInsets.symmetric(horizontal: Medida.md),
                decoration: BoxDecoration(
                  color: elegido ? Colores.primarioClaro : Colores.superficieAlta,
                  borderRadius: BorderRadius.circular(Medida.bordeRadio),
                  border: Border.all(
                    color: elegido ? Colores.primario : Colores.borde,
                    width: elegido ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      elegido
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: elegido ? Colores.primario : Colores.tintaSuave,
                    ),
                    const SizedBox(width: Medida.md),
                    Text(m.etiqueta, style: Tipo.cuerpo),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _seccionConfirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // SwitchListTile trae su propia area de toque grande y el texto es
        // parte de ella: no hay que apuntar al interruptor.
        SwitchListTile(
          value: _confirmado,
          onChanged: (v) => setState(() => _confirmado = v),
          title: Text('Diagnóstico confirmado', style: Tipo.cuerpo),
          subtitle: Text(
            'Actívalo solo si lo revisaste como veterinario',
            style: Tipo.apoyo,
          ),
          activeColor: Colores.primario,
          contentPadding: EdgeInsets.zero,
        ),

        // La severidad solo aparece si esta confirmado: sin confirmacion, el
        // dato no se va a usar y pedirlo seria un campo de mas.
        if (_confirmado) ...[
          const SizedBox(height: Medida.sm),
          Text('Gravedad', style: Tipo.cuerpo),
          const SizedBox(height: Medida.sm),
          Row(
            children: [1, 2, 3].map((n) {
              final elegido = _severidad == n;
              const nombres = {1: 'Leve', 2: 'Moderado', 3: 'Grave'};

              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: n < 3 ? Medida.sm : 0),
                  child: InkWell(
                    onTap: () => setState(() => _severidad = n),
                    borderRadius: BorderRadius.circular(Medida.bordeRadio),
                    child: Container(
                      height: Medida.toque,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: elegido
                            ? Colores.primarioClaro
                            : Colores.superficieAlta,
                        borderRadius: BorderRadius.circular(Medida.bordeRadio),
                        border: Border.all(
                          color: elegido ? Colores.primario : Colores.borde,
                          width: elegido ? 2 : 1,
                        ),
                      ),
                      child: Text(nombres[n]!, style: Tipo.cuerpo),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Widget _seccionNotas() {
    return TextField(
      controller: _notas,
      maxLines: 3,
      style: Tipo.cuerpo,
      decoration: const InputDecoration(
        labelText: 'Notas (opcional)',
        hintText: 'Lo que quieras recordar de este caso',
      ),
    );
  }

  Widget _barraGuardar() {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: const BoxDecoration(
        color: Colores.superficieAlta,
        border: Border(top: BorderSide(color: Colores.borde)),
      ),
      // SafeArea evita que el boton quede bajo la barra de gestos del sistema.
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Indicador de si el registro servira para entrenar.
            //
            // POR QUE ESTA AQUI: convierte un requisito abstracto en algo
            // visible. Ver el mensaje cambiar a "sirve para el algoritmo" al
            // activar la confirmacion ensenia, sin explicar nada, por que ese
            // interruptor importa. Es el mejor incentivo posible para que el
            // registro se haga completo.
            if (_puedeGuardar)
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
                            ? 'Este caso sirve para entrenar el algoritmo'
                            : 'Se guarda igual. Puedes completarlo después.',
                        style: Tipo.apoyo.copyWith(
                          color: _servira ? Colores.primario : Colores.atencion,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            ElevatedButton(
              // onPressed en null deja el boton deshabilitado y gris.
              onPressed: _puedeGuardar && !_guardando ? _guardar : null,
              child: _guardando
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Guardar caso'),
            ),
          ],
        ),
      ),
    );
  }
}
