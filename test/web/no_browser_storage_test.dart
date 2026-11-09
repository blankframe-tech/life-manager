import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrail for the web build: decrypted data must never reach browser
/// storage or the URL. Greps the web-only sources (comments stripped) for the
/// APIs that would put it there. The e2e run also checks the live page.
void main() {
  final banned = RegExp(
    r'localStorage|sessionStorage|indexedDB|IndexedDB|idbFactory|'
    r'\.cookie\b|cookieStore|caches\.open|CacheStorage|'
    r'pushState|replaceState|location\.(hash|search|href)\s*=|'
    r'SharedPreferencesPlugin|SharedPreferencesAsync|'
    r'flutter_secure_storage|isar',
  );

  List<File> webSources() => [
    ...Directory('lib/web').listSync(recursive: true).whereType<File>(),
    File('lib/boot/boot_web.dart'),
    File('lib/models/item_web.dart'),
    File('lib/models/history_event_web.dart'),
    ...Directory('web').listSync().whereType<File>().where(
      (f) => f.path.endsWith('.js') || f.path.endsWith('.html'),
    ),
  ];

  String stripComments(String src) => src
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'(^|\s)//.*'), ''))
      .join('\n');

  test('web code never touches browser storage or the URL', () {
    final hits = <String>[];
    for (final f in webSources()) {
      final lines = stripComments(f.readAsStringSync()).split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (banned.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}: ${lines[i]}');
      }
    }
    expect(hits, isEmpty);
  });

  test('the web boot swaps preferences for a memory-only store', () {
    final boot = File('lib/boot/boot_web.dart').readAsStringSync();
    expect(boot, contains('InMemorySharedPreferencesStore.empty()'));
  });

  test('index.html has a strict CSP and no-referrer', () {
    final html = File('web/index.html').readAsStringSync();
    expect(html, contains("default-src 'self'"));
    expect(html, contains("script-src 'self' 'wasm-unsafe-eval';"));
    expect(html, contains('name="referrer" content="no-referrer"'));
    expect(html, isNot(contains('https://')));
  });
}
