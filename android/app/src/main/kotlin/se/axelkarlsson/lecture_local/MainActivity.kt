package se.axelkarlsson.lecture_local

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// Bridge for the self-updater. `installApk` streams the downloaded APK into a
/// PackageInstaller session; the system's confirm dialog does the user-facing
/// work, [InstallReceiver] only observes the outcome. "Install unknown apps"
/// must be granted once before a session will commit — Dart asks
/// `canRequestInstall` first and sends the teacher to the right switch.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "forelasning/updater")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "installApk" -> {
                            installApk(call.argument<String>("path")!!)
                            result.success(null)
                        }
                        "canRequestInstall" -> result.success(canRequestInstall())
                        "openInstallPermissionSettings" -> {
                            openInstallPermissionSettings()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("updater_error", e.message, null)
                }
            }
    }

    private fun canRequestInstall(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
            packageManager.canRequestPackageInstalls()

    private fun openInstallPermissionSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName")
                )
            )
        }
    }

    private fun installApk(path: String) {
        val apk = File(path)
        val installer = packageManager.packageInstaller
        val sessionId = installer.createSession(
            PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        )
        val session = installer.openSession(sessionId)
        try {
            apk.inputStream().use { input ->
                session.openWrite("forelasning", 0, apk.length()).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }
            val pending = PendingIntent.getBroadcast(
                this,
                sessionId,
                Intent(INSTALL_STATUS_ACTION).setPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            session.commit(pending.intentSender)
        } catch (e: Throwable) {
            session.abandon()
            throw e
        } finally {
            session.close()
        }
    }

    companion object {
        const val INSTALL_STATUS_ACTION = "se.axelkarlsson.lecture_local.INSTALL_STATUS"
    }
}
