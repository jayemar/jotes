package migrations

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
)

func TestNotesCollectionHasRepeatRuleFields(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatal(err)
	}

	ruleField := collection.Fields.GetByName("repeat_rule")
	if ruleField == nil {
		t.Fatal("expected notes collection to have a \"repeat_rule\" field")
	}
	if _, ok := ruleField.(*core.TextField); !ok {
		t.Fatalf("expected \"repeat_rule\" to be a TextField, got %T", ruleField)
	}

	countField := collection.Fields.GetByName("repeat_occurrence_number")
	if countField == nil {
		t.Fatal("expected notes collection to have a \"repeat_occurrence_number\" field")
	}
	if _, ok := countField.(*core.NumberField); !ok {
		t.Fatalf("expected \"repeat_occurrence_number\" to be a NumberField, got %T", countField)
	}
}

// The superseded repeat_interval field (see 1721000005) should be gone by
// the time the full migration chain has run - 1721000006 removes it once
// any existing value has been converted into the new repeat_rule shape.
func TestNotesCollectionNoLongerHasRepeatIntervalField(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("notes")
	if err != nil {
		t.Fatal(err)
	}

	if collection.Fields.GetByName("repeat_interval") != nil {
		t.Fatal("expected the superseded \"repeat_interval\" field to have been removed")
	}
}

func TestExistingNoteWithNoExplicitRepeatRuleValueReadsAsEmpty(t *testing.T) {
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
	if found.GetString("repeat_rule") != "" {
		t.Fatalf(
			"expected a note with no explicit repeat_rule value to read as empty, got %q",
			found.GetString("repeat_rule"),
		)
	}
	if found.GetInt("repeat_occurrence_number") != 0 {
		t.Fatalf(
			"expected a note with no explicit repeat_occurrence_number value to read as 0 "+
				"(the app itself falls back to 1 - see Note.fromPocketBase), got %d",
			found.GetInt("repeat_occurrence_number"),
		)
	}
}

func TestNoteCanSaveAndReadBackAFullRepeatRuleJSONValue(t *testing.T) {
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
	record.Set("title", "Repeating note")
	const ruleJSON = `{"frequency":"weekly","interval":2,"weekdays":[1,3],"end":{"type":"never"}}`
	record.Set("repeat_rule", ruleJSON)
	record.Set("repeat_occurrence_number", 3)
	if err := app.Save(record); err != nil {
		t.Fatal(err)
	}

	found, err := app.FindRecordById("notes", record.Id)
	if err != nil {
		t.Fatal(err)
	}
	if found.GetString("repeat_rule") != ruleJSON {
		t.Fatalf("expected repeat_rule to round-trip exactly, got %q", found.GetString("repeat_rule"))
	}
	if found.GetInt("repeat_occurrence_number") != 3 {
		t.Fatalf("expected repeat_occurrence_number to round-trip as 3, got %d", found.GetInt("repeat_occurrence_number"))
	}
}
