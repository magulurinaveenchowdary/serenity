# Implementation Plan - Interactive Alarm Notification

This plan outlines the changes required to ensure the alarm notification is fully interactive, allowing the user to tap to open the app, or use action buttons to Stop/Snooze, even from a killed state.

## Problem Analysis
- **Issue**: The `AlarmForegroundService` was posting a generic notification that replaced the detailed one created by `AlarmReceiver`. This generic notification lacked `contentIntent` (tap action) and action buttons.
- **Goal**: Make the persistent service notification interactive and handle the app opening logic correctly.

## Proposed Changes

### 1. Android Native (`Kotlin`)

#### `AlarmForegroundService.kt`
- **Update `onStartCommand`**:
    - Build a rich `Notification` identical to the one in `AlarmReceiver`.
    - **Tap Action**: Use `setContentIntent` with a `PendingIntent.getActivity` pointing to `FullScreenAlarmActivity`.
        - Add extra: `is_success = true` (to signal the app that the user wants to dismiss/finish the alarm flow).
    - **Stop Action**: Add action button linking to `StopReceiver`.
    - **Snooze Action**: Add action button linking to `SnoozeReceiver`.
    - **Channel**: Ensure `IMPORTANCE_MAX` channel is used.

#### `MainActivity.kt` / `FullScreenAlarmActivity.kt`
- **Handle Intents**:
    - In `onCreate` and `onNewIntent`, check for `is_success` flag.
    - If present:
        - Stop the `AlarmForegroundService`.
        - Cancel the notification.
        - Send a MethodChannel message (`"tap"`) to Flutter.

### 2. Flutter (`Dart`)

#### `main.dart`
- **MethodChannel Listener**:
    - Ensure the `serenity/current_alarm` channel listener handles the `tap` method.
    - **Action**: Navigate to `AlarmSuccessScreen`.

## Verification Plan

### Automated/Manual Tests
1.  **Background Test**:
    - Schedule alarm for 1 min from now.
    - Background the app.
    - Wait for alarm.
    - **Verify**: Notification appears. Tap notification -> App opens -> Navigates to Success.
2.  **Killed State Test**:
    - Schedule alarm.
    - Kill the app.
    - Wait for alarm.
    - **Verify**: Notification appears. Tap notification -> App opens -> Navigates to Success.
3.  **Action Buttons**:
    - **Verify**: Snooze button dismisses notification and reschedules.
    - **Verify**: Stop button dismisses notification and opens app (optional) or just stops sound.

## Status
- [x] Update `AlarmForegroundService.kt` with rich notification logic.
- [x] Fix compilation error (`val cannot be reassigned`).
- [ ] Verify build and execution on device.
