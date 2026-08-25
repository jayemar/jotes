package migrations

import (
	"encoding/json"

	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// migrationRepeatRule mirrors the JSON shape the Flutter app's
// RepeatRule.toJson()/fromJson() (lib/models/repeat_rule.dart) actually
// reads/writes - kept in sync manually since this is the one place the
// backend ever constructs that shape itself (everywhere else it's an
// opaque string PocketBase just stores and returns).
type migrationRepeatRule struct {
	Frequency string         `json:"frequency"`
	Interval  int            `json:"interval"`
	Weekdays  []int          `json:"weekdays"`
	End       map[string]any `json:"end"`
}

// Replaces the fixed daily/weekly/monthly/yearly repeat_interval field
// (see 1721000005) with a fuller recurrence rule - repeat_rule (JSON:
// frequency, interval count, specific weekdays for a weekly rule, and an
// end condition) plus repeat_occurrence_number (which occurrence of that
// rule the note's current reminder_at represents, 1 = the first - needed
// for a "ends after N occurrences" end condition to know when it's been
// exhausted; see nextRuleOccurrence in the Flutter app). Any existing
// repeat_interval value is converted into the equivalent simple
// repeat_rule (interval 1, no specific weekday, never-ending) rather than
// silently dropped, since a handful of notes may already have one set.
func init() {
	m.Register(func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}

		hadRepeatInterval := collection.Fields.GetByName("repeat_interval") != nil

		if collection.Fields.GetByName("repeat_rule") == nil {
			collection.Fields.Add(&core.TextField{Name: "repeat_rule"})
		}
		if collection.Fields.GetByName("repeat_occurrence_number") == nil {
			collection.Fields.Add(&core.NumberField{Name: "repeat_occurrence_number"})
		}
		if err := app.Save(collection); err != nil {
			return err
		}

		if hadRepeatInterval {
			if err := migrateExistingRepeatIntervals(app); err != nil {
				return err
			}
			collection.Fields.RemoveByName("repeat_interval")
			if err := app.Save(collection); err != nil {
				return err
			}
		}

		return nil
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("notes")
		if err != nil {
			return err
		}
		collection.Fields.RemoveByName("repeat_rule")
		collection.Fields.RemoveByName("repeat_occurrence_number")
		if collection.Fields.GetByName("repeat_interval") == nil {
			collection.Fields.Add(&core.TextField{Name: "repeat_interval"})
		}
		return app.Save(collection)
	})
}

// migrateExistingRepeatIntervals converts every note's existing
// repeat_interval value (an enum name: "none"/"daily"/"weekly"/"monthly"/
// "yearly", or empty for a note that predates the field) into the
// equivalent repeat_rule - a note with "none"/empty gets no repeat_rule at
// all (nil, "does not repeat"), matching how RepeatRule.fromJson() already
// treats an empty string.
func migrateExistingRepeatIntervals(app core.App) error {
	records, err := app.FindAllRecords("notes")
	if err != nil {
		return err
	}

	for _, record := range records {
		interval := record.GetString("repeat_interval")
		if interval == "" || interval == "none" {
			continue
		}

		rule := migrationRepeatRule{
			Frequency: interval,
			Interval:  1,
			Weekdays:  []int{},
			End:       map[string]any{"type": "never"},
		}
		encoded, err := json.Marshal(rule)
		if err != nil {
			return err
		}

		record.Set("repeat_rule", string(encoded))
		record.Set("repeat_occurrence_number", 1)
		if err := app.Save(record); err != nil {
			return err
		}
	}

	return nil
}
