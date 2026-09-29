// Plantilla de arranque. flutter build reemplaza las dos marcas {{...}} por el
// cargador de Flutter y la configuracion de la compilacion.
//
// Se personaliza solo para dibujar la app dentro de #app y no a pantalla
// completa: asi queda espacio para la barra de "version de prueba" de arriba.
{{flutter_js}}
{{flutter_build_config}}

(function () {
  var host = document.getElementById("app");
  _flutter.loader.load({
    config: { hostElement: host },
    onEntrypointLoaded: async function (engineInitializer) {
      var appRunner = await engineInitializer.initializeEngine({ hostElement: host });
      var carga = document.getElementById("carga");
      if (carga) carga.remove();
      await appRunner.runApp();
    }
  });
})();
