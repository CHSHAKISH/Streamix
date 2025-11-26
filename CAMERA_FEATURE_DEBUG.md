# Remote Camera Feature - Implementation & Debugging Guide

## ✅ What Was Implemented

### User Flow (Simplified)
1. **User A** clicks "View Live / File" button in chat
2. System automatically triggers photo capture on **User B's** device
3. Photo viewer opens showing "Capturing photo from User B..."
4. Once captured, photo appears in fullscreen viewer
5. **User A** can close viewer and reopen to get fresh photo

### Key Changes Made

#### 1. **chat_screen.dart** - Automatic Trigger
```dart
// For camera services, trigger capture automatically when opening
if (service.contains('camera')) {
  await _ticketService.sendCameraTrigger(requestId);
  // Opens viewer immediately after triggering
  Navigator.push(...);
}
```

#### 2. **view_session_screen.dart** - Simple Photo Viewer
- Removed "VIEW FILE" button
- Shows photo in fullscreen with InteractiveViewer (pinch to zoom)
- Loading indicator while capturing
- Error handling with detailed messages
- Close button (top-right)
- Success indicator (bottom overlay)

#### 3. **global_camera_listener.dart** - Background Capture
- Listens for `remoteCommand: 'REQUEST_CAPTURE'`
- Captures photo silently in background
- Uploads to Supabase storage
- Updates Firestore with `mediaUrl`
- Resets command to 'IDLE' for next trigger

---

## 🔍 Debugging Steps (If Photo Not Visible)

### Step 1: Check Firestore Data
Open Firebase Console → Firestore → `requests` collection → Find your request document:

**Check these fields:**
```
remoteCommand: "COMPLETED" or "IDLE" (should change from REQUEST_CAPTURE)
mediaUrl: "https://your-project.supabase.co/storage/v1/object/public/media_files/..."
commandTimestamp: <Timestamp>
lastUpdated: <Timestamp>
```

**If `mediaUrl` is missing or null:**
- Problem is in the capture/upload flow
- Check GlobalCameraHandler logs in User B's device

### Step 2: Verify Supabase Storage Permissions

#### Option A: Via Supabase Dashboard
1. Go to https://supabase.com/dashboard
2. Select your project
3. Go to **Storage** → **media_files** bucket
4. Click **Policies** tab
5. Ensure policy exists for **SELECT** (read) with:
   ```sql
   Policy Name: Public Read
   Target: SELECT
   Policy Definition: true  (or specific path like storage.foldername(name) = 'public')
   ```

#### Option B: Via SQL Editor
Run this in Supabase SQL Editor:
```sql
-- Create policy for public read access
CREATE POLICY "Public Read Access"
ON storage.objects FOR SELECT
USING (bucket_id = 'media_files' AND (storage.foldername(name))[1] = 'public');

-- Or simpler (allow all reads):
CREATE POLICY "Allow Public Reads"
ON storage.objects FOR SELECT
USING (bucket_id = 'media_files');
```

### Step 3: Test URL Directly
Copy the `mediaUrl` from Firestore and paste in browser:
- **Works?** → Problem is in Flutter Image.network widget
- **403 Forbidden?** → Supabase bucket permissions issue
- **404 Not Found?** → File wasn't uploaded or path is wrong

### Step 4: Check Flutter Logs

**User A's Device** (should show):
```
🔴 User A clicked VIEW FILE button (from chat)
📸 Requesting photo from User B...
```

**User B's Device** (should show):
```
🔴 [GlobalCamera] 🚨 NEW Capture Request!
📸 Captured! Uploading...
✅ Uploaded!
✅ Sent to User A
```

### Step 5: Network Connectivity
Ensure User B's device has:
- ✅ Camera permission granted
- ✅ Internet connection
- ✅ Firestore rules allow writes to `requests` collection

---

## 🛠️ Common Issues & Fixes

### Issue 1: "Image load error: NetworkImageLoadException"
**Cause:** Supabase bucket is not public  
**Fix:** Follow Step 2 above (Verify Storage Permissions)

### Issue 2: Photo is always the same (not updating)
**Cause:** Cache not clearing properly  
**Fix:** Already implemented with `key: ValueKey(mediaUrl + timestamp)`

### Issue 3: Double-click required
**Cause:** Timestamp not being tracked properly  
**Fix:** ✅ Already fixed with `commandTimestamp` tracking

### Issue 4: Black screen or "Failed to load image"
**Possible Causes:**
- URL is malformed (check Firestore value)
- Supabase bucket permissions
- Network timeout
- Image file corrupted during upload

**Debug:**
```dart
// Add this to view_session_screen.dart for debugging
errorBuilder: (context, error, stackTrace) {
  print('🔴 Image URL: $mediaUrl');
  print('🔴 Error: $error');
  print('🔴 Stack: $stackTrace');
  return Center(...);
}
```

---

## 📱 Testing Checklist

