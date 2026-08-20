package com.jayemar.jotes

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.TextUnit
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
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextDecoration
import androidx.glance.text.TextStyle
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.actionStartActivity
import org.json.JSONObject

/** Mirrors note_body_editor.dart's BodyBlock - see [parseBlocks]. */
private sealed class BodyBlock {
  data class Checklist(
      val checked: Boolean,
      val text: String,
      val isLink: Boolean,
      val indent: Int,
  ) : BodyBlock()

  data class PlainText(val text: String, val isLink: Boolean) : BodyBlock()
}

/**
 * Reads the `blocks` array WidgetService.buildSingleNoteJson (Dart side)
 * already parsed via parseBody - re-parsing the raw "- [ ] "/"- [x] "
 * markdown syntax here in Kotlin too would mean two independent
 * implementations of the same regex to keep in sync. Same reasoning for
 * `isLink`/link-syntax stripping (see WidgetService's own comment on
 * buildSingleNoteJson) - Glance can't render a mixed-style line at all, so
 * `text` has already been reduced to just its display label on the Dart
 * side, and `isLink` says whether that whole block is nothing but a link
 * (the only case worth styling specially here - see WidgetContent).
 */
private fun parseBlocks(json: JSONObject): List<BodyBlock> {
  val array = json.optJSONArray("blocks") ?: return emptyList()
  return (0 until array.length()).mapNotNull { i ->
    val obj = array.getJSONObject(i)
    when (obj.optString("type")) {
      "checklist" ->
          BodyBlock.Checklist(
              checked = obj.optBoolean("checked", false),
              text = obj.optString("text", ""),
              isLink = obj.optBoolean("isLink", false),
              indent = obj.optInt("indent", 0),
          )
      "text" ->
          BodyBlock.PlainText(
              text = obj.optString("text", ""),
              isLink = obj.optBoolean("isLink", false),
          )
      else -> null
    }
  }
}

/** Link-blue + underline when [isLink], the normal note text color otherwise. */
private fun previewTextStyle(
    isLink: Boolean,
    fontSize: TextUnit,
    strikethrough: Boolean = false,
): TextStyle {
  val decoration = when {
    strikethrough -> TextDecoration.LineThrough
    isLink -> TextDecoration.Underline
    else -> TextDecoration.None
  }
  return TextStyle(
      color = if (isLink) linkColorProvider else noteTextColorProvider,
      fontSize = fontSize,
      textDecoration = decoration,
  )
}

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
            style = TextStyle(color = noteTextColorProvider, fontSize = 15.sp),
        )
      }
      return
    }

    val json = JSONObject(raw)
    val id = json.getString("id")
    val title = json.optString("title", "")
    val blocks = parseBlocks(json)
    val colorIndex = json.optInt("colorIndex", 0)

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(noteColorProvider(colorIndex))
            // More on the left specifically - content was sitting right up
            // against the widget's left edge.
            .padding(start = 20.dp, top = 14.dp, end = 14.dp, bottom = 14.dp)
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
                fontSize = 18.sp,
            ),
        )
        // Same gap note_card.dart puts between its own title and body
        // preview - packing straight from title into the body list with
        // zero gap (as an earlier version of this file did) read as
        // cramped, since Glance's Column has no built-in item spacing to
        // fall back on the way a Flutter Column does.
        Spacer(modifier = GlanceModifier.height(12.dp))
      }
      // Checklist items show a real checkbox glyph (checked/unchecked,
      // strikethrough) instead of the raw "- [ ] "/"- [x] " markdown
      // syntax the note's body carries - matches note_card.dart's own
      // in-app preview, just with plain Unicode box glyphs instead of
      // Material icons, since this widget renders no other icons either.
      // Capped at a modest number of blocks, well below what
      // note_card.dart allows itself - the in-app card lives in a
      // scrollable masonry grid with real room to breathe; a home-screen
      // widget's canvas is small and fixed, so cramming in as many lines
      // as the card does just looks crowded here.
      for (block in blocks.take(MAX_PREVIEW_BLOCKS)) {
        when (block) {
          is BodyBlock.Checklist -> ChecklistPreviewRow(block)
          is BodyBlock.PlainText ->
              if (block.text.isNotEmpty()) {
                Text(
                    text = block.text,
                    maxLines = 2,
                    style = previewTextStyle(isLink = block.isLink, fontSize = 16.sp),
                    modifier = GlanceModifier.padding(top = 2.dp, bottom = 2.dp),
                )
              }
        }
      }
    }
  }

  @Composable
  private fun ChecklistPreviewRow(block: BodyBlock.Checklist) {
    Row(
        modifier = GlanceModifier.padding(
            start = (block.indent * 12).dp,
            top = 2.dp,
            bottom = 2.dp,
        ),
        // The ☐/☑ glyphs come from a symbol font whose own line metrics
        // sit higher in its character cell than the surrounding Latin
        // text does in its cell - Row's CenterVertically centers each
        // child's *box*, not the glyphs actually drawn inside it, so
        // centering both left the checkbox visibly higher than the text
        // next to it. Bottom-aligning both is the usual fix for this kind
        // of icon/text glyph mismatch; Glance has no baseline-alignment
        // modifier to do this more precisely.
        verticalAlignment = Alignment.Vertical.Bottom,
    ) {
      Text(
          text = if (block.checked) "☑" else "☐",
          style = TextStyle(color = noteTextColorProvider, fontSize = 16.sp),
      )
      Spacer(modifier = GlanceModifier.width(6.dp))
      Text(
          text = block.text,
          maxLines = 1,
          style = previewTextStyle(
              isLink = block.isLink,
              fontSize = 16.sp,
              strikethrough = block.checked,
          ),
      )
    }
  }

  companion object {
    private const val MAX_PREVIEW_BLOCKS = 5
  }
}
