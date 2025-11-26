# 🧪 Camera Feature Testing Checklist

## Pre-Test Setup
- [ ] Two physical devices (or one physical + one emulator)
- [ ] Both devices logged in with different user accounts
- [ ] Camera permissions granted on User B's device
- [ ] Internet connection active on both devices

---

## Test 1: Basic Remote Capture
### User B (Responder)
1. [ ] Receive camera request notification
2. [ ] Open "My Requests" screen
3. [ ] Accept the request
4. [ ] Tap on the accepted request card
5. [ ] See "Camera Ready" message with 📷 icon
6. [ ] See "Keep this app open" instruction
7. [ ] Verify no countdown or auto-capture happens

### User A (Requester)
1. [ ] Open chat with User B
2. [ ] Tap "+" to create request
3. [ ] Select "Front Camera" or "Back Camera"
4. [ ] Set time window (e.g., start in 1 minute, duration 10 minutes)
5. [ ] Send request
6. [ ] Wait for User B to accept
7. [ ] Open the accepted request
8. [ ] See "No image yet" placeholder
9. [ ] See "CAPTURE REMOTE PHOTO" button (red, enabled)
10. [ ] Click the button
11. [ ] Button changes to "WAITING FOR USER B..." (grey, disabled)
12. [ ] Photo appears within 2-5 seconds
13. [ ] Button becomes "CAPTURE REMOTE PHOTO" again (enabled)

### User B (During Capture)
1. [ ] See "User A requested photo - Capturing..." message
2. [ ] See loading spinner
3. [ ] NO shutter sound or flash (silent capture)
4. [ ] See "Photo Sent!" with green checkmark
5. [ ] See "Ready for next capture - Keep app open"

---

## Test 2: Multiple Captures
### User A
1. [ ] After first photo appears, click "CAPTURE REMOTE PHOTO" again
2. [ ] Photo updates to new capture
3. [ ] Repeat 3-5 times
4. [ ] Each capture works correctly

### User B
1. [ ] Each trigger shows "Capturing..." message
2. [ ] Each capture shows "Photo Sent!" confirmation
3. [ ] No need to restart or click anything

---

## Test 3: Session Timing
### Before Start Time
1. [ ] User B opens session before scheduled start
2. [ ] Should see countdown timer
3. [ ] Should NOT allow capture yet

### After Start Time
1. [ ] Countdown reaches zero
2. [ ] Camera becomes ready automatically
3. [ ] User A can trigger capture

### After End Time
1. [ ] Session expires
2. [ ] GlobalCameraHandler releases camera
3. [ ] Capture button disabled on User A side

---

## Test 4: Front vs Back Camera
### Front Camera
1. [ ] Request front camera
2. [ ] Verify User B's front camera is used
3. [ ] Selfie-style photo captured

### Back Camera
1. [ ] Request back camera
2. [ ] Verify User B's back camera is used
3. [ ] Rear-facing photo captured

---

## Test 5: App Lifecycle
### User B Backgrounds App
1. [ ] User B presses Home button (app goes to background)
2. [ ] User A triggers capture
3. [ ] User B returns to app
4. [ ] Verify photo was captured in background

### User B Locks Screen
1. [ ] User B locks device
2. [ ] User A triggers capture
3. [ ] User B unlocks device
4. [ ] Verify capture still works

---

## Test 6: Error Scenarios
### Camera Permission Denied
1. [ ] User B denies camera permission
2. [ ] Verify graceful error message
3. [ ] No app crash

### Network Interruption
1. [ ] User B disconnects internet
2. [ ] User A triggers capture
3. [ ] User B reconnects
4. [ ] Verify photo uploads when connection restored

### Session Closed Early
1. [ ] User B closes ActiveSessionScreen
2. [ ] User A triggers capture
3. [ ] Verify nothing breaks on User A side
4. [ ] Button should remain clickable but no photo appears

---

## Test 7: Multiple Sessions
### Sequential Sessions
1. [ ] Complete one camera session
2. [ ] Start a new camera session immediately
3. [ ] Verify new session works correctly
4. [ ] Old camera hardware released properly

### Different Users
1. [ ] User A requests from User B (Session 1)
2. [ ] User C requests from User B (Session 2)
3. [ ] Verify GlobalCameraHandler handles only one active session
4. [ ] Test priority if both are active

---

## ✅ Success Criteria

### User B Experience
- [ ] Zero manual action required after opening session
- [ ] Clear status messages at each step
- [ ] Silent capture (no shutter sound)
- [ ] No UI freezing or lag
- [ ] Battery efficient (hidden 1x1 preview)

### User A Experience
- [ ] Instant feedback when clicking capture
- [ ] Photo loads quickly (under 5 seconds)
- [ ] Can capture multiple photos easily
- [ ] Button states are clear (enabled/disabled)
- [ ] Network image loading is smooth

### Technical
- [ ] No memory leaks
- [ ] Camera released when session ends
- [ ] Firestore updates propagate correctly
- [ ] No race conditions with rapid captures
- [ ] Supabase uploads complete successfully

---

## 🐛 Known Issues to Test For

1. **Camera Preview Black Screen**
   - If 1x1 preview is not visible, Android may pause camera
   - Verify preview is positioned at (bottom: 0, right: 0)

2. **Duplicate Captures**
   - Test rapid button clicking on User A side
   - Verify no duplicate uploads

3. **Stale Commands**
   - Test if old REQUEST_CAPTURE persists after completion
   - Verify remoteCommand resets to COMPLETED

4. **Permission Timing**
   - Test what happens if permission is requested during capture
   - Verify graceful handling

---

## 📊 Performance Metrics

Track these during testing:

| Metric | Target | Actual |
|--------|--------|--------|
| Capture Latency | < 3 seconds | _____ |
| Upload Time | < 2 seconds | _____ |
| User B Battery Drain | < 5%/hour | _____ |
| Memory Usage (User B) | < 200MB | _____ |
| Firestore Read Operations | < 10/capture | _____ |

---

## 🔧 Debug Tools

### Firestore Console
- Monitor `requests/{id}` document in real-time
- Watch `remoteCommand` field changes
- Verify `mediaUrl` updates correctly

### Logs to Check
```dart
// GlobalCameraHandler
👀 [GlobalCamera] Service Started
🕵️ [GlobalCamera] Initializing Camera Hardware...
✅ [GlobalCamera] HARDWARE READY & HIDDEN
⚡ [GlobalCamera] COMMAND RECEIVED
📸 Captured! Uploading...
✅ Uploaded!

// TicketService
🚀 [TicketService] Setting command to REQUEST_CAPTURE
✅ [TicketService] Task Finished. Updating URL.
```

### VS Code/Android Studio Logs
```bash
# Filter for camera-related logs
adb logcat | grep -i "camera\|streamix\|firestore"
```

---

## ✍️ Test Results Template

**Date:** ___________  
**Tester:** ___________  
**Device A:** ___________  
**Device B:** ___________  

| Test Case | Pass/Fail | Notes |
|-----------|-----------|-------|
| Basic Remote Capture | ☐ | |
| Multiple Captures | ☐ | |
| Session Timing | ☐ | |
| Front Camera | ☐ | |
| Back Camera | ☐ | |
| App Backgrounding | ☐ | |
| Permission Denied | ☐ | |
| Network Issue | ☐ | |

**Critical Issues Found:**
- [ ] None
- [ ] Issue 1: _____________________
- [ ] Issue 2: _____________________

**Overall Status:** ☐ PASS | ☐ FAIL | ☐ NEEDS FIXES

---

*Last Updated: November 26, 2025*
