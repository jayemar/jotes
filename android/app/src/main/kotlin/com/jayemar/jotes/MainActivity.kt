package com.jayemar.jotes

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.TimeUnit

private const val AUTOSTART_CHANNEL = "com.jayemar.jotes/autostart"
private const val SHARE_CHANNEL = "com.jayemar.jotes/share"
private const val PERIODIC_REFRESH_CHANNEL = "com.jayemar.jotes/periodic_refresh"
private const val PERIODIC_REFRESH_WORK_NAME = "periodic_refresh"
private const val NOTIFICATION_SOUNDS_CHANNEL = "com.jayemar.jotes/notification_sounds"
// A curated allowlist, by RingtoneManager's own title, of which of this
// device's notification sounds the picker offers - not "whatever
// RingtoneManager happens to return first" (this app's previous behavior),
// so the choices are ones actually picked for jotes rather than however the
// OS orders its own notification-sound list. Also keeps the picker (and so
// the number of permanent, immutable Android notification channels
// NotificationAppearanceSettings.channelId mints, one per distinct sound a
// user actually picks - see that class's own doc comment) bounded, same
// reasoning as the flat cap this replaced.
private val CURATED_NOTIFICATION_SOUND_TITLES =
    listOf(
        "Yahoo - Chime",
        "Yahoo - Snip Snap",
        "Yahoo - Mallet",
        "Yahoo - Skipping Rocks",
        "Yahoo - Reflective",
    )
// This prefix is just this sound pack's own branding - stripped from the
// title the picker actually shows, so options read "Chime" rather than
// "Yahoo - Chime".
private const val CURATED_SOUND_TITLE_PREFIX = "Yahoo - "
// The shortest interval Android's WorkManager allows for periodic work -
// anything shorter is silently clamped to this by the OS anyway. See
// PeriodicRefreshWorker's own doc comment for what this actually refreshes.
private const val PERIODIC_REFRESH_INTERVAL_MINUTES = 15L

/**
 * Component names for each OEM's own undocumented "autostart"/background
 * app management screen, keyed by a lowercase [Build.MANUFACTURER]
 * substring. There is no AOSP-standard equivalent to this - unlike exact
 * alarms or full-screen-intent access, "autostart" isn't an Android
 * concept at all, just something several manufacturers bolted on
 * independently, using internal Activity class names that aren't part of
 * any public API and can change without notice. Best-effort only: each
 * candidate is tried in order, and openAutostartSettings() always falls
 * back to the app's own details screen (an official, always-available
 * API) if none of them exist or launch successfully on this device.
 */
private val autostartActivitiesByManufacturer =
    mapOf(
        "xiaomi" to
            listOf(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
            ),
        "redmi" to
            listOf(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
            ),
        "poco" to
            listOf(
                ComponentName(
                    "com.miui.securitycenter",
                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                )
            ),
        "huawei" to
            listOf(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                ),
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.optimize.process.ProtectActivity",
                ),
            ),
        "honor" to
            listOf(
                ComponentName(
                    "com.huawei.systemmanager",
                    "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
                )
            ),
        "oppo" to
            listOf(
                ComponentName(
                    "com.coloros.safecenter",
                    "com.coloros.safecenter.permission.startup.StartupAppListActivity",
                ),
                ComponentName(
                    "com.oppo.safe",
                    "com.oppo.safe.permission.startup.StartupAppListActivity",
                ),
            ),
        "oneplus" to
            listOf(
                ComponentName(
                    "com.oneplus.security",
                    "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
                )
            ),
        "vivo" to
            listOf(
                ComponentName(
                    "com.vivo.permissionmanager",
                    "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
                )
            ),
        "iqoo" to
            listOf(
                ComponentName(
                    "com.iqoo.secure",
                    "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
                )
            ),
        "samsung" to
            listOf(
                ComponentName(
                    "com.samsung.android.lool",
                    "com.samsung.android.sm.ui.battery.BatteryActivity",
                )
            ),
        "letv" to
            listOf(
                ComponentName(
                    "com.letv.android.letvsafe",
                    "com.letv.android.letvsafe.AutobootManageActivity",
                )
            ),
        "asus" to
            listOf(
                ComponentName(
                    "com.asus.mobilemanager",
                    "com.asus.mobilemanager.autostart.AutoStartActivity",
                )
            ),
        "meizu" to
            listOf(
                ComponentName(
                    "com.meizu.safe",
                    "com.meizu.safe.permission.PermissionMainActivity",
                )
            ),
    )

