package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
)

// Adds the reminder Snooze settings (see SnoozeSettings in the Flutter app)
// onto each user's own auth record, so choosing e.g. "always snooze to
// 9am" on one device applies on every other device logged into the same
// account too - previously these lived only in each device's own
// SharedPreferences. The app already refreshes its copy of this record on
// every sync (see PbService.refreshAuth, called from mergeSync), which is
// what carries a change made on one device to another - no separate fetch
// needed. Existing users with no explicit value read as PocketBase's zero
// values (empty string / 0), which SnoozeSettings.fromPocketBase treats the
// same as "unset" and falls back to its own local defaults for - no
// backfill needed, same reasoning as the "deleted"/"reminder_resolved"
// field migrations this one otherwise mirrors.
func init() {
	m.Register(func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}

		if collection.Fields.GetByName("snooze_mode") == nil {
			collection.Fields.Add(&core.TextField{Name: "snooze_mode"})
		}
		if collection.Fields.GetByName("snooze_custom_delay_minutes") == nil {
			collection.Fields.Add(&core.NumberField{Name: "snooze_custom_delay_minutes"})
		}
		if collection.Fields.GetByName("snooze_time_of_day_minutes") == nil {
			collection.Fields.Add(&core.NumberField{Name: "snooze_time_of_day_minutes"})
		}

		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}
		collection.Fields.RemoveByName("snooze_mode")
		collection.Fields.RemoveByName("snooze_custom_delay_minutes")
		collection.Fields.RemoveByName("snooze_time_of_day_minutes")
		return app.Save(collection)
	})
}
