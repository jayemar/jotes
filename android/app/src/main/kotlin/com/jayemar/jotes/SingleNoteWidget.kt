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
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.itemsIndexed
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.text.FontFamily
import androidx.glance.text.FontStyle
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
      val style: String,
      val indent: Int,
  ) : BodyBlock()

  data class PlainText(val text: String, val style: String, val indent: Int) : BodyBlock()
}

/**
 * Reads the `blocks` array WidgetService.buildSingleNoteJson (Dart side)
 * already parsed via parseBody - re-parsing the raw "- [ ] "/"- [x] "
 * markdown syntax here in Kotlin too would mean two independent
 * implementations of the same regex to keep in sync. Same reasoning for
 * `style`/markdown-syntax stripping (see WidgetService's own comment on
 * _styledText) - Glance can't render a mixed-style line at all, so `text`
 * has already been reduced to a fully plain string on the Dart side, and
 * `style` says the one way (if any) this whole block can still be styled -
 * "link"/"bold"/"italic"/"strikethrough"/"code", or "plain" for none (see
 * [previewTextStyle]).
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
              style = obj.optString("style", "plain"),
              indent = obj.optInt("indent", 0),
          )
      "text" ->
          BodyBlock.PlainText(
              text = obj.optString("text", ""),
              style = obj.optString("style", "plain"),
              indent = obj.optInt("indent", 0),
          )
      else -> null
    }
  }
}

/**
 * The [TextStyle] for one of [BodyBlock]'s own `style` values - link-blue
 * + underline for "link", bold/italic/line-through/monospace for their own
 * matching value, or just the normal note text color for "plain". A
 * checked checklist item's own strikethrough (regardless of [style])
 * still combines in via [checked], the same as buildLinkSpans' own
 * combined decoration does in-app - Glance's TextDecoration has no
 * "combine" helper of its own, so a checked+link/strikethrough-styled item
 * (the only two `style` values [checked] could otherwise clash with)
 * favors the checked strikethrough, matching how a checked item always
 * reads as "done" regardless of what it says.
 */
private fun previewTextStyle(
    style: String,
    fontSize: TextUnit,
    checked: Boolean = false,
): TextStyle {
  val decoration = when {
    checked || style == "strikethrough" -> TextDecoration.LineThrough
    style == "link" -> TextDecoration.Underline
    else -> TextDecoration.None
  }
  return TextStyle(
      color = if (style == "link") linkColorProvider else noteTextColorProvider,
      fontSize = fontSize,
      fontWeight = if (style == "bold") FontWeight.Bold else FontWeight.Normal,
      fontStyle = if (style == "italic") FontStyle.Italic else FontStyle.Normal,
      textDecoration = decoration,
      fontFamily = if (style == "code") FontFamily.Monospace else null,
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
    val openNote =
        actionStartActivity<MainActivity>(context, Uri.parse("jotes://note/$id"))

    Column(
        modifier = GlanceModifier
            .fillMaxSize()
            .background(noteColorProvider(colorIndex))
            // More on the left specifically - content was sitting right up
            // against the widget's left edge.
            .padding(start = 20.dp, top = 14.dp, end = 14.dp, bottom = 14.dp)
            // Only reachable via the header/padding below, not through the
            // body list - LazyColumn renders as its own scrollable
            // ListView, which claims touches for scrolling before they
            // ever reach an ancestor's clickable(), so each row below also
            // carries its own copy of this same action.
            .clickable(openNote),
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
      // Every block is included (no cap) - a fixed cap used to hide
      // whatever was appended past it (e.g. a freshly added checklist
      // item), which read as a sync bug even though the note itself was
      // fine. defaultWeight() lets this claim whatever vertical space is
      // left under the header, and LazyColumn makes that space scrollable
      // instead of clipping - so a longer note just needs a swipe, at any
      // widget size, rather than a hard per-note limit.
      // An empty PlainText block (a blank line in the note) renders nothing
      // in-app either - filtered out here rather than left in as a
      // LazyColumn item with no content, which each item slot isn't meant
      // to be.
      val visibleBlocks = blocks.filter { it !is BodyBlock.PlainText || it.text.isNotEmpty() }
      LazyColumn(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
        itemsIndexed(visibleBlocks) { _, block ->
          when (block) {
            is BodyBlock.Checklist -> ChecklistPreviewRow(block, openNote)
            is BodyBlock.PlainText ->
                Text(
                    text = block.text,
                    maxLines = 2,
                    style = previewTextStyle(style = block.style, fontSize = 16.sp),
                    modifier = GlanceModifier
                        .fillMaxWidth()
                        // Same indent treatment as ChecklistPreviewRow's own
                        // start-padding - a bulleted/numbered sub-item
                        // previously rendered flush with its top-level
                        // parent, since this block type carried no indent
                        // at all until WidgetService started including it.
                        .padding(
                            start = (block.indent * 12).dp,
                            top = 2.dp,
                            bottom = 2.dp,
                        )
                        .clickable(openNote),
                )
          }
        }
      }
    }
  }

  @Composable
  private fun ChecklistPreviewRow(block: BodyBlock.Checklist, openNote: Action) {
    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(
                start = (block.indent * 12).dp,
                top = 2.dp,
                bottom = 2.dp,
            )
            .clickable(openNote),
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
              style = block.style,
              fontSize = 16.sp,
              checked = block.checked,
          ),
      )
    }
  }
}
