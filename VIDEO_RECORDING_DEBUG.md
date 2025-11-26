# Video Recording Debug Guide

## Recent Fixes Applied

### 1. **Audio Enabled** 🔊
- Changed camera initialization from `enableAudio: false` to `enableAudio: isVideo`
- Videos will now record with sound
- Video player starts with volume = 1.0 (unmuted)

### 2. **Backup Polling Mechanism** 🔄
- Added a Timer that checks Firestore every 3 seconds for pending `REQUEST_CAPTURE` commands
- This runs in parallel with the snapshot listener
- Ensures commands are never missed even if listener fails

### 3. **Extended Query Logic** 📡
- GlobalCameraHandler now activates when:
  - Session is in time window (between startTime and endTime), OR
  - `remoteCommand == 'REQUEST_CAPTURE'` (even if session not opened)
- This allows video recording without User B manually opening session

### 4. **Extended Timeout** ⏱️
- User A now waits 25 seconds (was 15s)
- Enough time for: 10s recording + 15s processing/upload

### 5. **Enhanced Logging** 📝
- Detailed logs at every step:
  - User ID being monitored
  - All accepted requests found
  - Time window calculations
  - Command detection
  - Recording start/stop with timestamps
  - File size information
  - Upload progress

## How to Test

### User B Device (Radha):
1. **Make sure app is running** - GlobalCameraHandler loads automatically
2. Check terminal/logcat for: `👀 [GlobalCamera] Service Started for User ID: <id>`
3. You should see: `🔍 [GlobalCamera] DEBUG: Found X total accepted requests`
4. When User A clicks "View File", you should see:
   ```
   📬 [GlobalCamera] Received snapshot...
   ⚡ [GlobalCamera] NEW COMMAND RECEIVED
   🎥 [GlobalVideo] Starting video recording...
   🎥 [GlobalVideo] Recording... 10s, 9s, 8s...
   🎥 [GlobalVideo] Upload successful!
   ```

### User A Device:
1. Click "View Live / File" button on any accepted video request
2. Should see loading dialog: "🎥 Recording 10s video from User B..."
3. Wait up to 25 seconds
4. Video should open in fullscreen with audio playing
5. Use speaker button to mute/unmute

## Troubleshooting

### If timeout still occurs:

#### Check User B's Logs:
```bash
# Filter for relevant logs
adb logcat | grep -E "GlobalCamera|GlobalVideo|TicketService"
```

Look for these key logs:
- `👀 [GlobalCamera] Service Started` - Listener is running
- `📬 [GlobalCamera] Received snapshot with X documents` - Firestore query working
- `⚡ [GlobalCamera] NEW COMMAND RECEIVED` - Command detected
- `🎥 [GlobalVideo] Starting video recording` - Recording started
- `✅ [GlobalVideo] Complete! Video sent to User A` - Success

#### Missing Logs Mean:

| Missing Log | Problem | Solution |
|------------|---------|----------|
| No "Service Started" | GlobalCameraHandler not initialized | Check main.dart, ensure GlobalCameraHandler wraps AuthWrapper |
| No "Received snapshot" | Firestore query issue | Check User B's ID matches `peerUserId` in request |
| No "NEW COMMAND" | Command not detected | Check `remoteCommand` field is set to `REQUEST_CAPTURE` |
| No "Starting video" | Camera not initializing | Check camera permissions, check logs for camera errors |
| No "Complete" | Upload failing | Check Supabase credentials, internet connection |

### Manual Firebase Check:
1. Open Firebase Console → Firestore
2. Find the request document (use request ID from chat)
3. Check fields:
   - `peerUserId` should be User B's Firebase Auth UID
   - `status` should be `'accepted'`
   - `remoteCommand` should be `'REQUEST_CAPTURE'` when User A clicks
   - `serviceType` should contain `'video'`
4. Watch for changes when User A clicks "View File"

### Camera Permission Check:
```dart
// In User B's device, check:
await Permission.camera.request().isGranted
await Permission.microphone.request().isGranted
```

## Expected Flow Timeline

| Time | User A | User B (Automatic) |
|------|--------|-------------------|
| 0s | Clicks "View File" | - |
| 0s | Shows loading dialog | GlobalCameraHandler detects `REQUEST_CAPTURE` |
| 1s | Waiting... | Camera initializes with audio enabled |
| 2s | Waiting... | Video recording starts |
| 3-11s | Waiting... | Recording 10 seconds |
| 12s | Waiting... | Recording stops, processing file |
| 13s | Waiting... | Uploading to Supabase |
| 15s | Waiting... | Firestore updated with mediaUrl |
| 16s | Video opens with audio! | Command reset to IDLE |

## New Error Messages

User A will see one of these error messages if timeout occurs:

1. **"Video recording in progress but not completed yet"**
   - Meaning: Command was sent but video not uploaded yet
   - Action: Wait a bit longer or retry

2. **"Make sure User B has opened the session first"**
   - Meaning: No active command detected
   - Action: User B should accept the request

Both errors now have a **RETRY button** that resends the command.

## Backup Polling Details

The polling timer runs every 3 seconds and:
1. Queries Firestore for all accepted requests with `REQUEST_CAPTURE` command
2. Checks if command timestamp is new (different from last processed)
3. Initializes camera if needed
4. Executes video recording

This ensures that even if the snapshot listener fails, commands will be picked up within 3 seconds.

## Key Code Changes

### global_camera_listener.dart:
- Line 163: `enableAudio: isVideo` - Audio enabled for videos
- Line 41: `_startBackupPolling()` - Backup mechanism started
- Line 93: Query includes active commands: `return inTimeWindow || hasActiveCommand`

### chat_screen.dart:
- Line 297: Timeout extended to 25 seconds
- Line 327: Better error messages with retry button

### view_session_screen.dart:
- Line 377: `_controller.setVolume(1.0)` - Audio enabled by default
- Line 446: Mute/unmute button with volume toggle

## Next Steps if Still Failing

1. **Run both devices with USB debugging**
2. **Capture full logs from User B's device** when User A clicks "View File"
3. **Share the logs** - look for any errors or exceptions
4. **Verify Firestore rules** allow read/write on requests collection
5. **Check Supabase bucket** has correct permissions for uploads
