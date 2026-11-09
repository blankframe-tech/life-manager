// Loaded before Flutter. Some plugins the iOS app needs also ship a web part
// that injects a third-party <script> at startup (google_sign_in adds
// accounts.google.com/gsi/client). The CSP already blocks those; this drops
// them before the browser tries, so nothing is requested and the console
// stays clean. Same-origin scripts (Flutter's own) are untouched.
(() => {
  const remote = (node) =>
    node instanceof HTMLScriptElement &&
    node.src !== '' &&
    new URL(node.src, location.href).origin !== location.origin;
  for (const name of ['appendChild', 'insertBefore']) {
    const original = Node.prototype[name];
    Node.prototype[name] = function (node, ...rest) {
      return remote(node) ? node : original.call(this, node, ...rest);
    };
  }
})();
