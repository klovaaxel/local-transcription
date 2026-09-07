import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'update_feed.dart';

/// Downloads a release artifact, checks its hash, and hands the file to the
/// platform installer. The platform paths differ in how "automatic" they can
/// be:
///
/// - Windows: Inno Setup is re-run silently (/FORCECLOSEAPPLICATIONS closes
///   this running app via the update mutex, /RESTARTAPPLICATIONS starts the
///   new build). No user interaction beyond the download.
/// - Linux: `pkexec dpkg -i` — polkit's own password dialog, then the app
///   respawns itself.
/// - Android: PackageInstaller always shows the system confirm dialog; the
///   user must also have granted "install unknown apps" once.
/// - macOS: no silent swap is safe for an unsigned bundle, so the update
///   zip is downloaded and revealed in Finder with one instruction.
class UpdateInstaller {
  static const _channel = MethodChannel('forelasning/updater');

  bool get platformSupported =>
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isMacOS;

  String get _platformKey {
    if (Platform.isWindows) {
      return 'windows';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isMacOS) {
      return 'macos';
    }
    return '';
  }

  UpdateArtifact? artifactFor(UpdateManifest manifest) {
    return manifest.artifacts[_platformKey];
  }

  Future<String> installDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'updates'));
    await dir.create(recursive: true);
    return dir.path;
  }

  /// Downloads [artifact] into the update cache and verifies the SHA-256;
  /// returns the local path. Throws with Swedish text when the hash does not
  /// match — a wrong checksum must never be "installed anyway".
  Future<String> download(
    UpdateArtifact artifact, {
    void Function(int received, int total)? onProgress,
  }) async {
    final destPath = p.join(await installDir(), artifact.file);
    final tmp = File('$destPath.part');
    if (await tmp.exists()) {
      await tmp.delete();
    }
    final request = http.Request('GET', artifact.url);
    request.headers['User-Agent'] = 'lecture_local-updater';
    final response = await http.Client().send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Drain the stream so the socket is released before we throw.
      await response.stream.drain<void>();
      throw HttpException(
        'Nedladdningen misslyckades (${response.statusCode}) för ${artifact.file}',
      );
    }
    final total = response.contentLength ?? -1;
    final sink = tmp.openWrite();
    var received = 0;
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      onProgress?.call(received, total);
    }
    await sink.close();
    final digest = await crypto.sha256.bind(tmp.openRead()).first;
    final actual = digest.toString();
    if (actual != artifact.sha256.toLowerCase()) {
      await tmp.delete();
      throw StateError(
        'Den nedladdade uppdateringen var skadad (kontrollsumman stämde inte). '
        'Försök igen om en stund.',
      );
    }
    if (await File(destPath).exists()) {
      await File(destPath).delete();
    }
    await tmp.rename(destPath);
    return destPath;
  }

  /// Installs the prepared file. On Windows and Linux this call does not
  /// return — the process exits so the installer can take over.
  Future<void> install(String path) async {
    if (Platform.isWindows) {
      await _installWindows(path);
      return;
    }
    if (Platform.isLinux) {
      await _installLinux(path);
      return;
    }
    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('installApk', {'path': path});
      return;
    }
    if (Platform.isMacOS) {
      await _revealMacos(path);
      return;
    }
    throw UnsupportedError(
      'Auto-uppdatering stöds inte på den här plattformen',
    );
  }

  Future<void> _installWindows(String path) async {
    await Process.start(path, const [
      '/VERYSILENT',
      '/SUPPRESSMSGBOXES',
      // The update mutex (windows/runner/main.cpp) tells Inno Setup that this
      // exe is running; force-close ends it, restart relaunches the new build.
      '/FORCECLOSEAPPLICATIONS',
      '/RESTARTAPPLICATIONS',
    ], mode: ProcessStartMode.detached);
    // Give the installer a moment to enumerate running apps before we exit.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    exit(0);
  }

  Future<void> _installLinux(String path) async {
    final result = await Process.run('pkexec', ['dpkg', '-i', path]);
    if (result.exitCode != 0) {
      throw StateError(
        'Installationen kunde inte köras. Godkänn systemdialogen och försök '
        'igen, eller installera paketet manuellt: $path',
      );
    }
    // The .deb replaced /usr/bin/forelasning; the old process keeps using its
    // own inodes, so respawn into the new build and leave.
    final launcher = File('/usr/bin/forelasning');
    if (await launcher.exists()) {
      await Process.start(
        launcher.path,
        const [],
        mode: ProcessStartMode.detached,
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  Future<void> _revealMacos(String path) async {
    await Process.run('open', ['-R', path]);
  }

  /// `canRequestPackageInstalls` for the once-only "install unknown apps"
  /// grant Android requires before PackageInstaller accepts a session.
  Future<bool> canRequestInstall() async {
    if (!Platform.isAndroid) {
      return true;
    }
    try {
      final result = await _channel.invokeMethod<bool>('canRequestInstall');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens Android's per-app "install unknown apps" switch for this app.
  Future<void> openInstallPermissionSettings() async {
    await _channel.invokeMethod<void>('openInstallPermissionSettings');
  }
}
