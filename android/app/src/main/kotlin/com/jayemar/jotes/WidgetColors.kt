package com.jayemar.jotes

import androidx.compose.ui.graphics.Color
import androidx.glance.color.ColorProvider
import androidx.glance.unit.ColorProvider as GlanceColorProvider

/**
 * Mirrors kNoteColors/kNoteColorsDark in lib/models/note.dart - Kotlin has
 * no access to the Flutter Theme those come from, so this is a
 * manually-kept-in-sync duplicate. Both palettes are internally consistent
 * (every light-mode entry is light, every dark-mode entry is dark), so a
 * single fixed day/night text color pair is safe here, unlike Dart's
 * per-color ThemeData.estimateBrightnessForColor.
 */
private val lightNoteColors = listOf(
    Color(0xFFFFFFFF), Color(0xFFF28B82), Color(0xFFFBBC04), Color(0xFFFFF475),
    Color(0xFFCCFF90), Color(0xFFCBF0F8), Color(0xFFAECBFA), Color(0xFFD7AEFB),
    Color(0xFFFDCFE8), Color(0xFFE6C9A8),
)

private val darkNoteColors = listOf(
    Color(0xFF202124), Color(0xFF5C2B29), Color(0xFF614A19), Color(0xFF635D19),
    Color(0xFF345920), Color(0xFF16504B), Color(0xFF2D555E), Color(0xFF42275E),
    Color(0xFF5B2245), Color(0xFF442F19),
)

fun noteColorProvider(colorIndex: Int): GlanceColorProvider {
  val index = colorIndex.coerceIn(0, lightNoteColors.size - 1)
  return ColorProvider(day = lightNoteColors[index], night = darkNoteColors[index])
}

val noteTextColorProvider: GlanceColorProvider =
    ColorProvider(day = Color(0xFF202124), night = Color(0xFFE8EAED))

// Reminder List widget: neutral background matching the app's own
// scaffold background roughly, plus red/green row-time colors mirroring
// NoteCard's _ReminderChip convention (note_card.dart).
val widgetBackgroundProvider: GlanceColorProvider =
    ColorProvider(day = Color(0xFFF8F9FA), night = Color(0xFF202124))
val overdueColorProvider: GlanceColorProvider =
    ColorProvider(day = Color(0xFFD93025), night = Color(0xFFF28B82))
val upcomingColorProvider: GlanceColorProvider =
    ColorProvider(day = Color(0xFF188038), night = Color(0xFF81C995))
