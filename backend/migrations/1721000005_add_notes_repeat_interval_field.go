package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Adds a synced field storing how often a note's reminder should recur
// once Dismissed (see RepeatInterval/nextOccurrence in the Flutter app's
// lib/models/note.dart) - stored as the enum's own name ("none", "daily",
// "weekly", "monthly", "yearly") rather than a numeric code, so the raw
// server value stays self-describing. Existing records with no explicit
// value read as an empty string, which Note.fromPocketBase already falls
// back to RepeatInterval.none for - no backfill needed, same reasoning as
// the "deleted"/"reminder_resolved" field migrations this one mirrors.
func init() {
	m.Register(func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		if collection.Fields.GetByName("repeat_interval") != nil {
			return nil
		}
		collection.Fields.Add(&core.TextField{Name: "repeat_interval"})
		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		collection.Fields.RemoveByName("repeat_interval")
		return app.Save(collection)
	})
}
