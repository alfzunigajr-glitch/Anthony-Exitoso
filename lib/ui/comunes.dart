// =============================================================================
//  comunes.dart
//  Piezas de interfaz que se repiten entre pantallas.
//
//  POR QUE UN ARCHIVO COMUN: el boton de opcion grande, la fila de fecha y las
//  respuestas a "cuando empezo" aparecen en casi todos los formularios. Si
//  cada pantalla tuviera su copia, tarde o temprano una tendria 48 px en vez
//  de 56, o "Esta manana" significaria cosas distintas en dos pantallas, y
//  eso ultimo ensucia el dataset sin que nadie lo note.
// =============================================================================

import 'package:flutter/material.dart';

import '../core/tema.dart';
import '../data/models/evento_salud.dart' show PrecisionTs;

// =============================================================================
//  CUANDO EMPEZO
// =============================================================================

/// Respuesta a "cuando empezo", en lenguaje de campo.
///
/// Cada opcion traduce lo que la persona entiende a los dos datos que el
/// esquema necesita: la fecha y su precision (regla 7 de CLAUDE.md: la
/// precision se deduce, nunca se pregunta).
class MomentoInicio {
  final String etiqueta;

  /// Cuantas horas antes del momento de referencia se situa el inicio.
  /// Negativo significa "no se sabe".
  final int horasAtras;

  /// Precision que implica esa respuesta.
  final String precision;

  const MomentoInicio(this.etiqueta, this.horasAtras, this.precision);

  /// Opciones para un evento que se registra en el momento: "cuando empezo,
  /// contando desde ahora". De la mas reciente a la mas antigua.
  ///
  /// "Ahora mismo" da precision EXACTO porque la persona lo esta viendo.
  /// "Ayer" da +-1 dia, que sigue sirviendo para entrenar.
  /// "Hace 2 o 3 dias" da +-3 dias: se guarda, pero la vista de entrenamiento
  /// lo excluye. Es honesto y mejor que inventar una hora.
  static const opciones = [
    MomentoInicio('Ahora mismo', 0, PrecisionTs.exacto),
    MomentoInicio('Esta mañana', 6, PrecisionTs.masMenos6h),
    MomentoInicio('Ayer', 24, PrecisionTs.masMenos1d),
    MomentoInicio('Hace 2 o 3 días', 60, PrecisionTs.masMenos3d),
    MomentoInicio('No lo sé', -1, PrecisionTs.desconocido),
  ];

  /// Opciones para completar un caso YA registrado: "cuando empezo, contando
  /// desde que alguien lo noto". Mismas horas y precisiones que [opciones],
  /// con palabras que tienen sentido mirando hacia atras.
  static const opcionesDesdeDeteccion = [
    MomentoInicio('Cuando se notó', 0, PrecisionTs.exacto),
    MomentoInicio('Unas horas antes', 6, PrecisionTs.masMenos6h),
    MomentoInicio('El día anterior', 24, PrecisionTs.masMenos1d),
    MomentoInicio('2 o 3 días antes', 60, PrecisionTs.masMenos3d),
    MomentoInicio('No se sabe', -1, PrecisionTs.desconocido),
  ];

  /// Calcula la fecha real contando hacia atras desde [desde] (por defecto,
  /// ahora). Devuelve null para "No lo se": esa columna admite null y es
  /// preferible a guardar una fecha falsa.
  DateTime? calcularFecha({DateTime? desde}) {
    if (horasAtras < 0) return null;
    return (desde ?? DateTime.now()).subtract(Duration(hours: horasAtras));
  }
}

/// Lista de opciones de "cuando empezo", una por fila.
class SelectorMomento extends StatelessWidget {
  final List<MomentoInicio> opciones;
  final MomentoInicio? elegido;
  final ValueChanged<MomentoInicio> onElegir;

