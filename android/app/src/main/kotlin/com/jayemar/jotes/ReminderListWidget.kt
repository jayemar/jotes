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
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Column
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.json.JSONArray

private data class ReminderEntry(
    val id: String,
    val title: String,
    val reminderAtMillis: Long,
    val isOverdue: Boolean,
)

private val timeFormat = SimpleDateFormat("MMM d, h:mm a", Locale.getDefault())

private fun parseEntries(raw: String?): List<ReminderEntry> {
  if (raw.isNullOrEmpty()) return emptyList()
  val array = JSONArray(raw)
  return (0 until array.length()).map { i ->
    val obj = array.getJSONObject(i)
    ReminderEntry(
        id = obj.getString("id"),
        title = obj.optString("title", ""),
        reminderAtMillis = obj.getLong("reminderAtMillis"),
        isOverdue = obj.optBoolean("isOverdue", false),
    )
  }
}

/**
 * Every note with a reminder set (upcoming and overdue), title + time,
 * oldest-first - mirrors WidgetService.buildReminderListPayload on the Dart
 * side, which is the single source of truth for the sort order and the
 * isOverdue flag used for the red/green time styling here. No
 * per-instance configuration - every pinned instance shows the same list.
 */
class ReminderListWidget : GlanceAppWidget() {
  override val stateDefinition = HomeWidgetGlanceStateDefinition()

  override suspend fun provideGlance(context: Context, id: GlanceId) {
    provideContent { WidgetContent(currentState()) }
  }

  @Composable
  private fun WidgetContent(currentState: HomeWidgetGlanceState) {
    val context = LocalContext.current
    val raw = currentState.preferences.getString("reminders_widget_data", null)
    val entries = parseEntries(raw)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(widgetBackgroundProvider)
            .padding(8.dp),
    ) {
      Text(
          text = "Reminders",
          style = TextStyle(
              color = noteTextColorProvider,
              fontWeight = FontWeight.Bold,
              fontSize = 14.sp,
          ),
          modifier = GlanceModifier.padding(bottom = 4.dp),
      )
      if (entries.isEmpty()) {
        Text(
            text = "No scheduled reminders",
            style = TextStyle(color = noteTextColorProvider, fontSize = 13.sp),
        )
      } else {
        LazyColumn {
          items(entries, itemId = { it.id.hashCode().toLong() }) { entry ->
            Column(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp)
                    .clickable(
                        actionStartActivity<MainActivity>(
                            context,
                            Uri.parse("jotes://note/${entry.id}"),
                        )
                    ),
            ) {
              Text(
                  text = entry.title.ifEmpty { "(untitled)" },
                  maxLines = 1,
                  style = TextStyle(color = noteTextColorProvider, fontSize = 14.sp),
              )
              Text(
                  text = timeFormat.format(Date(entry.reminderAtMillis)),
                  maxLines = 1,
                  style = TextStyle(
                      fontSize = 12.sp,
                      color = if (entry.isOverdue) overdueColorProvider else upcomingColorProvider,
                  ),
              )
            }
          }
        }
      }
    }
  }
}
