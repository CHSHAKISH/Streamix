# Streamix Testing Guide - Live Streaming Features

## 📱 Installation

### Release APK Location
```
D:\Projects\streamix\build\app\outputs\flutter-apk\app-release.apk
```

### Install on Device
```powershell
# Connect device via USB and enable USB debugging
adb install -r build\app\outputs\flutter-apk\app-release.apk
```

## 🧪 Test Scenarios

### Test 1: Front Camera Live Stream ✅

**Setup:**
- Device A (Viewer - User A): Person requesting stream
- Device B (Broadcaster - User B): Person sharing camera

**Steps:**

1. **User A (Viewer):**
   - Open Streamix app
   - Navigate to chat with User B
   - Send request: Select "Front Camera Stream"
   - Set time window (now → +1 hour)
   - Send request

2. **User B (Broadcaster):**
   - Receive notification
   - Open Streamix app
   - See request notification
   - Tap request → Tap "Accept"
   - **Expected:** ActiveSessionScreen opens
   - **Expected:** See your own front camera preview immediately
   - **Expected:** Status shows "Broadcasting - User A can now view"

3. **User A (Viewer):**
   - In chat, tap the request message
   - Tap "View Live / File" button
   - **Expected:** LiveStreamViewerScreen opens
   - **Expected:** See "Connecting..." for 2-3 seconds
   - **Expected:** See User B's front camera feed (full screen)
   - **Expected:** Hear User B's voice through speaker
   - **Expected:** Image is mirrored (front camera)

4. **Test Audio:**
   - User B: Say something near the phone
   - User A: Should hear it clearly
   - User A: Tap mute button (🎤 icon in top bar)
   - **Expected:** Red "Muted" badge appears
   - **Expected:** No audio heard
   - User A: Tap unmute
   - **Expected:** Audio returns

5. **Stop Stream (User A stops):**
   - User A: Tap "STOP VIEWING" button
   - **Expected:** Viewer screen closes, returns to chat
   - **Expected:** User B sees notification "Stream stopped by User A"
   - **Expected:** User B's ActiveSessionScreen closes after 1 second

### Test 2: Back Camera Live Stream ✅

**Steps:**
1. Repeat Test 1, but select "Back Camera Stream" instead
2. **Expected:** User A sees User B's rear camera view
3. **Expected:** Image is NOT mirrored (back camera)
4. All other behaviors same as Test 1

### Test 3: Stop Stream from Broadcaster ✅

**Steps:**
1. Start any stream (front or back)
2. Establish connection (User A viewing User B)
3. **User B:** Tap "STOP SHARING" button in ActiveSessionScreen
4. **Expected on User B:**
   - See green snackbar: "Stopped sharing camera"
   - Screen closes immediately
5. **Expected on User A:**
   - See message: "User B stopped sharing"
   - Red camera-off icon displayed
   - "Close" button appears
   - Can tap to return to chat

### Test 4: Retry Logic (Black Screen Recovery) ✅

**Scenario:** Connection doesn't establish on first try

**Steps:**
1. Start stream request
2. User A opens viewer
3. **If you see black screen:**
   - Wait and observe status message
   - After 6 seconds: "No remote stream yet — re-sending viewerReady (attempt 1)"
   - System automatically retries up to 3 times
   - **Expected:** Connection establishes within 18 seconds
   - **Expected:** Video and audio start working

**Manual verification:**
- Check device logs (see below) for retry markers
- Verify `viewerRetry` field increments in Firestore

### Test 5: Multiple Sessions ✅

**Steps:**
1. Complete a stream session (start → stop)
2. Send a NEW stream request
3. User B accepts
4. User A views again
5. **Expected:** Works exactly like first session
6. **Expected:** No leftover state from previous session

### Test 6: Network Interruption 🔄

**Steps:**
1. Establish stream connection
2. User A: Enable airplane mode for 5 seconds
3. User A: Disable airplane mode
4. **Expected:** May need to stop and restart stream
5. **Future improvement:** Auto-reconnection

## 📊 Monitoring & Logs

### Capture Device Logs

**Full logs:**
```powershell
adb logcat > streamix_test_log.txt
```

**Flutter logs only:**
```powershell
adb logcat | Select-String -Pattern "flutter"
```

**WebRTC logs only:**
```powershell
adb logcat | Select-String -Pattern "WebRTC|onTrack|ICE|offer|answer"
```

### Key Log Markers

**✅ Successful Connection:**
```
📡 Viewer ready signal received
📤 Creating fresh offer for viewer
✅ Offer created and sent
📺 Remote track received: video
📺 Remote track received: audio
🔊 Audio track explicitly enabled
✅ Connected
```

**🔁 Retry in Progress:**
```
🔁 No remote stream yet after 6s — re-sending viewerReady (attempt 1)
📡 Viewer ready signal received, retry: 1
📤 Creating fresh offer for viewer (retry: 1)
```

**❌ Connection Failed:**
```
❌ Error initializing streaming: [error message]
⚠️ Cannot create offer - service not ready
⚠️ Remote stream has no video tracks
```

## 🐛 Troubleshooting

