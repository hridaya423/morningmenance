# Morning Menace

Morning Menace is a chaotic alarm app built in Flutter.

Core idea: if you keep snoozing, the app fires a consequence.

Right now, only consequence #1 is active. On snooze, it picks random contacts and random images, then opens the Messages app with everything prefilled.

## What works today

- Create, edit, delete, and toggle daily alarms
- Ringing screen with `Stop` and `Snooze`
- Notification-based scheduling with timezone handling
- Consequence #1 (5 contacts + 5 images)
- Contact/image pool management with local persistence

## Important behavior note

This app does **not** silently send SMS/MMS in the background.

On both iOS and Android, system rules require user interaction for this flow. So the app prepares the message and opens Messages, and the user taps send.

## Run it

```bash
flutter pub get
flutter run
```

