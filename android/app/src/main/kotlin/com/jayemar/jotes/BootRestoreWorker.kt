package com.jayemar.jotes

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Boots a headless Flutter engine to run main()'s `--boot-restore` branch
 * (see main.dart), which re-posts any overdue reminder the user hasn't
 * resolved yet - see NotificationService.restoreUnresolvedReminders.
 * Enqueued by BootRestoreReceiver on boot.
 *
 * A WorkManager Worker, not a foreground Service - confirmed on-device
 * (via ForegroundServiceStartNotAllowedException) that Android 14+
 * unconditionally refuses to start a foreground service whose
 * background-start allowance derives from a BOOT_COMPLETED broadcast, for
 * every foregroundServiceType tried (dataSync, then shortService), even
 * routed through a delayed AlarmManager hop - the restriction turned out
 * to be tied to which temporary background-execution allowlist entry is
 * being consumed, not simply the immediate call stack. WorkManager's own
 * executor has its own legitimate background-execution allowance entirely
 * independent of that restriction, which is exactly why it's the
 * documented, recommended mechanism for "run some background work
 * triggered by boot" on modern Android.
 *
 * FlutterEngine's platform-channel plumbing expects to be created and
 * driven from the main thread, but Worker.doWork() itself runs on one of
 * WorkManager's own background threads - so this hops onto the main
 * thread to do the actual engine work, then blocks doWork() (which is
 * explicitly meant to be a synchronous, blocking call) for a fixed
 * window, same reasoning as the earlier Service-based implementation:
 * there's no signal back from Dart when restoreUnresolvedReminders()
 * finishes, so this just gives it a generous fixed window before tearing
 * the engine down - a handful of DB reads and notification calls
 * comfortably fit well within it.
 */
class BootRestoreWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

  override fun doWork(): Result {
    var engine: FlutterEngine? = null

    Handler(Looper.getMainLooper()).post {
      val flutterEngine = FlutterEngine(applicationContext)
      engine = flutterEngine
      flutterEngine.dartExecutor.executeDartEntrypoint(
          DartExecutor.DartEntrypoint.createDefault(),
          listOf("--boot-restore"),
      )
    }

    Thread.sleep(SHUTDOWN_DELAY_MS)

    Handler(Looper.getMainLooper()).post {
      engine?.destroy()
    }

    return Result.success()
  }

  companion object {
    private const val SHUTDOWN_DELAY_MS = 15_000L
  }
}
