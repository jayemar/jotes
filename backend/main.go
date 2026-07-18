package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"path/filepath"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/plugins/migratecmd"
	"github.com/pocketbase/pocketbase/tools/osutils"

	webpush "github.com/SherClockHolmes/webpush-go"

	_ "jotes-backend/migrations"
)

const vapidFileName = "jotes_vapid.json"

type vapidKeyPair struct {
	PublicKey  string `json:"publicKey"`
	PrivateKey string `json:"privateKey"`
}

// loadOrCreateVAPIDKeys returns this server's persistent Web Push VAPID
// keypair, generating and saving one on first run. The keys live in
// pb_data (not the SQLite database itself) so they survive container
// restarts via the same volume already mounted for pb_data, and so a
// device's push registration doesn't silently break if the server is ever
// recreated.
func loadOrCreateVAPIDKeys(app core.App) (*vapidKeyPair, error) {
	path := filepath.Join(app.DataDir(), vapidFileName)

	if data, err := os.ReadFile(path); err == nil {
		var keys vapidKeyPair
		if err := json.Unmarshal(data, &keys); err != nil {
			return nil, err
		}
		return &keys, nil
	}

	private, public, err := webpush.GenerateVAPIDKeys()
	if err != nil {
		return nil, err
	}
	keys := &vapidKeyPair{PublicKey: public, PrivateKey: private}

	data, err := json.Marshal(keys)
	if err != nil {
		return nil, err
	}
	if err := os.WriteFile(path, data, 0o600); err != nil {
		return nil, err
	}
	return keys, nil
}

func main() {
	app := pocketbase.New()

	migratecmd.MustRegister(app, app.RootCmd, migratecmd.Config{
		Automigrate: osutils.IsProbablyGoRun(),
	})

	var vapid *vapidKeyPair

	app.OnServe().BindFunc(func(se *core.ServeEvent) error {
		keys, err := loadOrCreateVAPIDKeys(app)
		if err != nil {
			return err
		}
		vapid = keys

		se.Router.GET("/api/jotes/vapid-public-key", func(e *core.RequestEvent) error {
			return e.JSON(http.StatusOK, map[string]string{
				"publicKey": vapid.PublicKey,
			})
		})

		return se.Next()
	})

	registerNotesPushHooks(app, func() *vapidKeyPair { return vapid })

	if err := app.Start(); err != nil {
		log.Fatal(err)
	}
}
