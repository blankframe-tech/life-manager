import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'vectors/embedded.dart';

void main() {
  test('embedded vectors match the files', () {
    for (final MapEntry(:key, :value) in embeddedVectors.entries) {
      expect(
        base64.decode(value),
        File('test/vault/vectors/$key').readAsBytesSync(),
        reason: '$key changed: regenerate test/vault/vectors/embedded.dart',
      );
    }
  });
}