  const SelectorMomento({
    super.key,
    this.opciones = MomentoInicio.opciones,
    required this.elegido,
    required this.onElegir,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final m in opciones)
          Padding(
            padding: const EdgeInsets.only(bottom: Medida.sm),
            child: InkWell(
              onTap: () => onElegir(m),
              borderRadius: BorderRadius.circular(Medida.bordeRadio),
              child: Container(
                height: Medida.toque,
                padding: const EdgeInsets.symmetric(horizontal: Medida.md),
                decoration: BoxDecoration(
                  color: elegido == m
                      ? Colores.primarioClaro
                      : Colores.superficieAlta,
                  borderRadius: BorderRadius.circular(Medida.bordeRadio),
                  border: Border.all(
                    color: elegido == m ? Colores.primario : Colores.borde,
                    width: elegido == m ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      elegido == m
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color:
                          elegido == m ? Colores.primario : Colores.tintaSuave,
                    ),
                    const SizedBox(width: Medida.md),
                    Text(m.etiqueta, style: Tipo.cuerpo),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
//  BOTONES Y FILAS
// =============================================================================

/// Boton de eleccion grande. Relleno cuando esta elegido.
class Opcion extends StatelessWidget {
  final String texto;
  final bool elegida;
  final VoidCallback onTap;

  /// Alto del boton. Los diagnosticos usan [Medida.toqueGrande] porque sus
  /// nombres ocupan a veces dos lineas.
  final double alto;

  const Opcion({
    super.key,
    required this.texto,
    required this.elegida,
    required this.onTap,
    this.alto = Medida.toque,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Medida.bordeRadio),
      child: Container(
        height: alto,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Medida.sm),
        decoration: BoxDecoration(
          color: elegida ? Colores.primario : Colores.superficieAlta,
          borderRadius: BorderRadius.circular(Medida.bordeRadio),
          border: Border.all(
            color: elegida ? Colores.primario : Colores.borde,
            width: elegida ? 2 : 1,
          ),
        ),
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: Tipo.cuerpo.copyWith(
            color: elegida ? Colors.white : Colores.tinta,
            fontWeight: elegida ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

/// Opciones en dos columnas que se ajustan al ancho disponible.
///
/// LayoutBuilder da el ancho real del contenedor. Se usa en vez del ancho de
/// la pantalla para que las columnas cuadren tambien dentro de un marco mas
/// angosto o con el telefono de lado.
class GrillaOpciones<T> extends StatelessWidget {
  final List<T> valores;
  final T? elegido;
  final String Function(T) etiqueta;
  final ValueChanged<T> onElegir;
  final double alto;

  const GrillaOpciones({
    super.key,
    required this.valores,
    required this.elegido,
    required this.etiqueta,
    required this.onElegir,
    this.alto = Medida.toque,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, limites) {
        final ancho = (limites.maxWidth - Medida.sm) / 2;
        return Wrap(
          spacing: Medida.sm,
          runSpacing: Medida.sm,
          children: [
            for (final v in valores)
              SizedBox(
                width: ancho,
                child: Opcion(
                  texto: etiqueta(v),
                  elegida: elegido == v,
                  alto: alto,
                  onTap: () => onElegir(v),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Fila tocable que muestra un valor (una fecha, casi siempre) y abre un
/// selector al tocarla.
class FilaFecha extends StatelessWidget {
  final String etiqueta;
  final String valor;
  final VoidCallback onTap;

  const FilaFecha({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Medida.bordeRadio),
      child: Container(
        height: Medida.toque,
        padding: const EdgeInsets.symmetric(horizontal: Medida.md),
        decoration: BoxDecoration(
          color: Colores.superficieAlta,
          borderRadius: BorderRadius.circular(Medida.bordeRadio),
          border: Border.all(color: Colores.borde),
        ),
        child: Row(
          children: [
            Expanded(child: Text(etiqueta, style: Tipo.cuerpoSuave)),
            Text(valor, style: Tipo.cuerpo),
            const SizedBox(width: Medida.sm),
            const Icon(Icons.calendar_today_outlined,
                size: 20, color: Colores.tintaSuave),
          ],
        ),
      ),
    );
  }
}

/// Numero entero con botones de menos y mas.
///
/// POR QUE NO UN CAMPO DE TEXTO: los dias de retiro son numeros chicos que se
/// ajustan de uno en uno. Dos botones de 56 px se aciertan con guantes; el
/// teclado numerico tapa media pantalla y obliga a borrar antes de escribir.
class Contador extends StatelessWidget {
  final String etiqueta;
  final int valor;
  final int minimo;
  final int maximo;
  final ValueChanged<int> onCambio;

  const Contador({
    super.key,
    required this.etiqueta,
    required this.valor,
    required this.onCambio,
    this.minimo = 0,
    this.maximo = 99,
  });

  @override
  Widget build(BuildContext context) {
    Widget boton(IconData icono, int nuevo, String descripcion) {
      final activo = nuevo >= minimo && nuevo <= maximo;
      return SizedBox(
        width: Medida.toque,
        height: Medida.toque,
        child: OutlinedButton(
          onPressed: activo ? () => onCambio(nuevo) : null,
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(Medida.toque, Medida.toque),
          ),
          child: Icon(icono, semanticLabel: descripcion),
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: Text(etiqueta, style: Tipo.cuerpo)),
        boton(Icons.remove, valor - 1, 'Menos'),
        SizedBox(
          width: 56,
          child: Text(
            '$valor',
            textAlign: TextAlign.center,
            style: Tipo.subtitulo,
          ),
        ),
        boton(Icons.add, valor + 1, 'Más'),
      ],
    );
  }
}

/// Barra fija abajo con los botones de accion. Siempre al alcance del pulgar,
/// sin tener que recorrer el formulario.
class BarraInferior extends StatelessWidget {
  final List<Widget> hijos;

  const BarraInferior({super.key, required this.hijos});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Medida.md),
      decoration: const BoxDecoration(
        color: Colores.superficieAlta,
        border: Border(top: BorderSide(color: Colores.borde)),
      ),
      // SafeArea evita que los botones queden bajo la barra de gestos.
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: hijos,
        ),
      ),
    );
  }
}

/// Titulo de una seccion de formulario, con su separacion estandar.
class TituloSeccion extends StatelessWidget {
  final String texto;
  final String? apoyo;

  const TituloSeccion(this.texto, {super.key, this.apoyo});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Medida.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: Tipo.subtitulo),
          if (apoyo != null) ...[
            const SizedBox(height: Medida.xs),
            Text(apoyo!, style: Tipo.apoyo),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
//  FECHAS PARA MOSTRAR
// =============================================================================
//
// Se arman a mano porque DateFormat de intl necesita cargar los datos del
// idioma al arrancar la app solo para esto. Son SOLO para la pantalla: lo que
// se guarda pasa siempre por lib/core/fechas.dart (regla 3 de CLAUDE.md).

const _meses = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// '12 jun 2026'
String fechaCorta(DateTime f) => '${f.day} ${_meses[f.month - 1]} ${f.year}';

/// 'jue 12 jun, 06:30'. Lleva el dia de la semana porque para el retiro de
/// leche es lo que se recuerda: "hasta el jueves".
String fechaHora(DateTime f) {
  final hh = f.hour.toString().padLeft(2, '0');
  final mm = f.minute.toString().padLeft(2, '0');
  return '${_dias[f.weekday - 1]} ${f.day} ${_meses[f.month - 1]}, $hh:$mm';
}

/// 'hoy', 'ayer', 'hace 5 días' o la fecha, para listas de historial.
String haceCuanto(DateTime f, {DateTime? hoy}) {
  final h = hoy ?? DateTime.now();
  final dias = DateTime.utc(h.year, h.month, h.day)
      .difference(DateTime.utc(f.year, f.month, f.day))
      .inDays;
  if (dias == 0) return 'hoy';
  if (dias == 1) return 'ayer';
  if (dias > 1 && dias < 30) return 'hace $dias días';
  return fechaCorta(f);
}

/// Edad legible a partir de dias: '3 años', '8 meses', '12 días'.
String edadLegible(int dias) {
  if (dias >= 730) return '${dias ~/ 365} años';
  if (dias >= 365) return '1 año';
  if (dias >= 60) return '${dias ~/ 30} meses';
  return '$dias días';
}
