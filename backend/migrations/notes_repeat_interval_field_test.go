package migrations

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
)

func TestNotesCollectionHasRepeatIntervalField(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatal(err)
	}

	field := collection.Fields.GetByName("repeat_interval")
	if field == nil {
		t.Fatal("expected notes collection to have a \"repeat_interval\" field")
	}
	if _, ok := field.(*core.TextField); !ok {
		t.Fatalf("expected \"repeat_interval\" to be a TextField, got %T", field)
	}
}

func TestExistingNoteWithNoExplicitRepeatIntervalValueReadsAsEmpty(t *testing.T) {
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
	if found.GetString("repeat_interval") != "" {
		t.Fatalf(
			"expected a note with no explicit repeat_interval value to read as empty, got %q",
			found.GetString("repeat_interval"),
		)
	}
}
