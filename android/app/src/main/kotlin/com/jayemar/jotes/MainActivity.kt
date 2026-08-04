package com.jayemar.jotes

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

private const val AUTOSTART_CHANNEL = "com.jayemar.jotes/autostart"

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
