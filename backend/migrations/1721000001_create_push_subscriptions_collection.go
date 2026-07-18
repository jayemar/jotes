package migrations

import (
	"github.com/pocketbase/pocketbase/core"
	m "github.com/pocketbase/pocketbase/migrations"
	"github.com/pocketbase/pocketbase/tools/types"
)

// Stores one Web Push subscription per registered device, so the "notes"
// hooks (see main.go) know where to send an encrypted push when a note
// changes - this is what lets reminders and ordinary edits reach another
// device even while its app isn't open (see UnifiedPush integration).
func init() {
	m.Register(func(app core.App) error {
		users, err := app.FindCollectionByNameOrId("users")
		if err != nil {
			return err
		}

		collection := core.NewBaseCollection("push_subscriptions", "")
		collection.ListRule = types.Pointer("user = @request.auth.id")
		collection.ViewRule = types.Pointer("user = @request.auth.id")
		collection.CreateRule = types.Pointer("@request.auth.id != ''")
		collection.UpdateRule = types.Pointer("user = @request.auth.id")
		collection.DeleteRule = types.Pointer("user = @request.auth.id")

		collection.Fields.Add(
			&core.RelationField{
				Name:          "user",
				CollectionId:  users.Id,
				Required:      true,
				CascadeDelete: true,
				MaxSelect:     1,
			},
			// The URL the "notes" hooks POST an encrypted Web Push message
			// to - provided by the device's chosen UnifiedPush distributor.
			&core.TextField{Name: "endpoint", Required: true, Max: 2000},
			// Web Push encryption keys (RFC8291), base64url-encoded without
			// padding, as supplied by PushEndpoint.pubKeySet on the client.
			&core.TextField{Name: "p256dh", Required: true},
			&core.TextField{Name: "auth", Required: true},
			// UnifiedPush's "instance" label - jotes only ever registers a
			// single default instance per device, but it's stored so a
			// device's own record can be found again without needing to
			// remember a server-issued id client-side.
			&core.TextField{Name: "instance", Required: true},
			&core.AutodateField{Name: "created", OnCreate: true, OnUpdate: false},
			&core.AutodateField{Name: "updated", OnCreate: true, OnUpdate: true},
		)

		return app.Save(collection)
	}, func(app core.App) error {
		collection, err := app.FindCollectionByNameOrId("push_subscriptions")
		if err != nil {
			return err
		}
		return app.Delete(collection)
	})
}
