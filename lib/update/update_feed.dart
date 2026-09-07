import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// The GitHub repo that hosts both the source and the release assets the app
/// updates itself from. `releases/latest/download/<file>` always points at
/// the newest published release, so publishing a version is only a matter of
/// attaching the artifacts (tool/package/publish_update.ps1).
const String updateRepoSlug = 'klovaaxel/local-transcription';

Uri updateFeedUrl() {
  return Uri.parse(
    'https://github.com/$updateRepoSlug/releases/latest/download/updates.json',
  );
}

/// One downloadable file in the feed: name inside the release plus the SHA-256
/// the app checks before installing. HTTPS plus the hash is the integrity
/// story — the installer is unsigned.
class UpdateArtifact {
  const UpdateArtifact({required this.file, required this.sha256});

  final String file;
  final String sha256;

  Uri get url {
    return Uri.parse(
      'https://github.com/$updateRepoSlug/releases/latest/download/$file',
    );
  }

  static UpdateArtifact fromJson(Map<String, dynamic> json) {
    return UpdateArtifact(
      file: json['file'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
    );
  }

  bool get isValid => file.isNotEmpty && sha256.length == 64;
}

/// A parsed updates.json from the release feed.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.build,
    required this.artifacts,
    this.notes,
  });

  final String version;
  final int build;

  /// Keyed by platform: 'windows', 'android', 'linux', 'macos'.
  final Map<String, UpdateArtifact> artifacts;
  final String? notes;

  static UpdateManifest fromJson(Map<String, dynamic> json) {
    final artifacts = <String, UpdateArtifact>{};
    final raw = json['artifacts'];
    if (raw is Map<String, dynamic>) {
      for (final entry in raw.entries) {
        if (entry.value is Map<String, dynamic>) {
          artifacts[entry.key] = UpdateArtifact.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }
    }
    return UpdateManifest(
      version: json['version'] as String? ?? '',
      build: (json['build'] as num?)?.toInt() ?? 0,
      artifacts: artifacts,
      notes: json['notes'] as String?,
    );
  }

  static UpdateManifest? tryParse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return UpdateManifest.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  /// Fetches the feed. Null means "no release published yet" (the expected
  /// state before the first publish); anything else that fails throws.
  static Future<UpdateManifest?> fetch([http.Client? client]) async {
    final owns = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c.get(
        updateFeedUrl(),
        headers: {'User-Agent': 'lecture_local-updater'},
      );
      if (response.statusCode == 404) {
        return null;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Uppdateringslistan svarade ${response.statusCode}',
        );
      }
      return UpdateManifest.tryParse(response.body);
    } finally {
      if (owns) {
        c.close();
      }
    }
  }
}

/// True when [candidate] (+ [candidateBuild]) should replace [current]
/// (+ [currentBuild]). Compares the dotted version first, build number as
/// tie-breaker — Android depends on the build number strictly increasing.
bool versionIsNewer(
  String current,
  int currentBuild,
  String candidate,
  int candidateBuild,
) {
  final a = _versionParts(current);
  final b = _versionParts(candidate);
  for (var i = 0; i < 3; i++) {
    if (b[i] != a[i]) {
      return b[i] > a[i];
    }
  }
  return candidateBuild > currentBuild;
}

List<int> _versionParts(String version) {
  final parts = version.split('.');
  return List<int>.generate(
    3,
    (i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0,
  );
}
