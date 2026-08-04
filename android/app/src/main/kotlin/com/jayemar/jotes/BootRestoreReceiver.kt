package com.jayemar.jotes

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager

/**
 * Enqueues BootRestoreWorker so unresolved overdue reminders (see
 * NotificationService.restoreUnresolvedReminders in the Dart code) reappear
 * without the user having to open the app first - Android wipes the
 * notification tray on every boot, and nothing else restores them.
 * Mirrors the same BOOT_COMPLETED/MY_PACKAGE_REPLACED/QUICKBOOT_POWERON
 * intent-filter shape as flutter_local_notifications' own boot receiver
 * (see AndroidManifest.xml), for the same cross-OEM reliability reasons.
 *
 * See BootRestoreWorker's own doc comment for why this enqueues a
 * WorkManager Worker rather than starting a Service directly.
 */
class BootRestoreReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    WorkManager.getInstance(context).enqueue(
        OneTimeWorkRequestBuilder<BootRestoreWorker>().build(),
    )
  }
}
