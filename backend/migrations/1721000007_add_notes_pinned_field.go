package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Adds a synced flag marking whether a note is pinned - pinned notes
// always sort to the top of the grid/list regardless of the chosen sort
// order (see applyNotesView in the Flutter app). Existing records with no
// explicit value read as false (Go's zero value), which is the correct
// default - no backfill needed, same reasoning as the "reminder_resolved"
// field migration this one otherwise mirrors.
func init() {
	m.Register(func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		if collection.Fields.GetByName("pinned") != nil {
			return nil
		}
		collection.Fields.Add(&core.BoolField{Name: "pinned"})
		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		collection.Fields.RemoveByName("pinned")
		return app.Save(collection)
	})
}
