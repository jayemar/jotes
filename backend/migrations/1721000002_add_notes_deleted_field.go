package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Adds a tombstone field so a device that deletes a note while another
// device is offline doesn't get its deletion silently undone: without
// this, "remote has no record for this id" is indistinguishable from
// "this note was never synced yet", so the offline device's stale local
// copy gets pushed right back up once it reconnects (see
// SyncNotifier.mergeSync in the Flutter app, which now checks this field
// instead of relying on hard deletion). Existing records with no explicit
// value read as false (Go's zero value), which is the correct default -
// no backfill needed.
func init() {
	m.Register(func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		if collection.Fields.GetByName("deleted") != nil {
			return nil
		}
		collection.Fields.Add(&core.BoolField{Name: "deleted"})
		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		collection.Fields.RemoveByName("deleted")
		return app.Save(collection)
	})
}
