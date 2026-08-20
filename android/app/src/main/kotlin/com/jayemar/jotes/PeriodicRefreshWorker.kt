package com.jayemar.jotes

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Boots a headless Flutter engine to run main()'s `--periodic-refresh`
 * branch (see main.dart) - re-derives the home-screen widget's
 * upcoming/overdue state against the current time, and re-posts any
 * overdue reminder that's no longer showing in the notification shade
 * (see NotificationService.restoreUnresolvedReminders), without either of
 * those waiting on the next unrelated sync/push/app-open to happen to
 * touch them. Scheduled as periodic work by MainActivity.
 *
 * Same Worker-not-Service reasoning as BootRestoreWorker's own doc
 * comment, and the same main-thread hop + fixed shutdown window for the
 * same reason: FlutterEngine expects to be driven from the main thread,
 * and there's no signal back from Dart when the `--periodic-refresh`
 * branch finishes.
 */
class PeriodicRefreshWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

  override fun doWork(): Result {
    var engine: FlutterEngine? = null

    Handler(Looper.getMainLooper()).post {
      val flutterEngine = FlutterEngine(applicationContext)
      engine = flutterEngine
      flutterEngine.dartExecutor.executeDartEntrypoint(
          DartExecutor.DartEntrypoint.createDefault(),
          listOf("--periodic-refresh"),
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
