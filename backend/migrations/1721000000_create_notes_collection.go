package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

func init() {
	m.Register(func(app core.App) error {
		collection := core.NewBaseCollection("notes", "")
		collection.ListRule = types.Pointer("@request.auth.id != ''")
		collection.ViewRule = types.Pointer("@request.auth.id != ''")
		collection.CreateRule = types.Pointer("@request.auth.id != ''")
		collection.UpdateRule = types.Pointer("@request.auth.id != ''")
		collection.DeleteRule = types.Pointer("@request.auth.id != ''")

		collection.Fields.Add(
			&core.TextField{Name: "title"},
			&core.TextField{Name: "body"},
			&core.NumberField{Name: "color_index"},
			&core.TextField{Name: "reminder_at"},
			// Not added automatically by PocketBase (unlike the id field) -
			// the app's sync merge logic compares this timestamp to decide
			// which side of a conflict wins, so without it every fetched
			// note would report its created/updated as "now" instead of
			// its real value.
			&core.AutodateField{Name: "created", OnCreate: true, OnUpdate: false},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)

		if err := app.Save(collection); err != nil {
			return err
		}

		// jotes generates note ids as UUID v4 (36 chars, e.g.
		// "3fa85f64-5717-4562-b3fc-2c963f66afa6"), but PocketBase's default
		// id field (pattern ^[a-z0-9]+$, min/max 15) rejects both the
		// hyphens and the length, so every client-supplied id would fail on
		// create. Relax both to accept jotes' UUIDs. The id field only
		// exists on the collection after the first save, hence the second
		// save here.
		idField := collection.Fields.GetByName("id").(*core.TextField)
		idField.Pattern = "^[a-z0-9-]+$"
		idField.Min = 0
		idField.Max = 36

		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		return app.Delete(collection)
	})
}
