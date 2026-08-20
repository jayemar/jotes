package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Adds a synced flag marking whether the user has Dismissed/Snoozed a
// note's current reminder cycle - previously this only lived in each
// device's own SharedPreferences (see NotificationService in the Flutter
// app), so acting on a reminder on one device had no effect on any other
// device's copy of the same tray notification. Existing records with no
// explicit value read as false (Go's zero value), which is the correct
// default - no backfill needed, same reasoning as the "deleted" field
// migration this one otherwise mirrors.
func init() {
	m.Register(func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		if collection.Fields.GetByName("reminder_resolved") != nil {
			return nil
		}
		collection.Fields.Add(&core.BoolField{Name: "reminder_resolved"})
		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		collection.Fields.RemoveByName("reminder_resolved")
		return app.Save(collection)
	})
}
