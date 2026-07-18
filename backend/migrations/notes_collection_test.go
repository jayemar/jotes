package migrations

import (
	"strings"
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
)

// Regression test for the exact upgrade failure this migration hit in
// production: PocketBase tracks applied migrations by filename, so a
// deployment that already ran the original JS migration
// (1721000000_create_notes_collection.js) sees this Go-ported file as a
// brand new, unapplied migration and runs it again - which must not try
// to recreate a "notes" collection that already exists.
//
// tests.NewTestApp() already runs every registered migration once (via
// app.RunAllMigrations()), which for a fresh test app means
// ensureNotesCollection creates "notes" itself the first time - so
// calling it again here exercises exactly the "already exists" branch
// that broke on upgrade, without needing an external PocketBase binary or
// a real historical database.
func TestEnsureNotesCollectionIsIdempotent(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	before, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatalf("expected notes collection to already exist after NewTestApp: %v", err)
	}

	record := core.NewRecord(before)
	record.Set("title", "pre-existing note")
	record.Set("body", "must survive a second migration run")
	if err := app.Save(record); err != nil {
		t.Fatalf("failed to seed a note: %v", err)
	}

	if err := ensureNotesCollection(app); err != nil {
		t.Fatalf("ensureNotesCollection should be a no-op on an existing, "+
			"correctly-shaped collection, got error: %v", err)
	}

	after, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatalf("notes collection should still exist: %v", err)
	}
	if before.Id != after.Id {
		t.Fatalf("expected the same collection (id %q), got a different one (id %q) - "+
			"looks like it got recreated instead of left alone", before.Id, after.Id)
	}

	found, err := app.FindRecordById("notes", record.Id)
	if err != nil || found == nil {
		t.Fatalf("pre-existing note did not survive: %v", err)
	}
	if found.GetString("title") != "pre-existing note" {
		t.Fatalf("pre-existing note's data was altered, got title %q", found.GetString("title"))
	}
}

// If a pre-existing "notes" collection is missing a field the app
// actually depends on (e.g. hand-edited, or from some future incompatible
// schema), ensureNotesCollection must fail loudly at startup with a clear
// error rather than silently treating a differently-shaped collection as
// fine, which would otherwise surface later as a confusing failure on the
// first note create/update.
func TestEnsureNotesCollectionDetectsSchemaDrift(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatal(err)
	}

	collection.Fields.RemoveByName("color_index")
	if err := app.Save(collection); err != nil {
		t.Fatalf("failed to simulate schema drift: %v", err)
	}

	err = ensureNotesCollection(app)
	if err == nil {
		t.Fatal("expected an error for a notes collection missing a required field, got nil")
	}
	if !strings.Contains(err.Error(), "color_index") {
		t.Fatalf("expected error to mention the missing field \"color_index\", got: %v", err)
	}
}
