# Live Streaming Testing Guide

## Prerequisites
- Two devices/emulators running the Streamix app
- Both users logged in and connected to Firebase
- User A has sent a `front_stream` or `back_stream` request to User B

## Step-by-Step Testing

### 1. User B Accepts Request
**Location:** Requests List Screen

**Actions:**
1. User B opens the app
2. Navigate to Requests List
3. See the stream request from User A (front_stream or back_stream)
4. Click the request card
5. Click "Accept" button

**Expected Result:**
- Navigate to ActiveSessionScreen
- See "Checking Schedule..." briefly
- Camera should initialize automatically
- See local camera preview (your own face/environment)
- Status message: "User A is viewing your live stream..."
- "STOP SHARING" button visible at bottom

### 2. User A Views Stream
**Location:** Chat Screen

**Actions:**
1. User A opens the chat with User B
2. Find the accepted stream request message
3. Click "View File" button

**Expected Result:**
- Navigate to LiveStreamViewerScreen  
- See "Connecting..." with spinner
- After 2-5 seconds, see live video feed from User B's camera
- If front_stream: image should be mirrored
- If back_stream: image should not be mirrored
- Mute button visible in app bar

### 3. Test Mute/Unmute
**User:** User A (Viewer)

**Actions:**
1. While viewing stream, click microphone icon in app bar
2. Icon should change to mic_off
3. Red "Muted" badge appears in top-left corner
4. Click mic_off icon again

**Expected Result:**
- Audio from User B's stream is muted (if User B is talking)
- Unmuting restores audio
- Badge disappears when unmuted

### 4. Test Stop Viewing (User A)
**User:** User A (Viewer)

**Actions:**
1. While viewing stream, click "STOP VIEWING" red button at bottom
2. Watch for navigation

**Expected Result:**
- Navigate back to chat screen
- User B's ActiveSessionScreen shows "User stopped viewing" (request status changes)
- WebRTC connection closes cleanly

### 5. Test Stop Sharing (User B)
**User:** User B (Broadcaster)

**Actions:**
1. While streaming, click "STOP SHARING" red button
2. Watch for navigation

**Expected Result:**
- Navigate back to home/requests list
- User A sees "User B stopped sharing" message
- User A's stream automatically closes
- Both WebRTC connections clean up

### 6. Test Back Camera Stream
**Repeat steps 1-5 with `back_stream` service**

**Expected Differences:**
- User B's ActiveSessionScreen shows back camera preview
- User A sees back camera view (environment behind User B)
- Image is NOT mirrored

## What to Look For

### User B (Broadcaster) Screen
✅ Local camera preview visible
✅ Preview matches selected camera (front/back)
✅ No black screen or frozen image
✅ "User A is viewing..." message
✅ Can see "STOP SHARING" button

### User A (Viewer) Screen
✅ Remote video displays after connection
✅ Video is smooth (not laggy)
✅ Audio plays (if User B makes noise)
✅ Mute button works
✅ Front camera is mirrored, back camera is not
✅ Can see "STOP VIEWING" button

### Console Logs to Monitor

**User B (Broadcaster):**
```
📹 Initializing streaming for front_stream...
📷 Selected camera: [camera_id]
🌐 WebRTC initializing... isInitiator: true
✅ WebRTC initialized successfully
✅ Local stream created with 2 tracks
📤 Creating offer...
✅ Offer created and sent
🧊 ICE candidate: ...
📩 Received answer
✅ Answer handled
```

**User A (Viewer):**
```
🌐 WebRTC initializing... isInitiator: false
✅ WebRTC initialized successfully
📩 Received offer
📥 Handling offer...
✅ Answer created and sent
🧊 ICE candidate: ...
📺 Remote track received: video
📺 Remote track received: audio
📺 Remote stream received, setting up renderer
🔗 Connection state: RTCPeerConnectionState.RTCPeerConnectionStateConnected
```

## Common Issues & Solutions

### Issue: Black Screen on User A
**Possible Causes:**
- WebRTC connection not established
- ICE candidates not exchanging
- Camera permission denied on User B's device

**Solutions:**
1. Check console for error messages
2. Verify both devices have internet connection
3. Check User B has granted camera permissions
4. Restart both apps and try again

### Issue: "Connecting..." Never Ends
**Possible Causes:**
- Firestore signaling not working
- Network firewall blocking WebRTC
- STUN servers unreachable

**Solutions:**
1. Check Firebase console for `webrtc_signaling` collection
2. Verify offer and answer documents are created
3. Check if ICE candidates subcollection has documents
4. Try on different network (WiFi vs mobile data)

### Issue: Audio Not Working
**Possible Causes:**
- Microphone permission denied on User B
- Audio tracks not added to stream
- User A's device volume is muted

**Solutions:**
1. Check User B granted microphone permission
2. Verify console shows "Adding track: audio"
3. Unmute User A's device
4. Try mute/unmute toggle

### Issue: Stream Lags or Stutters
**Possible Causes:**
- Poor network connection
- Device performance issues
- High resolution stream

**Solutions:**
1. Check network speed on both devices
2. Move closer to WiFi router
3. Close other apps consuming resources

## Firebase Console Checks

### Requests Collection
```
requests/{requestId}
  - status: "active"
  - remoteCommand: "IDLE" (for streams, no REQUEST_CAPTURE)
  - serviceType: "front_stream" or "back_stream"
  - mediaUrl: null (streams don't upload to Supabase)
```

### WebRTC Signaling Collection
```
webrtc_signaling/{requestId}
  - offer: {type: "offer", sdp: "v=0..."}
  - answer: {type: "answer", sdp: "v=0..."}
  - timestamp: [Firebase Timestamp]

webrtc_signaling/{requestId}/candidates/
  - [auto-id-1]: {candidate: "...", senderId: "broadcaster", ...}
  - [auto-id-2]: {candidate: "...", senderId: "viewer", ...}
  - [auto-id-3]: {candidate: "...", senderId: "broadcaster", ...}
  ...
```

## Performance Metrics

**Expected Connection Time:**
- Initialization: 0-2 seconds
- ICE gathering: 1-3 seconds
- Connection established: 2-5 seconds total

**Expected Video Quality:**
- Resolution: 640x480 to 1280x720 (device dependent)
- Frame rate: 15-30 fps
- Latency: < 500ms over good network

## Test Completion Checklist

- [ ] User B can accept stream request
- [ ] User B sees local camera preview
- [ ] User A can view live stream
- [ ] Video is smooth and clear
- [ ] Audio works (if User B makes sound)
- [ ] Mute/unmute button works
- [ ] User A can stop viewing
- [ ] User B can stop sharing
- [ ] Front camera stream works
- [ ] Back camera stream works
- [ ] Multiple request-accept cycles work
- [ ] Console logs show no errors
- [ ] Firestore signaling data created and cleaned up

## Next Steps After Testing

1. Document any bugs found
2. Test on different networks (WiFi, 4G, 5G)
3. Test with slow network conditions
4. Test connection stability over time (5-10 minutes)
5. Implement any missing error handling
6. Add analytics for connection success rate
