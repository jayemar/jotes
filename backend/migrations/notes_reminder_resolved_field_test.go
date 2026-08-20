package migrations

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
)

func TestNotesCollectionHasReminderResolvedField(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatal(err)
	}

	field := collection.Fields.GetByName("reminder_resolved")
	if field == nil {
		t.Fatal("expected notes collection to have a \"reminder_resolved\" field")
	}
	if _, ok := field.(*core.BoolField); !ok {
		t.Fatalf("expected \"reminder_resolved\" to be a BoolField, got %T", field)
	}
}

func TestExistingNoteWithNoExplicitReminderResolvedValueReadsAsFalse(t *testing.T) {
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
	if found.GetBool("reminder_resolved") {
		t.Fatal("expected a note with no explicit reminder_resolved value to read as false")
	}
}
