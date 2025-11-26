# Live Streaming Feature Implementation

## Overview
Successfully implemented live video streaming between User A (viewer) and User B (broadcaster) using WebRTC technology for the `front_stream` and `back_stream` services.

## Architecture

### 1. WebRTC Service (`lib/services/webrtc_service.dart`)
- **Purpose**: Manages WebRTC peer-to-peer connections for real-time video streaming
- **Key Features**:
  - Peer connection management with STUN servers
  - Local media stream capture (broadcaster)
  - Remote media stream reception (viewer)
  - ICE candidate exchange via Firestore
  - SDP offer/answer signaling via Firestore
  - Audio mute/unmute functionality
  - Automatic cleanup of Firestore signaling data

#### Signaling Flow:
1. User B (broadcaster) creates WebRTC service with `isInitiator: true`
2. Broadcaster captures local camera stream and creates an SDP offer
3. Offer is stored in Firestore: `webrtc_signaling/{requestId}/offer`
4. User A (viewer) creates WebRTC service with `isInitiator: false`
5. Viewer listens for offer and creates SDP answer
6. Answer is stored in Firestore: `webrtc_signaling/{requestId}/answer`
7. Both peers exchange ICE candidates via `webrtc_signaling/{requestId}/candidates/`
8. Connection establishes and video stream flows from broadcaster to viewer

### 2. Live Stream Viewer Screen (`lib/screens/session/live_stream_viewer_screen.dart`)
- **User**: User A (viewer)
- **Purpose**: View live camera feed from User B
- **Features**:
  - Real-time video display using `RTCVideoView`
  - Mute/unmute audio button (controls received audio)
  - Connection status indicator
  - Stop viewing button (stops stream for User A)
  - Automatic cleanup on disposal
  - Firestore listener for broadcaster stopping stream

#### UI Components:
- **AppBar**: Title + Mute/Unmute button
- **Video Display**: Full-screen RTCVideoView with mirror effect for front camera
- **Status Messages**: 
  - "Connecting..." while establishing connection
  - "Waiting for stream..." if no video yet
  - "User B stopped sharing" if broadcaster ends stream
- **Mute Indicator**: Red badge overlay when audio is muted
- **Stop Button**: Red button at bottom to stop viewing

### 3. Active Session Screen (`lib/screens/session/active_session_screen.dart`)
- **User**: User B (broadcaster)
- **Purpose**: Broadcast camera feed to User A
- **Features**:
  - Automatic WebRTC initialization for stream services
  - Camera selection (front/back based on service type)
  - Local video preview using `RTCVideoView`
  - Automatic offer creation
  - Stop Sharing button to end stream
  - Status messages for User A viewing

#### Streaming Initialization:
```dart
1. Detect stream service type (front_stream/back_stream)
2. Initialize RTCVideoRenderer for local preview
3. Get appropriate camera (front or back)
4. Create WebRTCService as broadcaster (isInitiator: true)
5. Initialize with camera ID
6. Create and send SDP offer
7. Display local camera preview to User B
```

### 4. Global Camera Listener Updates (`lib/widgets/global_camera_listener.dart`)
- **Change**: Stream services are now **skipped entirely**
- **Reason**: WebRTC handles camera directly in ActiveSessionScreen
- **Impact**: 
  - No REQUEST_CAPTURE trigger needed for streams
  - Camera stays active via WebRTC, not GlobalCameraHandler
  - Simpler flow: Accept request → ActiveSessionScreen handles everything

## User Experience

### For User A (Viewer):
1. Click "View File" button on stream request in chat
2. Automatically navigates to LiveStreamViewerScreen
3. See "Connecting..." status while WebRTC establishes connection
4. Once connected, see live video feed from User B's camera
5. Use mute button to control received audio
6. Click "STOP VIEWING" to end stream

### For User B (Broadcaster):
1. Receive and accept stream request (front_stream or back_stream)
2. Navigate to ActiveSessionScreen
3. Camera automatically initializes via WebRTC
4. See local camera preview on screen
5. Status shows "User A is viewing your live stream..."
6. Click "STOP SHARING" to end stream

## Technical Details

### Camera Selection
- **Front Stream**: Uses `CameraLensDirection.front`
- **Back Stream**: Uses `CameraLensDirection.back`
- Camera name is passed to WebRTC `getUserMedia()` as device constraint

### Video Display
- **Mirror Effect**: Front camera videos are mirrored for natural preview
- **Object Fit**: Cover mode for full-screen display
- **Renderer**: RTCVideoRenderer from flutter_webrtc package

### Audio Control
- **Mute/Unmute**: Disables/enables audio tracks on the remote stream
- **Visual Feedback**: Red badge appears when muted
- **Icon Toggle**: Mic icon changes to mic_off when muted

### Connection Management
- **STUN Servers**: Google STUN servers for NAT traversal
- **Signaling**: Firestore real-time database for SDP and ICE exchange
- **Cleanup**: Automatic disposal of peer connections and Firestore data
- **Error Handling**: Connection state monitoring and failure messages

## Firestore Structure

### Main Signaling Document
```
webrtc_signaling/{requestId}/
  - offer: {type, sdp}
  - answer: {type, sdp}
  - timestamp: serverTimestamp
```

### ICE Candidates Subcollection
```
webrtc_signaling/{requestId}/candidates/{auto-id}/
  - candidate: string
  - sdpMid: string
  - sdpMLineIndex: number
  - senderId: "broadcaster" | "viewer"
  - timestamp: serverTimestamp
```

## Dependencies Used
- `flutter_webrtc: ^1.2.0` - WebRTC implementation
- `cloud_firestore` - Signaling server
- `camera` - Camera device enumeration

## Key Differences from Camera/Video Services

| Feature | Camera/Video | Stream |
|---------|--------------|--------|
| Trigger Method | REQUEST_CAPTURE | Automatic on accept |
| Camera Handler | GlobalCameraListener | WebRTC Service |
| Duration | One-time capture | Continuous until stopped |
| Storage | Supabase (static file) | Real-time P2P |
| User B Action | Automatic capture | Manual stop only |
| Viewer UI | ViewSessionScreen | LiveStreamViewerScreen |

## Testing Checklist

✅ **Implemented Features:**
- [x] WebRTC service with peer connection
- [x] Signaling via Firestore
- [x] Broadcaster local stream capture
- [x] Viewer remote stream display
- [x] Mute/unmute audio control
- [x] Local video preview for broadcaster
- [x] Stop viewing/sharing buttons
- [x] Connection status indicators
- [x] Camera selection (front/back)
- [x] GlobalCameraListener skips stream services
- [x] Chat screen routing to LiveStreamViewerScreen

⏳ **To Test:**
1. Accept front_stream request
2. Verify User B sees local camera preview
3. Verify User A sees live video feed
4. Test mute/unmute functionality
5. Test stop sharing from User B
6. Test stop viewing from User A
7. Accept back_stream request and verify back camera
8. Test connection over real network (not just localhost)

## Known Limitations
- Requires good network connection for smooth streaming
- STUN servers only (no TURN for complex NAT scenarios)
- Audio mute only affects received audio (User A muting User B's audio)
- No bandwidth adaptation or quality settings

## Future Enhancements
- Add TURN servers for better connectivity
- Implement video quality controls
- Add bandwidth adaptation
- Two-way video calling (both users streaming)
- Screen recording of streams
- Chat during live stream
