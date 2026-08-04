# Physical Device Testing (Pixel 6a)

Reference notes from a session that drove a real Pixel 6a via `adb` to
diagnose and verify several Android-platform-specific bugs in jotes
(notification actions, boot-triggered background work, notification
swipe behavior). Written for a future AI session that needs to do this
again.

## Before you start: this is expensive, don't reach for it by default

Screenshot-based UI automation over `adb` burns tokens fast - every
screenshot is an image in context, and a single test cycle (navigate,
type, wait for something to fire, check the result) easily takes a dozen
round trips. **Only drive the phone when the user explicitly asks for
it**, or when you're specifically asked to diagnose something that is
genuinely unverifiable any other way (real notification-shade behavior,
real boot behavior, real foreground-service restrictions - things
`flutter test` cannot see at all). Default to the normal `flutter
test`/`flutter analyze`/`build-apk.sh` workflow. If a bug is *plausibly*
diagnosable by reading plugin source, checking the manifest, or reasoning
about the code, do that first.

## One-time environment setup

The Android SDK in this environment is not on `PATH`:

```bash
export ANDROID_SDK_ROOT=/home/jayemar/dev/Android/SDK
ADB="$ANDROID_SDK_ROOT/platform-tools/adb"
```

The phone connects over USB. The first time in a given environment, `adb
devices` may show the device as unreachable with `Access denied
(insufficient permissions)` in `adb start-server` output - this needs a
one-time udev rule that only the user can install (needs `sudo`):

```bash
! echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", MODE="0666"' | sudo tee /etc/udev/rules.d/51-android.rules && sudo udevadm control --reload-rules && sudo udevadm trigger
```

