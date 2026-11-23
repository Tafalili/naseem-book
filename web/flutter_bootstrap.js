{{flutter_js}}
{{flutter_build_config}}

// No Flutter service worker: it is deprecated, and on iPhone Safari its
// register / unregister / reload cycle can leave the page on the loading screen.
_flutter.loader.load();
