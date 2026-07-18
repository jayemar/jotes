package migrations

import (
	"fmt"

	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// requiredNotesFields describes the shape the app's sync code depends on,
// used both to build a fresh collection and to sanity-check a pre-existing
// one (see ensureNotesCollection) - a mismatch here would otherwise surface
// as a confusing runtime failure on the first note create/update instead
// of a clear error at startup.
var requiredNotesFields = []struct {
	name    string
	newType func() core.Field
}{
	{"title", func() core.Field { return &core.TextField{} }},
	{"body", func() core.Field { return &core.TextField{} }},
	{"color_index", func() core.Field { return &core.NumberField{} }},
	{"reminder_at", func() core.Field { return &core.TextField{} }},
	{"created", func() core.Field { return &core.AutodateField{} }},
	{"updated", func() core.Field { return &core.AutodateField{} }},
}

// verifyNotesSchema checks that a pre-existing "notes" collection actually
// has the fields the app depends on, rather than assuming any collection
// by that name is usable.
func verifyNotesSchema(collection *core.Collection) error {
	for _, want := range requiredNotesFields {
		field := collection.Fields.GetByName(want.name)
		if field == nil {
			return fmt.Errorf(
				"existing %q collection is missing required field %q - "+
					"schema doesn't match what jotes expects",
				collection.Name, want.name,
			)
		}

		wantType := want.newType().Type()
		if field.Type() != wantType {
			return fmt.Errorf(
				"existing %q collection's field %q has type %q, expected %q",
				collection.Name, want.name, field.Type(), wantType,
			)
		}
	}
	return nil
}

// ensureNotesCollection creates the "notes" collection if it doesn't
// already exist. A pre-existing deployment may already have it from the
// original JS migration (1721000000_create_notes_collection.js, ported to
// this Go file 1:1) - PocketBase tracks applied migrations by filename,
// and the changed extension means this migration looks unapplied there
// even though the schema it would create already exists. Rather than
// colliding on the duplicate collection name, verify the existing one
// actually matches what's expected and leave it alone.
func ensureNotesCollection(app core.App) error {
	if existing, err := app.FindCollectionByNameOrId("notes"); err == nil {
		return verifyNotesSchema(existing)
	}

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
		// note would report its created/updated as "now" instead of its
		// real value.
		&core.AutodateField{Name: "created", OnCreate: true, OnUpdate: false},
		&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
	)

	if err := app.Save(collection); err != nil {
		return err
	}

	// jotes generates note ids as UUID v4 (36 chars, e.g.
	// "3fa85f64-5717-4562-b3fc-2c963f66afa6"), but PocketBase's default id
	// field (pattern ^[a-z0-9]+$, min/max 15) rejects both the hyphens and
	// the length, so every client-supplied id would fail on create. Relax
	// both to accept jotes' UUIDs. The id field only exists on the
	// collection after the first save, hence the second save here.
	idField := collection.Fields.GetByName("id").(*core.TextField)
	idField.Pattern = "^[a-z0-9-]+$"
	idField.Min = 0
	idField.Max = 36

	return app.Save(collection)
}

// revertNotesCollection intentionally does NOT delete the "notes"
// collection: ensureNotesCollection may have found it pre-existing (see
// above) rather than having created it, so this migration can't safely
// assume it owns the collection's lifecycle. Rolling back this migration
// simply leaves the collection as-is.
func revertNotesCollection(app core.App) error {
	return nil
}

func init() {
	m.Register(ensureNotesCollection, revertNotesCollection)
}