### User B (Receiver) Checklist
- [ ] App is open (doesn't need to be on specific screen)
- [ ] Camera permission granted
- [ ] Internet connected
- [ ] Device has working camera
- [ ] GlobalCameraHandler is active (wrapped in main.dart)

### User A (Requester) Checklist
- [ ] Opens chat with User B
- [ ] Can see camera service request
- [ ] Clicks "View Live / File" button
- [ ] Photo viewer opens
- [ ] Loading indicator appears
- [ ] Photo loads within 3-5 seconds

### Expected Timeline
```
00:00s - User A clicks "View Live / File"
00:01s - Firestore updated (REQUEST_CAPTURE)
00:02s - User B's GlobalCameraHandler detects request
00:03s - Photo captured on User B's device
00:04s - Photo uploaded to Supabase
00:05s - Firestore updated (mediaUrl + COMPLETED)
00:06s - User A's viewer shows photo
```

---

## 🔧 Manual Verification Steps

### 1. Verify Supabase URL Format
Should look like:
```
https://[project-ref].supabase.co/storage/v1/object/public/media_files/public/[requestId]/media_[timestamp].jpg
```

### 2. Test Upload Manually
```dart
// In User B's device, add a test button:
ElevatedButton(
  onPressed: () async {
    final service = SupabaseStorageService();
    // Take a test photo
    final camera = await availableCameras().then((cameras) => cameras.first);
    final controller = CameraController(camera, ResolutionPreset.medium);
    await controller.initialize();
    final photo = await controller.takePicture();
    
    // Upload
    final url = await service.uploadRequestMedia('TEST123', File(photo.path), 'jpg');
    print('🔴 TEST URL: $url');
    
    // Try opening in Image.network
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        content: Image.network(url!),
      ),
    );
  },
  child: Text('TEST UPLOAD'),
)
```

### 3. Check Firestore Rules
Ensure rules allow:
```javascript
match /requests/{requestId} {
  // Allow users in the request to read/write
  allow read, write: if request.auth != null && 
    (request.auth.uid == resource.data.userId || 
     request.auth.uid == resource.data.providerId);
}
```

---

## 📊 Architecture Flow

```
┌─────────────────────────────────────────────────────────────┐
│  User A (Requester)                                         │
├─────────────────────────────────────────────────────────────┤
│  1. Chat Screen → Click "View Live / File"                 │
│  2. sendCameraTrigger(requestId)                            │
│     └─> Firestore: remoteCommand = 'REQUEST_CAPTURE'       │
│  3. Navigate to ViewSessionScreen                           │
│  4. StreamBuilder listens to Firestore                      │
│  5. Shows loading while waiting for mediaUrl                │
│  6. Image.network(mediaUrl) displays photo                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Firestore (requests/{requestId})                           │
├─────────────────────────────────────────────────────────────┤
│  remoteCommand: 'REQUEST_CAPTURE' → 'COMPLETED' → 'IDLE'   │
│  commandTimestamp: serverTimestamp()                        │
│  mediaUrl: null → 'https://...'                             │
│  lastUpdated: serverTimestamp()                             │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  User B (Provider)                                          │
├─────────────────────────────────────────────────────────────┤
│  1. GlobalCameraHandler (always listening)                  │
│  2. Detects remoteCommand = 'REQUEST_CAPTURE'              │
│  3. Compares commandTimestamp (skip if old)                 │
│  4. _takePictureAndUpload(requestId)                        │
│  5. CameraController.takePicture()                          │
│  6. SupabaseStorage.uploadRequestMedia()                    │
│  7. completeCameraTask(requestId, url)                      │
│     └─> Firestore: remoteCommand = 'COMPLETED', mediaUrl   │
│  8. Reset: remoteCommand = 'IDLE'                           │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│  Supabase Storage (media_files bucket)                      │
├─────────────────────────────────────────────────────────────┤
│  Path: public/{requestId}/media_{timestamp}.jpg            │
│  Public Read Policy: ✅ Enabled                             │
│  Returns: https://[project].supabase.co/storage/v1/...     │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Next Steps

1. **Test the current implementation** with two devices
2. **Check Supabase dashboard** for uploaded files
3. **Verify Firestore** is updating correctly
4. **Add debug logs** if issues persist
5. **Test network conditions** (WiFi vs mobile data)

---

## 📝 File Locations

- **Main Handler:** `lib/widgets/global_camera_listener.dart`
- **Chat Trigger:** `lib/screens/chat/chat_screen.dart` (line ~237)
- **Photo Viewer:** `lib/screens/session/view_session_screen.dart` (line ~52)
- **Storage Service:** `lib/services/supabase_storage_service.dart`
- **Ticket Service:** `lib/services/ticket_service.dart`

---

## ✨ Feature Summary

**What User B Sees:**
- Nothing changes! App works normally
- May see toast: "⚡ Taking Silent Picture..." (brief)
- May see toast: "✅ Sent to User A" (brief)

**What User A Sees:**
- Chat button: "View Live / File" (eye icon)
- Clicks → Fullscreen photo viewer opens
- Loading indicator while capturing
- Photo appears (can pinch to zoom)
- Close button to dismiss
- Click again → NEW photo captured!

**Technical Benefits:**
- ✅ Automatic capture (no User B interaction)
- ✅ Background operation (doesn't interrupt User B)
- ✅ Fresh photo on each request
- ✅ Cache-proof updates
- ✅ Error handling with user feedback
- ✅ Clean fullscreen UI
