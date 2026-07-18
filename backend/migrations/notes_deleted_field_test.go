package migrations

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
)

func TestNotesCollectionHasDeletedField(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatal(err)
	}

	field := collection.Fields.GetByName("deleted")
	if field == nil {
		t.Fatal("expected notes collection to have a \"deleted\" field")
	}
	if _, ok := field.(*core.BoolField); !ok {
		t.Fatalf("expected \"deleted\" to be a BoolField, got %T", field)
	}
}

func TestExistingNoteWithNoExplicitDeletedValueReadsAsFalse(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatal(err)
	}

	record := core.NewRecord(collection)
	record.Set("title", "Untouched note")
	if err := app.Save(record); err != nil {
		t.Fatal(err)
	}

	found, err := app.FindRecordById("notes", record.Id)
	if err != nil {
		t.Fatal(err)
	}
	if found.GetBool("deleted") {
		t.Fatal("expected a note with no explicit deleted value to read as false")
	}
}
