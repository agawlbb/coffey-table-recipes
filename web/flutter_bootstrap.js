{{flutter_js}}
{{flutter_build_config}}

// Development hosting: fetch the entry point anew and do not register an
// offline service worker. Apache headers in .htaccess cover the other assets.
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) {
    build.mainJsPath += '?dev=' + Date.now();
  }
}
_flutter.loader.load();
