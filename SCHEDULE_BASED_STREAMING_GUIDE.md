# Schedule-Based Persistent Streaming Architecture

## Overview
The app now implements **schedule-based persistent streaming** where streams automatically start at the scheduled time and run continuously in the background until the scheduled end time, regardless of viewer connection status.

## Key Changes

### 1. Architecture Redesign
- **Old Model**: Viewer-triggered, on-demand streaming (User B had to manually click "OPEN SESSION")
- **New Model**: Schedule-triggered, persistent background streaming

### 2. Stream Lifecycle

#### Broadcaster (User B) Behavior
1. **Accepts request** via interactive notification or requests list
2. **Navigates** to `ActiveSessionScreen` 
3. **Automatic start** at `scheduledStartTime` via `_scheduleTimer`
4. **Stream runs continuously** in background until `scheduledEndTime`
5. **Independent** of viewer connections/disconnections
6. **Ends** at scheduled end time OR manual stop by User B

#### Viewer (User A) Behavior
1. **Clicks "View File"** anytime during scheduled window
2. **Connects** to existing broadcaster stream
3. **Can exit and reconnect** multiple times without affecting broadcaster
4. **No manual "OPEN SESSION" click** required from User B

### 3. Permission Flow
- **All permissions requested once** at app startup (HomeScreen)
- Permissions: Camera, Microphone, Location
- **No runtime permission prompts** during usage

## Testing Instructions

### Test 1: Schedule-Based Auto-Start
**Goal**: Verify stream starts automatically at scheduled time

1. **Setup**: 
   - User A sends request with start time 2-3 minutes in future
   - User B accepts request via notification or requests list

2. **Expected**:
   - User B navigates to `ActiveSessionScreen`
   - Screen shows "Session will start at [scheduled time]"
   - At scheduled start time, stream automatically initializes
   - Camera preview appears without manual button click

3. **Pass Criteria**:
   - ✅ No "OPEN SESSION" button required
   - ✅ Stream starts precisely at scheduled time
   - ✅ Camera preview shows both front and back streams

### Test 2: Background Persistence
**Goal**: Verify stream continues when app is backgrounded

1. **Setup**:
   - Start stream as in Test 1
   - Wait for stream to start automatically

2. **Test Steps**:
   - Press device home button (app goes to background)
   - Wait 30 seconds
   - Reopen app

3. **Expected**:
   - Stream still running when app reopens
   - Camera preview visible
   - No reconnection needed

4. **Pass Criteria**:
   - ✅ Stream continues running in background
   - ✅ No disruption when app returns to foreground

### Test 3: Multiple Viewer Connections
**Goal**: Verify User A can connect/disconnect freely

1. **Setup**:
   - Stream running (User B on `ActiveSessionScreen`)

2. **Test Steps**:
   - **User A**: Click "View File" → see stream
   - **User A**: Exit stream screen (back button)
   - **User A**: Click "View File" again → see stream
   - Repeat 3-4 times

3. **Expected**:
   - User B's stream unaffected by User A's actions
   - User A reconnects successfully each time
   - No stream interruption on User B's side

4. **Pass Criteria**:
   - ✅ User A can view stream multiple times
   - ✅ User B's stream never stops
   - ✅ No manual "OPEN SESSION" clicks needed

### Test 4: Stream End Time
**Goal**: Verify stream ends at scheduled end time

1. **Setup**:
   - Create request with short duration (e.g., 5 minutes)
   - Start stream

2. **Test Steps**:
   - Wait until scheduled end time passes
   - Observe behavior

3. **Expected**:
   - Stream automatically stops at end time
   - User B returns to previous screen or shows session ended message
   - Firestore ticket status updates to completed

4. **Pass Criteria**:
   - ✅ Stream ends precisely at scheduled end time
   - ✅ Clean resource cleanup
   - ✅ Database updated correctly

### Test 5: Startup Permissions
**Goal**: Verify all permissions requested at app launch

1. **Setup**:
   - Uninstall existing app
   - Install fresh APK: `d:\Projects\streamix\build\app\outputs\flutter-apk\app-release.apk`

2. **Test Steps**:
   - Launch app
   - Complete login
   - Observe HomeScreen initialization

3. **Expected**:
   - Permission prompts appear immediately:
     - Camera access
     - Microphone access
     - Location access
   - All prompts appear before any other UI interaction