(`18d1` is Google's USB vendor ID.) After that, unplug/replug the cable.
Then the phone will show as `unauthorized` until the user taps **Allow**
on the "Allow USB debugging?" prompt on the device itself - that's a
physical confirmation only they can do. Once authorized, `adb devices -l`
shows `device` and normal `adb shell` commands work.

## The single biggest recurring mistake: coordinate scaling

Screenshots returned by the `Read` tool report as e.g. "original
1080x2400, displayed at 900x2000" - **the displayed size is what you see
in the image, but `adb shell input tap`/`swipe` need coordinates in the
*original* device resolution.** Multiply every coordinate you read off
the screenshot by the given scale factor (`1080/900 = 1.2` for this
phone) before tapping. Forgetting this - or forgetting it *consistently*,
since it's easy to do it right once and then slip - was the single most
common source of wasted round trips this session (mistaps landing on the
wrong field, wrong button, wrong dial position).

**More reliable than eyeballing screenshot coordinates at all**: dump the
real element bounds and tap the center of the exact bounds reported,
which are already in device-native coordinates:

```bash
"$ADB" shell uiautomator dump /sdcard/ui.xml
"$ADB" pull /sdcard/ui.xml /tmp/.../ui.xml
grep -o 'content-desc="Set reminder"[^>]*bounds="[^"]*"' /tmp/.../ui.xml
```

Two gotchas with `uiautomator dump`:

- **Flutter widgets expose their accessible label via `content-desc`,
  not `text=`.** `text=` is almost always empty for Flutter-rendered
  UI; grep for `content-desc="..."` instead. (Native Android views, like
  system dialogs' `EditText`s, *do* use `text=`.)
- **It only captures the currently-focused window's tree.** A system
  notification-shade overlay (a heads-up notification, for example) is
  drawn by a different process/window than your foreground app, and
  `uiautomator dump` will silently return only the launcher/foreground
  app's tree, omitting the overlay entirely. For those cases, just tap
  based on screenshot pixel coordinates (scaled per above) instead -
  there's no reliable structured alternative.

## Typing text

`adb shell input text "..."` mangles literal spaces and some punctuation
when passed through as a normal shell argument (spaces get silently
dropped or the string gets truncated). Use `%s` as a placeholder for each
space instead - `input text` on Android specifically recognizes `%s` as
a space:

```bash
"$ADB" shell input text "Reboot%stest"
"$ADB" shell input text "-%s[%s]%sBuy%smilk"
```

Brackets (`[`/`]`) typed fine once spaces were fixed.

## Text fields: title vs. body, and what "Enter" actually does

jotes' note editor has a single-line **Title** field stacked directly
above the multiline **body** field, with no visible border between them
- it is very easy to tap the title by mistake when aiming for the body
(happened more than once this session). If text ends up somewhere
unexpected, `uiautomator dump` and grep for `class="android.widget.EditText"`
to see which field actually has the text and which is focused.

A single-line field's IME treats Enter as "done" (submits/dismisses the
keyboard) rather than inserting a newline - this is normal, expected
behavior for a title field, not a bug. Before testing anything that
depends on a real newline (e.g. checklist-continuation behavior), confirm
you're actually in the multiline field: the on-screen keyboard's
bottom-right key shows a hooked **return arrow (⏎)** for a field
configured for newlines, vs. a **checkmark** for a field whose action is
"done". If you see a checkmark, you're not where you think you are.

Note also: `adb shell input keyevent KEYCODE_ENTER` does not always
behave identically to a real tap on the IME's own return key for every
field/IME combination - if a "press Enter" test doesn't do what the
*code* clearly says it should, don't immediately assume the code is
wrong. Cross-check with a `flutter test` widget test (which drives
`TextField`/`TextInputFormatter` directly through Flutter's own pipeline,
with no IME-delivery ambiguity) before concluding there's a real bug.

## Screen wake, unlock, and Direct Boot

The screen times out and locks between slow steps (e.g. while waiting on
a background task's output). To get back in:

```bash
"$ADB" shell input keyevent KEYCODE_WAKEUP
"$ADB" shell input swipe 540 1900 540 500 500   # swipe up to dismiss keyguard
```

This phone has no PIN/pattern set, just a swipe-to-unlock keyguard - the
swipe above is sufficient. If a device *does* have a secure lock method,
you cannot bypass it via `adb` without the credential; you'll need to ask
the user to unlock it.

**Important Android behavior, not a bug**: `BOOT_COMPLETED` is
deliberately *not* broadcast immediately after boot - Android withholds
it until the device is unlocked for the first time since that boot (this
is part of Direct Boot / file-based encryption, and applies even to a
device with only a swipe keyguard, no PIN). If you're testing anything
that listens for `BOOT_COMPLETED`, waking the screen is not enough - you
must actually dismiss the keyguard once before it fires.

## Notification shade

```bash
"$ADB" shell cmd statusbar expand-notifications
"$ADB" shell cmd statusbar collapse
```

Multiple notifications from the same app can get auto-grouped by Android
into a collapsed summary (`groupKey=...Aggregate_AlertingSection`) even
without the app requesting grouping. A single tap on the group's chevron
did not reliably expand it in testing; a **swipe-down gesture directly on
the group header** did:

```bash
"$ADB" shell input swipe 450 650 450 750 300
```

To test swipe-to-dismiss on an individual notification, swipe
horizontally across its row (after expanding, if grouped):

```bash
"$ADB" shell input swipe 100 906 850 906 300
```

## Rebooting for boot-behavior tests

```bash
"$ADB" reboot
"$ADB" wait-for-device
until [ "$("$ADB" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
  sleep 3
done
# then wake + swipe-unlock (see above) before checking anything
# BOOT_COMPLETED-dependent
```

Run this kind of multi-minute wait via the `Bash` tool's
`run_in_background: true` rather than blocking - you'll get a completion
notification instead of holding up the turn. **This is real, disruptive
device downtime for the user (their phone is unusable while it
reboots)** - always say so before doing it, and don't reboot the phone
speculatively.

## The most useful diagnostic tools, by far

- **`adb logcat -d`** (dump the buffer, don't bother with a live
  `-v threadtime` capture unless you need to correlate exact timing)
  piped through `grep` for your package name or a relevant tag. This is
  how every real root cause this session was actually found - stack
  traces for uncaught exceptions appear here even when nothing in the
  app's own (caught-and-swallowed) error handling would ever surface
  them. If something silently doesn't work, check here before
  hypothesizing.
- **`adb shell dumpsys notification --noredact`** - dumps the live,
  actual `NotificationRecord` for every currently-posted notification,
  including its real flags (`ONGOING_EVENT`, etc.), `groupKey`,
  `deleteIntent`, actions, and more. This is the ground truth for "is the
  flag my code sets actually reaching the OS" - don't guess, check here
  directly.

## Android 14+ foreground-service restrictions (a real trap)

If you need to run background work triggered by `BOOT_COMPLETED`:
starting a foreground service directly from a `BOOT_COMPLETED` receiver
is unconditionally rejected on Android 14+ with
`ForegroundServiceStartNotAllowedException`, **regardless of
`foregroundServiceType`** (confirmed for both `dataSync` and
`shortService` specifically) - the type doesn't matter, the restriction
is tied to which background-execution allowlist entry the call is
consuming, and that entry (established by the `BOOT_COMPLETED` broadcast
itself) permanently excludes starting a foreground service, even if you
delay the actual `startForegroundService()` call by a few seconds
through an `AlarmManager` hop (still within the original broadcast's
temp-allowlist window). **`WorkManager` (`androidx.work`) is the reliable
way to do this instead** - a plain `Worker`/`OneTimeWorkRequest` enqueued
from the receiver has its own legitimate execution allowance and sidesteps
this whole restriction, since it never needs to become a foreground
service at all. See `BootRestoreReceiver.kt`/`BootRestoreWorker.kt` for
the working pattern.

## The emulator is not a viable alternative here

This sandbox has no `/dev/kvm` and the CPU exposes no `vmx`/`svm` flags
(`grep -c 'vmx\|svm' /proc/cpuinfo` returns `0`) - there is no
hardware-accelerated virtualization available, confirmed via the
emulator's own `-accel-check` output ("VT disabled in BIOS or KVM kernel
module not loaded"). The configured AVD is an x86_64 image, which is
specifically designed to require acceleration - running it in pure
software emulation is not just slow, it's practically unusable. Don't
attempt to launch the emulator again without first confirming `/dev/kvm`
exists; if it doesn't, a physical device (or the user enabling
virtualization in their BIOS and rebooting - their call, not something to
do unprompted) is the only path to real Android UI testing in this
environment.