### Problem: Black screen persists after 18 seconds

**Check:**
1. Camera permissions granted on User B's device?
   - Settings → Apps → Streamix → Permissions → Camera (Allow)
2. Microphone permissions granted?
   - Settings → Apps → Streamix → Permissions → Microphone (Allow)
3. Check User B's logs for camera initialization errors
4. Try back camera instead (some devices have issues with front camera)

**Solution:**
- Reinstall app
- Grant all permissions
- Restart devices

### Problem: No audio

**Check:**
1. User B's device not muted?
2. User A's device volume turned up?
3. User A hasn't tapped mute button?
4. Check logs for "Audio track enabled: true"

**Solution:**
- Unmute User A
- Increase volume on User A
- Check audio permissions on User B

### Problem: "Camera initialization failed"

**Check User B's logs for:**
```
❌ Error initializing streaming: CameraException
```

**Common causes:**
- Another app using camera
- Camera hardware issue
- Permissions denied

**Solution:**
- Close other camera apps
- Restart device
- Check permissions

### Problem: Connection establishes but video freezes

**Check:**
- Network quality (weak WiFi/cellular?)
- Device performance (old/slow device?)

**Solution:**
- Move closer to WiFi router
- Switch to better network
- Close other apps

## 🔍 Firestore Verification

### Check Signaling Document

**Path:** `webrtc_signaling/{requestId}`

**Expected fields when connected:**
```javascript
{
  "offer": {
    "type": "offer",
    "sdp": "v=0\no=- ..." // Long SDP string
  },
  "answer": {
    "type": "answer", 
    "sdp": "v=0\no=- ..." // Long SDP string
  },
  "viewerReady": true,
  "viewerTimestamp": Timestamp,
  "viewerRetry": 0 // or 1, 2, 3 if retries occurred
}
```

**Check ICE Candidates:**

**Path:** `webrtc_signaling/{requestId}/candidates`

**Expected:** 5-20 candidate documents with:
```javascript
{
  "candidate": "candidate:...",
  "sdpMid": "0" or "1",
  "sdpMLineIndex": 0 or 1,
  "senderId": "broadcaster" or "viewer",
  "timestamp": Timestamp
}
```

## ✅ Success Criteria

### Connection Establishment
- ✅ Stream connects within 5 seconds (typical: 2-3s)
- ✅ Black screen resolved automatically within 18s if initial connection fails
- ✅ Audio and video both working
- ✅ Full-screen video display

### Audio Quality
- ✅ Clear voice transmission
- ✅ No echo (echo cancellation working)
- ✅ Low latency (< 500ms)
- ✅ Mute/unmute works instantly

### Video Quality
- ✅ Smooth playback (no stuttering)
- ✅ Low latency (< 500ms)
- ✅ Correct camera orientation
- ✅ Full-screen coverage

### Control Functions
- ✅ Stop from viewer (User A) works
- ✅ Stop from broadcaster (User B) works
- ✅ Clean disconnection (no errors)
- ✅ Request status updated correctly

## 📋 Test Checklist

Print this and check off as you test:

- [ ] Front camera stream - First attempt success
- [ ] Front camera stream - Retry recovery works
- [ ] Back camera stream - First attempt success
- [ ] Back camera stream - Retry recovery works
- [ ] Audio clearly audible on viewer
- [ ] Mute/unmute works correctly
- [ ] Stop from viewer works
- [ ] Stop from broadcaster works
- [ ] Firestore signaling document created correctly
- [ ] ICE candidates exchanged
- [ ] No black screen issues
- [ ] No audio issues
- [ ] Multiple sessions work in sequence
- [ ] Both users can see appropriate status messages

## 🎯 Known Issues

### Minor Issues (cosmetic)
- ⚠️ Lots of debug logs (366 analyzer warnings)
  - Not a functional issue
  - Will be cleaned up before production

### Future Improvements
- 🔄 Add TURN server for better NAT traversal
- 🔄 Add connection quality indicators
- 🔄 Add auto-reconnection on network drop
- 🔄 Add video quality settings

## 📞 Reporting Issues

When reporting an issue, please include:

1. **Device info:**
   - Device A model: [e.g., Samsung Galaxy S21]
   - Device B model: [e.g., Pixel 6]
   - Android versions

2. **Steps to reproduce:**
   - Exact sequence of actions
   - Which user experienced the issue

3. **Logs:**
   - Attach `adb logcat` output
   - Screenshot of error (if visible)

4. **Firestore state:**
   - Screenshot of signaling document
   - Screenshot of candidates collection

5. **Expected vs Actual:**
   - What should have happened
   - What actually happened

## 🚀 Quick Start

**Fast test (2 devices ready):**
```
1. Install APK on both devices
2. Login on both devices  
3. User A → Send "Front Stream" request to User B
4. User B → Accept request
5. User A → Tap request → "View Live / File"
6. ✅ Should see User B's front camera + hear audio
7. User A → Tap "STOP VIEWING"
8. ✅ Both devices should close cleanly
```

**Estimated test time:** 2-3 minutes per scenario

**Total comprehensive testing:** ~30 minutes

---

Happy Testing! 🎉
