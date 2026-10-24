// Browser-only glue for the web vault: file pickers, write-back, download,
// and page events. Imported only from the web boot (conditional import), so
// none of this reaches the iOS / Android build.
//
// Storage rule: nothing here writes to localStorage, sessionStorage,
// IndexedDB, cookies or the URL (test/web/no_browser_storage_test.dart).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:web/web.dart' as web;

import 'web_vault.dart';

const vaultFileName = 'LifeManager.lmvault';

// The File System Access API pieces package:web doesn't declare (Chromium).
extension type _Picker._(JSObject _) implements JSObject {
  external JSPromise<JSArray<web.FileSystemFileHandle>> showOpenFilePicker([
    JSObject options,
  ]);
  external JSPromise<web.FileSystemFileHandle> showSaveFilePicker([
    JSObject options,
  ]);
}

extension type _Permissions._(JSObject _) implements JSObject {
  external JSPromise<JSString> queryPermission(JSObject descriptor);
  external JSPromise<JSString> requestPermission(JSObject descriptor);
}

/// Chromium's File System Access API: open, then write back to the same file.
bool get canWriteInPlace =>
    web.window.has('showOpenFilePicker') &&
    web.window.has('showSaveFilePicker');

JSObject _pickerOptions({String? suggestedName}) => {
  'suggestedName': ?suggestedName,
  'types': [
    {
      'description': 'Life Manager vault',
      'accept': {
        'application/octet-stream': ['.lmvault'],
      },
    },
  ],
}.jsify()! as JSObject;

/// A vault the user picked: its bytes and where a sync should go.
typedef PickedVault = ({
  Uint8List bytes,
  int? modified,
  VaultSource source,
});

/// Asks for a `.lmvault` file. Null when the user cancels.
Future<PickedVault?> pickVault() async {
  if (canWriteInPlace) {
    try {
      final handles = await (web.window as _Picker)
          .showOpenFilePicker(_pickerOptions())
          .toDart;
      final source = HandleSource(handles.toDart.first);
      final f = (await source.readCurrent())!;
      return (bytes: f.bytes, modified: f.modified, source: source);
    } on Object catch (e) {
      if (_isAbort(e)) return null;
      rethrow;
    }
  }
  // Safari / Firefox: a plain file input. No extension filter, so a file that
  // iCloud Drive renamed ("LifeManager 2.lmvault") is still selectable.
  final file = await openFile();
  if (file == null) return null;
  return (
    bytes: await file.readAsBytes(),
    modified: (await file.lastModified()).millisecondsSinceEpoch,
    source: DownloadSource(file.name) as VaultSource,
  );
}

/// The user closed the picker (a DOMException named AbortError).
bool _isAbort(Object e) => e.toString().contains('AbortError');

/// Writes back to the file the user opened (Chromium). Asks for write
/// permission the first time; the browser shows its own prompt.
class HandleSource implements VaultSource {
  HandleSource(this.handle);

  final web.FileSystemFileHandle handle;

  @override
  String get name => handle.name;

  @override
  bool get writesInPlace => true;

  @override
  Future<({Uint8List bytes, int modified})?> readCurrent() async {
    final file = await handle.getFile().toDart;
    final buf = await file.arrayBuffer().toDart;
    return (bytes: buf.toDart.asUint8List(), modified: file.lastModified);
  }

  /// True when writing won't need a prompt (used before an auto-lock).
  Future<bool> hasWritePermission() async =>
      (await (handle as _Permissions)
              .queryPermission({'mode': 'readwrite'}.jsify()! as JSObject)
              .toDart)
          .toDart ==
      'granted';

  @override
  Future<int?> write(Uint8List bytes) async {
    final mode = {'mode': 'readwrite'}.jsify()! as JSObject;
    final p = handle as _Permissions;
    if ((await p.queryPermission(mode).toDart).toDart != 'granted' &&
        (await p.requestPermission(mode).toDart).toDart != 'granted') {
      throw StateError('The browser did not allow writing to $name.');
    }
    final stream = await handle.createWritable().toDart;
    await stream.write(bytes.toJS).toDart;
    await stream.close().toDart;
    return (await handle.getFile().toDart).lastModified;
  }
}

/// Safari / Firefox: every sync downloads `LifeManager.lmvault` for the user
/// to put back in iCloud Drive (or AirDrop to the iPhone).
class DownloadSource implements VaultSource {
  DownloadSource(this.name);

  @override
  final String name;

  @override
  bool get writesInPlace => false;

  @override
  Future<({Uint8List bytes, int modified})?> readCurrent() async => null;

  @override
  Future<int?> write(Uint8List bytes) async {
    download(bytes, vaultFileName);
    return null;
  }
}

/// A vault created in this tab: on Chromium the first sync asks where to save
/// it and later syncs write there; elsewhere every sync downloads.
class NewFileSource implements VaultSource {
  HandleSource? _handle;

  @override
  String get name => _handle?.name ?? vaultFileName;

  @override
  bool get writesInPlace => canWriteInPlace;

  @override
  Future<({Uint8List bytes, int modified})?> readCurrent() async =>
      _handle?.readCurrent();

  @override
  Future<int?> write(Uint8List bytes) async {
    if (!canWriteInPlace) {
      download(bytes, vaultFileName);
      return null;
    }
    _handle ??= HandleSource(
      await (web.window as _Picker)
          .showSaveFilePicker(_pickerOptions(suggestedName: vaultFileName))
          .toDart,
    );
    return _handle!.write(bytes);
  }
}

/// Saves [bytes] (always ciphertext) through a temporary blob: URL.
void download(Uint8List bytes, String name) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name
    ..style.display = 'none';
  web.document.body!.append(a);
  a.click();
  a.remove();
  // Give the download a moment to start before revoking the URL.
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
}

/// Warns before closing or reloading the tab while [hasUnsynced] is true.
void guardUnload(bool Function() hasUnsynced) {
  web.window.addEventListener(
    'beforeunload',
    (web.BeforeUnloadEvent e) {
      if (!hasUnsynced()) return;
      e.preventDefault();
      e.returnValue = ''; // older Chromium / Safari need a value set
    }.toJS,
  );
}

/// Calls [onChange] with `true` when the tab becomes visible, `false` hidden.
void onVisibilityChange(void Function(bool visible) onChange) {
  web.document.addEventListener(
    'visibilitychange',
    (web.Event _) {
      onChange(web.document.visibilityState == 'visible');
    }.toJS,
  );
}
