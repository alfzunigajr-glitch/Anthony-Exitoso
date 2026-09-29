// =============================================================================
//  tema.dart
//  Sistema visual de la app.
//
//  EL CONTEXTO DE USO MANDA SOBRE TODO:
//  esta app se usa a las cinco de la maniana, en la sala de ordenio, con las
//  manos mojadas y frias, con luz de establo o sol directo, en un telefono de
//  gama media. No es una app de escritorio ni de sofa.
//
//  De ahi salen las tres decisiones de fondo:
//   1. Contraste alto. Bajo sol directo, los grises claros desaparecen.
//   2. Areas de toque de 56 px, no los 48 por defecto de Material. Con dedos
//      frios o guantes, 48 falla y el usuario abandona.
//   3. Tipografia del sistema. Una fuente descargada falla la primera vez que
//      se abre la app sin senial, y en una finca de Sierra eso es lo normal,
//      no el caso raro.
// =============================================================================

import 'package:flutter/material.dart';

/// Paleta.
///
/// La referencia visual es un instrumento de medicion de campo, no una app de
/// consumo: colores que significan algo, ninguno decorativo.
class Colores {
  /// Fondo. Casi blanco con una pizca de verde para que no deslumbre bajo sol.
  static const superficie = Color(0xFFFBFBF9);

  /// Tarjetas y zonas elevadas.
  static const superficieAlta = Color(0xFFFFFFFF);

  /// Texto principal. Negro con base verde en vez de negro puro: mas suave a
  /// la vista en sesiones largas sin perder contraste.
  static const tinta = Color(0xFF16211C);

  /// Texto secundario. Todavia legible bajo sol; un gris mas claro no lo seria.
  static const tintaSuave = Color(0xFF5A6560);

  /// Verde de pastizal. Es el color de la accion principal.
  static const primario = Color(0xFF1F5D3F);
  static const primarioClaro = Color(0xFFE3EDE7);

  /// Ambar: dato incompleto, algo que se puede completar. No es un error.
  static const atencion = Color(0xFFB26B00);
  static const atencionClaro = Color(0xFFFBF0DC);

  /// Rojo tierra: retiro de leche y alertas que exigen accion hoy.
  static const alerta = Color(0xFF9E2B25);
  static const alertaClara = Color(0xFFF9E7E5);

  /// Bordes y separadores.
  static const borde = Color(0xFFDCDDD6);
}

/// Escala tipografica.
///
/// Empieza en 15 px y no en los 12-13 habituales: por debajo de eso, un texto
/// no se lee a un brazo de distancia con el telefono sobre una baranda.
class Tipo {
  static const _familia = null; // null = fuente del sistema (Roboto en Android)

  /// Numeros grandes: litros, dias restantes, contadores.
  static const cifra = TextStyle(
    fontFamily: _familia,
    fontSize: 34,
    fontWeight: FontWeight.w600,
    // Altura de linea ajustada para que los numeros no queden flotando.
    height: 1.1,
    color: Colores.tinta,
  );

  static const titulo = TextStyle(
    fontFamily: _familia,
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.25,
    color: Colores.tinta,
  );

  static const subtitulo = TextStyle(
    fontFamily: _familia,
    fontSize: 19,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: Colores.tinta,
  );

  /// Texto normal. 17 px es el minimo comodo para lectura en campo.
  static const cuerpo = TextStyle(
    fontFamily: _familia,
    fontSize: 17,
    height: 1.45,
    color: Colores.tinta,
  );

  static const cuerpoSuave = TextStyle(
    fontFamily: _familia,
    fontSize: 17,
    height: 1.45,
    color: Colores.tintaSuave,
  );

  /// Texto de apoyo: fechas, unidades, aclaraciones.
  static const apoyo = TextStyle(
    fontFamily: _familia,
    fontSize: 15,
    height: 1.4,
    color: Colores.tintaSuave,
  );

  /// Texto de boton. Peso alto porque va sobre color.
  static const boton = TextStyle(
    fontFamily: _familia,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
}

/// Medidas. Se centralizan para que el espaciado sea consistente sin tener
/// que recordar numeros sueltos en cada pantalla.
class Medida {
  /// Altura minima de cualquier cosa que se toque.
  ///
  /// Material recomienda 48. Aqui son 56 por el contexto: dedos frios, manos
  /// mojadas, telefono en movimiento. Los 8 px extra son la diferencia entre
  /// que el registro se complete o se abandone.
  static const toque = 56.0;

  /// Altura de los botones grandes de seleccion rapida (diagnostico, momento).
  static const toqueGrande = 72.0;

  static const bordeRadio = 10.0;

  // Escala de espaciado en pasos de 4. Usar solo estos valores evita el
  // desorden de tener 13, 15 y 17 px repartidos por la app.
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Construye el ThemeData de la app.
ThemeData construirTema() {
  return ThemeData(
    useMaterial3: true,

    // fromSeed genera una paleta completa a partir de un color base. Se fijan
    // a mano solo los valores que importan; el resto los deriva Material.
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colores.primario,
      primary: Colores.primario,
      surface: Colores.superficie,
      error: Colores.alerta,
    ),

    scaffoldBackgroundColor: Colores.superficie,

    appBarTheme: const AppBarTheme(
      backgroundColor: Colores.superficie,
      foregroundColor: Colores.tinta,
      elevation: 0,
      // scrolledUnderElevation a 0 evita que la barra cambie de color al hacer
      // scroll. Ese cambio distrae y no aporta informacion.
      scrolledUnderElevation: 0,
      titleTextStyle: Tipo.subtitulo,
      centerTitle: false,
    ),

    // Botones principales: altos, sin sombra, esquinas suaves.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colores.primario,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(Medida.toque),
        elevation: 0,
        textStyle: Tipo.boton,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medida.bordeRadio),
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colores.tinta,
        minimumSize: const Size.fromHeight(Medida.toque),
        side: const BorderSide(color: Colores.borde, width: 1.5),
        textStyle: Tipo.boton,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Medida.bordeRadio),
        ),
      ),
    ),

    // Botones de texto ("Cambiar", "Hato", "Ver todos"). Material los trae
    // con letra de 14 y 40 px de alto: por debajo del minimo de esta app.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Colores.primario,
        minimumSize: const Size(Medida.toque, Medida.toque),
        textStyle: Tipo.cuerpo.copyWith(fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colores.superficieAlta,
      // Padding generoso: el area de toque efectiva del campo crece con el.
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Medida.md,
        vertical: Medida.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
        borderSide: const BorderSide(color: Colores.borde),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
        borderSide: const BorderSide(color: Colores.borde),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Medida.bordeRadio),
        // Borde grueso al enfocar: el usuario tiene que ver de un vistazo
        // donde esta escribiendo, sin buscar el cursor.
        borderSide: const BorderSide(color: Colores.primario, width: 2),
      ),
      hintStyle: Tipo.cuerpoSuave,
    ),

    dividerTheme: const DividerThemeData(
      color: Colores.borde,
      thickness: 1,
      space: 1,
    ),

    // El indicador de carga hereda el verde de la app en vez del azul por
    // defecto de Material.
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Colores.primario,
    ),
  );
}
