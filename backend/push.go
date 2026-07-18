package main

import (
	"encoding/json"
	"log"
	"os"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"

	webpush "github.com/SherClockHolmes/webpush-go"
)

// vapidSubject is the "sub" claim in the VAPID JWT sent with every push -
// required by RFC8292, but its exact value isn't meaningful for a
// single-user self-hosted server; most push services accept any string.
// Override via JOTES_VAPID_SUBJECT if a distributor you use is stricter.
func vapidSubject() string {
	if s := os.Getenv("JOTES_VAPID_SUBJECT"); s != "" {
		return s
	}
	return "mailto:admin@localhost"
}

// notesChangedPayload is deliberately a tiny "something changed" hint
// rather than the note's actual content: Web Push messages have a strict
// size ceiling, and a hint works uniformly for creates/updates/deletes and
// for batches (e.g. Google Keep import) without needing to shape a
// per-event payload. The receiving device does a full re-sync on wake,
// identical to what already happens when it reconnects normally (see
// SyncNotifier._mergeSync in the Flutter app).
type notesChangedPayload struct {
	Type string `json:"type"`
}

func notesChangedMessage() []byte {
	data, _ := json.Marshal(notesChangedPayload{Type: "notes_changed"})
	return data
}

// registerNotesPushHooks wires the "notes" collection's create/update/delete
// success events to a Web Push fan-out to every registered device, so a
// change made on one device reaches every other device even while its app
// isn't open - not just while both happen to be running at the same time.
func registerNotesPushHooks(app *pocketbase.PocketBase, getVapid func() *vapidKeyPair) {
	notify := func(e *core.RecordEvent) error {
		vapid := getVapid()
		if vapid != nil {
			fanOutPush(app, notesChangedMessage(), vapid)
		}
		return e.Next()
	}

	app.OnRecordAfterCreateSuccess("notes").BindFunc(notify)
	app.OnRecordAfterUpdateSuccess("notes").BindFunc(notify)
	app.OnRecordAfterDeleteSuccess("notes").BindFunc(notify)
}

// pushHTTPClient overrides the HTTP client webpush.SendNotification uses -
// nil in production (webpush-go then falls back to a real *http.Client),
// swapped out in tests so they can assert on fanOutPush's response
// handling (e.g. stale-subscription cleanup) without a real network call.
var pushHTTPClient webpush.HTTPClient

// fanOutPush sends payload to every registered device. A single device's
// subscription being invalid/expired must not stop delivery to the rest,
// so failures are logged and skipped rather than propagated - this runs
// from inside a record hook, where there's no HTTP response to report
// errors back through anyway.
func fanOutPush(app core.App, payload []byte, vapid *vapidKeyPair) {
	records, err := app.FindAllRecords("push_subscriptions")
	if err != nil {
		log.Printf("jotes push: failed to list subscriptions: %v", err)
		return
	}

	options := &webpush.Options{
		HTTPClient:      pushHTTPClient,
		Subscriber:      vapidSubject(),
		VAPIDPublicKey:  vapid.PublicKey,
		VAPIDPrivateKey: vapid.PrivateKey,
		TTL:             60,
	}

	for _, record := range records {
		sub := &webpush.Subscription{
			Endpoint: record.GetString("endpoint"),
			Keys: webpush.Keys{
				P256dh: record.GetString("p256dh"),
				Auth:   record.GetString("auth"),
			},
		}

		resp, err := webpush.SendNotification(payload, sub, options)
		if err != nil {
			log.Printf("jotes push: send failed for subscription %s: %v", record.Id, err)
			continue
		}
		resp.Body.Close()

		// A Web Push endpoint that responds 404/410 has been revoked by the
		// distributor and will never accept another message - clean it up
		// instead of retrying it forever on every future note change.
		if resp.StatusCode == 404 || resp.StatusCode == 410 {
			if err := app.Delete(record); err != nil {
				log.Printf("jotes push: failed to remove stale subscription %s: %v", record.Id, err)
			}
		}
	}
}
