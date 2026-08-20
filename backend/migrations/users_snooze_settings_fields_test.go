package migrations

import (
	"testing"

	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"
)

func TestUsersCollectionHasSnoozeSettingsFields(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	collection, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatal(err)
	}

	for name, wantType := range map[string]string{
		"snooze_mode":                 core.FieldTypeText,
		"snooze_custom_delay_minutes": core.FieldTypeNumber,
		"snooze_time_of_day_minutes":  core.FieldTypeNumber,
	} {
		field := collection.Fields.GetByName(name)
		if field == nil {
			t.Fatalf("expected users collection to have a %q field", name)
		}
		if field.Type() != wantType {
			t.Fatalf("expected %q to be a %s field, got %s", name, wantType, field.Type())
		}
	}
}
