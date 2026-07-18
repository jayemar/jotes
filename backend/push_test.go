package main

import (
	"io"
	"net/http"
	"strings"
	"testing"

	"github.com/google/uuid"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tests"

	webpush "github.com/SherClockHolmes/webpush-go"
)

// fakePushHTTPClient lets a test control exactly what response
// fanOutPush's webpush.SendNotification call sees, without a real network
// call - see the pushHTTPClient var in push.go.
type fakePushHTTPClient struct {
	statusCode int
}

func (c *fakePushHTTPClient) Do(*http.Request) (*http.Response, error) {
	return &http.Response{
		StatusCode: c.statusCode,
		Body:       io.NopCloser(strings.NewReader("")),
	}, nil
}

func newTestSubscription(t *testing.T, app core.App, endpoint string) *core.Record {
	t.Helper()

	users, err := app.FindCollectionByNameOrId("users")
	if err != nil {
		t.Fatal(err)
	}
	user := core.NewRecord(users)
	user.SetEmail("push-test-" + uuid.NewString() + "@example.com")
	user.SetPassword("password123456")
	if err := app.Save(user); err != nil {
		t.Fatalf("failed to create test user: %v", err)
	}

	subs, err := app.FindCollectionByNameOrId("push_subscriptions")
	if err != nil {
		t.Fatal(err)
	}
	sub := core.NewRecord(subs)
	sub.Set("user", user.Id)
	sub.Set("endpoint", endpoint)
	// A real, valid P-256 Web Push test key (from webpush-go's own test
	// suite) - fanOutPush must get through encryption to actually reach
	// the HTTP layer this test is exercising, so a placeholder string
	// won't do (it fails to parse as an EC key before any request is
	// sent).
	sub.Set("p256dh", "BNNL5ZaTfK81qhXOx23-wewhigUeFb632jN6LvRWCFH1ubQr77FE_9qV1FuojuRmHP42zmf34rXgW80OvUVDgTk")
	sub.Set("auth", "zqbxT6JKstKSY9JKibZLSQ")
	sub.Set("instance", "default")
	if err := app.Save(sub); err != nil {
		t.Fatalf("failed to create test push subscription: %v", err)
	}
	return sub
}

func testVapidKeys(t *testing.T) *vapidKeyPair {
	t.Helper()
	private, public, err := webpush.GenerateVAPIDKeys()
	if err != nil {
		t.Fatal(err)
	}
	return &vapidKeyPair{PublicKey: public, PrivateKey: private}
}

func TestFanOutPushRemovesSubscriptionOn410Gone(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	sub := newTestSubscription(t, app, "https://push.example.com/gone")

	pushHTTPClient = &fakePushHTTPClient{statusCode: http.StatusGone}
	defer func() { pushHTTPClient = nil }()

	fanOutPush(app, notesChangedMessage(), testVapidKeys(t))

	if _, err := app.FindRecordById("push_subscriptions", sub.Id); err == nil {
		t.Fatal("expected the subscription to be deleted after a 410 response, but it still exists")
	}
}

func TestFanOutPushKeepsSubscriptionOnSuccess(t *testing.T) {
	app, err := tests.NewTestApp()
	if err != nil {
		t.Fatal(err)
	}
	defer app.Cleanup()

	sub := newTestSubscription(t, app, "https://push.example.com/ok")

	pushHTTPClient = &fakePushHTTPClient{statusCode: http.StatusCreated}
	defer func() { pushHTTPClient = nil }()

	fanOutPush(app, notesChangedMessage(), testVapidKeys(t))

	if _, err := app.FindRecordById("push_subscriptions", sub.Id); err != nil {
		t.Fatalf("subscription should survive a successful push, got: %v", err)
	}
}