4. **Pass Criteria**:
   - ✅ All 3 permissions requested on first launch
   - ✅ No permission prompts during streaming
   - ✅ No permission prompts when accepting requests

### Test 6: Manual Stop by User B
**Goal**: Verify User B can manually end stream before scheduled end time

1. **Setup**:
   - Stream running (before end time)

2. **Test Steps**:
   - User B clicks "End Session" or back button
   - Confirm end action

3. **Expected**:
   - Stream stops immediately
   - Resources cleaned up
   - User A sees "Stream ended" if connected

4. **Pass Criteria**:
   - ✅ Manual stop works anytime
   - ✅ Clean shutdown
   - ✅ Viewer notified of end

## Key Implementation Files

### `lib/screens/home/home_screen.dart`
```dart
// Permission request at app startup
void _requestAllPermissions() async {
  await Permission.camera.request();
  await Permission.microphone.request();
  await Permission.location.request();
}
```

### `lib/screens/session/active_session_screen.dart`
**Key Methods**:
- `_checkSchedule()`: Determines if session should start based on scheduledStartTime
- `_scheduleTimer`: Timer that checks every second for scheduled start time
- Stream initialization: Automatically triggered at start time
- No manual initialization methods anymore

**Lifecycle**:
```
Accept Request → Navigate to ActiveSessionScreen → 
_checkSchedule() runs → Wait for scheduled time → 
Auto-start stream → Run until end time → 
Auto-cleanup OR manual stop
```

### `lib/screens/requests/requests_list_screen.dart`
- Simplified accept button (no permission requests)
- Auto-navigation for stream services maintained
- Permission handling moved to HomeScreen

## Architecture Benefits

### For User B (Broadcaster)
- ✅ No manual "OPEN SESSION" clicks required
- ✅ Stream automatically starts at scheduled time
- ✅ Stream runs independently in background
- ✅ Can manage session without worrying about viewer connections

### For User A (Viewer)
- ✅ Can view stream anytime during scheduled window
- ✅ Can exit and return freely
- ✅ No dependency on broadcaster manual actions
- ✅ Seamless reconnection experience

### For Both Users
- ✅ Single permission request at app startup
- ✅ No interruptions during usage
- ✅ Clear session lifecycle tied to schedule
- ✅ Predictable behavior based on scheduled times

## Known Behaviors

1. **Before Scheduled Start Time**: 
   - ActiveSessionScreen shows countdown or "Session will start at..." message
   - Camera preview not yet visible

2. **During Scheduled Window**:
   - Stream always running (User B side)
   - User A can connect/disconnect freely
   - Background operation supported

3. **After Scheduled End Time**:
   - Stream automatically stops
   - Resources cleaned up
   - Database updated

## Troubleshooting

### Stream doesn't start automatically
- **Check**: scheduledStartTime in Firestore ticket
- **Verify**: Device time is correct
- **Look for**: Console logs showing schedule check results

### Permissions not requested at startup
- **Check**: HomeScreen initState() being called
- **Verify**: permission_handler dependency in pubspec.yaml
- **Test**: Fresh install (uninstall previous version)

### User A can't connect to stream
- **Check**: User B's stream is running (check ActiveSessionScreen)
- **Verify**: scheduledStartTime has passed
- **Check**: WebRTC signaling in Firestore

### Stream stops unexpectedly
- **Check**: scheduledEndTime hasn't been reached
- **Verify**: No manual stop by User B
- **Look for**: Console error logs

## Development Notes

### Timer Management
- `_scheduleTimer` checks every 1 second if start time is reached
- Timer disposed properly in dispose() method
- Prevents memory leaks from running timers

### State Management
- `_isStreaming` flag tracks streaming state
- Schedule checks prevent duplicate stream initialization
- Proper lifecycle management with dispose() cleanup

### Future Enhancements
- [ ] Add progress indicator for scheduled start countdown
- [ ] Implement notification when stream auto-starts
- [ ] Add viewer count display on broadcaster side
- [ ] Implement stream health monitoring
- [ ] Add analytics for connection/disconnection events

## APK Location
```
d:\Projects\streamix\build\app\outputs\flutter-apk\app-release.apk
```

**Version**: Latest build with schedule-based streaming
**Size**: ~109.2 MB
**Build Date**: Current session
