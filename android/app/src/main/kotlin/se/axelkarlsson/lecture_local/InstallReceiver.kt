package se.axelkarlsson.lecture_local

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

/// Catches the PackageInstaller session result the updater commit pointed
/// here. The install confirms, fails, or pends in the system dialog, which owns
/// the user-facing UX; this receiver exists so the outcome is visible in
/// logcat and so commit() has a valid target.
class InstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        Log.d("ForelasningUpdater", "Install session status=$status message=$message")
    }
}
