package com.jayemar.jotes

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import org.json.JSONObject

/**
 * Shows a single note's title and a short body preview; the whole widget
 * opens that note in the app on tap. Which note is configured per widget
 * instance via WidgetConfigurationActivity/widget_note_picker_screen.dart -
 * see WidgetService.syncAll (Dart side) for how note_data.$appWidgetId gets
 * (re)written whenever the note changes.
 */
class SingleNoteWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    val appWidgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
    provideContent { WidgetContent(appWidgetId, currentState()) }
  }

  @Composable
  private fun WidgetContent(appWidgetId: Int, currentState: HomeWidgetGlanceState) {
    val context = LocalContext.current
    val raw = currentState.preferences.getString("note_data.$appWidgetId", null)

    if (raw == null) {
      Column(
          modifier = GlanceModifier
              .fillMaxSize()
              .background(noteColorProvider(0))
              .padding(16.dp),
          verticalAlignment = Alignment.Vertical.CenterVertically,
      ) {
        Text(
            text = "Long-press → Edit to choose a note",
            style = TextStyle(color = noteTextColorProvider, fontSize = 13.sp),
        )
      }
      return
    }

    val json = JSONObject(raw)
    val id = json.getString("id")
    val title = json.optString("title", "")
    val body = json.optString("body", "")
    val colorIndex = json.optInt("colorIndex", 0)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(noteColorProvider(colorIndex))
            .padding(12.dp)
            .clickable(
                actionStartActivity<MainActivity>(context, Uri.parse("jotes://note/$id"))
            ),
    ) {
      if (title.isNotEmpty()) {
        Text(
            text = title,
            maxLines = 2,
            style = TextStyle(
                color = noteTextColorProvider,
                fontWeight = FontWeight.Bold,
                fontSize = 15.sp,
            ),
        )
      }
      if (body.isNotEmpty()) {
        Text(
            text = body,
            maxLines = 6,
            style = TextStyle(color = noteTextColorProvider, fontSize = 13.sp),
        )
      }
    }
  }
}
