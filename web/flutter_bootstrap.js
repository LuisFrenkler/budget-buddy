{{flutter_js}}
{{flutter_build_config}}

// Load main.dart.js under a URL that changes with every build, so a browser
// can never keep running an old copy from its cache.
const buildId = "__BUILD_ID__"; // set by tool/build_web.sh
for (const build of _flutter.buildConfig.builds) {
  if (build.mainJsPath) build.mainJsPath += "?v=" + buildId;
}
_flutter.loader.load();
