package com.jayemar.jotes

import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

class SingleNoteWidgetReceiver : HomeWidgetGlanceWidgetReceiver<SingleNoteWidget>() {
  override val glanceAppWidget = SingleNoteWidget()
}