class MainActivity : FlutterActivity() {
  private var shareChannel: MethodChannel? = null

  // The sound option a user is currently previewing from the picker (see
  // playNotificationSound below) - tracked so a second preview tap stops
  // the previous one instead of layering playback, and so backgrounding
  // the app (onPause) doesn't leave a preview audible after jotes is no
  // longer on screen.
  private var previewRingtone: Ringtone? = null

  override fun onPause() {
    super.onPause()
    previewRingtone?.stop()
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTOSTART_CHANNEL)
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "isKnownRestrictiveManufacturer" ->
                result.success(matchingManufacturerKey() != null)
            "openAutostartSettings" -> {
              openAutostartSettings()
              result.success(null)
            }
            else -> result.notImplemented()
          }
        }

    // The on/off decision itself lives in Dart-side SharedPreferences (see
    // PeriodicRefreshSettings) - not readable/writable from here without
    // depending on the Flutter plugin's internal storage format, so Dart
    // tells this side what to do instead: once at every normal app startup
    // (to cover a fresh install's default-on state, and to survive an
    // app update) and immediately on every Settings toggle.
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PERIODIC_REFRESH_CHANNEL)
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "setPeriodicRefreshEnabled" -> {
              applyPeriodicRefreshSchedule(call.arguments as? Boolean ?: true)
              result.success(null)
            }
            else -> result.notImplemented()
          }
        }

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_SOUNDS_CHANNEL)
        .setMethodCallHandler { call, result ->
          when (call.method) {
            "listNotificationSounds" -> result.success(listNotificationSounds())
            "playNotificationSound" -> {
              playNotificationSound(call.arguments as String)
              result.success(null)
            }
            else -> result.notImplemented()
          }
        }

    val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
    shareChannel = channel
    channel.setMethodCallHandler { call, result ->
      when (call.method) {
        // Cold start (jotes wasn't already running) - the intent that
        // launched this Activity in the first place is the share itself.
        // A warm start (already running) instead arrives via onNewIntent
        // below, pushed to Dart as an "onSharedText" call on this same
        // channel rather than something Dart has to poll for.
        "getInitialSharedText" -> result.success(extractShare(intent))
        else -> result.notImplemented()
      }
    }
  }

  // android:launchMode="singleTop" means a share arriving while jotes is
  // already on top of the back stack reuses this same Activity instance
  // via onNewIntent instead of a fresh onCreate - without overriding this,
  // that share would be silently dropped (getIntent()/configureFlutterEngine
  // only ever see the *original* launch intent).
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    setIntent(intent)
    val share = extractShare(intent) ?: return
    shareChannel?.invokeMethod("onSharedText", share)
  }

  /// See PeriodicRefreshWorker's own doc comment for what the job itself
  /// does. enqueueUniquePeriodicWork with KEEP is a no-op if a matching job
  /// is already scheduled, and cancelUniqueWork is a no-op if none is -
  /// both safe to call on every normal app startup, not just on an actual
  /// toggle.
  private fun applyPeriodicRefreshSchedule(enabled: Boolean) {
    val workManager = WorkManager.getInstance(applicationContext)
    if (enabled) {
      val request = PeriodicWorkRequestBuilder<PeriodicRefreshWorker>(
          PERIODIC_REFRESH_INTERVAL_MINUTES, TimeUnit.MINUTES,
      ).build()
      workManager.enqueueUniquePeriodicWork(
          PERIODIC_REFRESH_WORK_NAME,
          ExistingPeriodicWorkPolicy.KEEP,
          request,
      )
    } else {
      workManager.cancelUniqueWork(PERIODIC_REFRESH_WORK_NAME)
    }
  }

  /**
   * "Default" (this device's own configured default notification sound)
   * first, then whichever of [CURATED_NOTIFICATION_SOUND_TITLES] this
   * device's own installed notification sounds (queried via
   * [RingtoneManager] rather than bundled into the app - see
   * NotificationAppearanceSettings' own doc comment (Dart side) for why)
   * actually has, in that same curated order - not the OS's own cursor
   * order, and skipping any curated title this particular device doesn't
   * have installed rather than leaving a gap. Best-effort: any failure
   * querying the device's sound list still returns the "Default" entry,
   * since that one needs no query at all.
   */
  private fun listNotificationSounds(): List<Map<String, String>> {
    val sounds =
        mutableListOf(
            mapOf(
                "uri" to Settings.System.DEFAULT_NOTIFICATION_URI.toString(),
                "title" to "Default",
            )
        )
    try {
      val manager = RingtoneManager(this)
      manager.setType(RingtoneManager.TYPE_NOTIFICATION)
      val cursor = manager.cursor
      val uriByTitle = mutableMapOf<String, String>()
      while (cursor.moveToNext()) {
        val title = cursor.getString(RingtoneManager.TITLE_COLUMN_INDEX)
        if (title in CURATED_NOTIFICATION_SOUND_TITLES && title !in uriByTitle) {
          uriByTitle[title] =
              "${cursor.getString(RingtoneManager.URI_COLUMN_INDEX)}/" +
                  cursor.getString(RingtoneManager.ID_COLUMN_INDEX)
        }
      }
      for (title in CURATED_NOTIFICATION_SOUND_TITLES) {
        val uri = uriByTitle[title] ?: continue
        sounds.add(
            mapOf("uri" to uri, "title" to title.removePrefix(CURATED_SOUND_TITLE_PREFIX))
        )
      }
    } catch (_: Exception) {
      // Best-effort - the "Default" entry above is always returned
      // regardless of whether the device's own sound list is queryable.
    }
    return sounds
  }

  /**
   * Plays [uri] (one of [listNotificationSounds]'s own entries) once, as a
   * preview for the sound picker - so picking an option is audible rather
   * than just a name in a menu. Stops any preview already playing first,
   * same reasoning as [onPause], so previews never overlap.
   */
  private fun playNotificationSound(uri: String) {
    previewRingtone?.stop()
    previewRingtone =
        try {
          RingtoneManager.getRingtone(this, Uri.parse(uri))?.also { it.play() }
        } catch (_: Exception) {
          // Best-effort - a preview failing to play isn't worth surfacing
          // as an error, same reasoning as listNotificationSounds above.
          null
        }
  }

  private fun extractShare(intent: Intent?): Map<String, String>? {
    if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return null
    val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return null
    val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
    return buildMap {
      put("text", text)
      if (subject != null) put("subject", subject)
    }
  }

  private fun matchingManufacturerKey(): String? {
    val manufacturer = Build.MANUFACTURER.lowercase()
    return autostartActivitiesByManufacturer.keys.firstOrNull { manufacturer.contains(it) }
  }

  private fun openAutostartSettings() {
    val key = matchingManufacturerKey()
    val candidates = key?.let { autostartActivitiesByManufacturer[it] } ?: emptyList()
    for (component in candidates) {
      try {
        startActivity(Intent().apply { setComponent(component) })
        return
      } catch (_: ActivityNotFoundException) {
        // Try the next candidate, if any.
      } catch (_: SecurityException) {
        // Try the next candidate, if any.
      }
    }

    try {
      startActivity(
          Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.fromParts("package", packageName, null)
          }
      )
    } catch (_: ActivityNotFoundException) {
      // Nothing more to try - extremely unlikely on a real device.
    }
  }
}
