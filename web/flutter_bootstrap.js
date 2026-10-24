{{flutter_js}}
{{flutter_build_config}}

// No service worker (nothing is cached for offline use), and fallback fonts
// come from this site's own fonts/fallback/ folder instead of Google's CDN.
// CanvasKit is served locally too (build with --no-web-resources-cdn).
_flutter.loader.load({
  config: {
    fontFallbackBaseUrl: 'fonts/fallback/',
  },
});
