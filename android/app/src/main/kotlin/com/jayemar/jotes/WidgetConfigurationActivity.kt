package com.jayemar.jotes

import io.flutter.embedding.android.FlutterActivity

/** Hosts the Single Note widget's "choose a note" UI; uses Dart's
 * `configureMain` entrypoint instead of the normal `main`, per
 * ACTION_APPWIDGET_CONFIGURE (see AndroidManifest.xml). */
class WidgetConfigurationActivity : FlutterActivity() {
  override fun getDartEntrypointFunctionName(): String = "configureMain"
}
