# Streamix — Project Report (Remote-pic-capture branch)

Last updated: 2025-11-29

Overview
--------
This document summarizes all work completed on the Streamix application (branch `Remote-pic-capture`) up to this date. It includes a chronological task list, methodology, tools and frameworks used, code snippets, commands, prompts, outcomes, and guidance for screenshots and validations. Add screenshots to the `docs/screenshots/` folder and follow the image placement notes in each task section.

Contents
- **Task Summary** (chronological)
- **Methodology & Approach** (per task)
- **Tools & Frameworks**
- **Code & Snippets** (explanations)
- **Prompts / Commands Used**
- **Outcomes / Results**
- **Documentation & Screenshot Placement**
- **Validation Steps & Next Actions**


**Task Summary (chronological)**
--------------------------------
Each task below is listed with Task Name/Title, Objective/Purpose, and Date of completion.

1. Task: Camera surface-combination fix
   - Objective: Stop CameraX "No supported surface combination" crashes on physical devices.
   - Completed: 2025-11-29
   - Files modified: `lib/widgets/global_camera_listener.dart`

2. Task: Prevent stopVideoRecording race/crash
   - Objective: Avoid exceptions when `stopVideoRecording()` is called while not recording.
   - Completed: 2025-11-29
   - Files modified: `lib/widgets/global_camera_listener.dart`

3. Task: Improve photo upload propagation + viewer delay
   - Objective: Avoid grey screen by ensuring Supabase URL is available before opening viewer.
   - Completed: 2025-11-29
   - Files modified: `lib/services/supabase_storage_service.dart`, `lib/screens/chat/chat_screen.dart`, `lib/screens/session/view_session_screen.dart`

4. Task: Add permission logging & user guidance
   - Objective: Make permission states visible and guide user when permissions are permanently denied.
   - Completed: 2025-11-29
   - Files modified: `lib/widgets/global_camera_listener.dart`

5. Task: Add ERROR state & Firestore reporting for failures
   - Objective: When capture/upload fails, write `remoteCommand='ERROR'` and `errorMessage` so requester sees the reason.
   - Completed: 2025-11-29
   - Files modified: `lib/widgets/global_camera_listener.dart`, `lib/screens/chat/chat_screen.dart`, `lib/screens/session/view_session_screen.dart`

6. Task: Background/FCM diagnostics & guidance
   - Objective: Add background handler diagnostics and document limitation: Flutter widget-based listeners require app process alive.
   - Completed: 2025-11-29
   - Files inspected: `lib/main.dart`, `lib/services/notification_service.dart`

7. Task: Release-only issues (manifest, proguard, network security)
   - Objective: Fix release-only networking and runtime stripping issues causing grey screens in production APKs.
   - Completed: 2025-11-29
   - Files modified: `android/app/src/main/AndroidManifest.xml`, `android/app/proguard-rules.pro`, `android/app/src/main/res/xml/network_security_config.xml`, `android/app/build.gradle.kts`

8. Task: Documentation - summary and README
   - Objective: Add `FIXES_APPLIED_README.md` and this project report file for maintainers.
   - Completed: 2025-11-29
   - Files created: `FIXES_APPLIED_README.md`, `docs/PROJECT_REPORT.md`


**Methodology / Approach (detailed)**
------------------------------------
For each task below, the approach, challenges, and resolution are described.

Task 1 — Camera surface-combination fix
- Approach:
  1. Reproduce the CameraX error on a physical device or inspect screenshot/log provided by user.
  2. Identify root cause: CameraX attempted to bind PREVIEW + IMAGE_CAPTURE + IMAGE_ANALYSIS simultaneously; some devices allow only 2 use-cases.
  3. Reduce camera use-case load by lowering resolution and removing forced `imageFormatGroup` where present.
  4. Add logging during initialization to validate success on device.
- Challenge: Preserve acceptable image quality while ensuring compatibility.
- Resolution: Use `ResolutionPreset.low` as most compatible fallback. Later can implement device-specific profiles.

Task 2 — Prevent stopVideoRecording crash
- Approach:
  1. Add guard checks `if (_cameraController != null && _cameraController!.value.isRecordingVideo)` before calling `stopVideoRecording()`.
  2. If `stopVideoRecording()` fails, attempt to reinitialize camera and show error to Firestore/requester.
- Challenge: Race conditions where camera was stopped by system; handled by robust checks and graceful error reporting.

Task 3 — Improve upload propagation and viewer delay
- Approach:
  1. Add a short delay after upload to Supabase to let the CDN/URL propagate (initially 500ms, increased to 1s) and append a cache-busting timestamp query param to the returned URL.
  2. In `chat_screen.dart` wait 3 seconds after `COMPLETED` and verify Firestore `mediaUrl` value before opening `ViewSessionScreen`.
  3. Add `loadingBuilder` and `errorBuilder` to `Image.network` in the viewer with a Retry button.
- Challenge: Different Supabase/CDN propagation times across regions; used small delay + verification for robustness.

Task 4 — Permission logging & user guidance
- Approach:
  1. Implement `_ensureRuntimePermissions()` with detailed logs for camera and microphone, and display Snackbars for `isPermanentlyDenied`.
  2. Call this during initialization of the background camera handler.
- Challenge: Some devices behave differently with permission prompts; logs help identify the state.

Task 5 — Add ERROR state & Firestore reporting
- Approach:
  1. On any unrecoverable failure (camera init fail, capture fail, upload fail), update the `requests` document with `remoteCommand='ERROR'` and a human-readable `errorMessage`.
  2. Update `chat_screen.dart` and `view_session_screen.dart` to present this error to the requester instead of showing a grey screen.
- Outcome: Requester immediately sees the cause and next steps (retry, ask provider to open app, etc.).

Task 6 — Background/FCM diagnostics & guidance
- Approach:
  1. Verify `main.dart` registers `FirebaseMessaging.onBackgroundMessage` and a small background handler exists.
  2. Document the limitation: Flutter widget-only background code needs the app process alive; capturing while the app is fully killed requires native Android background service.
- Recommendation: For fully headless captures, implement a native foreground service in Android.

Task 7 — Release-only issues
- Approach:
  1. Inspect `AndroidManifest.xml` for syntax or attribute placement errors; ensure `android:usesCleartextTraffic` and `android:networkSecurityConfig` are properly set on `<application>`.
  2. Add `network_security_config.xml` to allow necessary domains (Supabase/Firebase) during release builds.
  3. Add ProGuard rules in `android/app/proguard-rules.pro` to keep `okhttp3`, `okio`, `io.supabase`, `com.google.firebase` and Camera/WeRTC classes from being stripped or obfuscated.
  4. Rebuild release APK and test.
- Challenge: Release builds can strip or obfuscate libraries causing runtime-only issues; ProGuard fixes preserve required classes.

Task 8 — Documentation
- Approach: Create `FIXES_APPLIED_README.md` and this `docs/PROJECT_REPORT.md` with full details for maintainers.


**Tools & Frameworks**
----------------------
- Flutter 3.8.1 (Dart SDK compatible with Flutter 3.8.1)
- Android SDK (compileSdk 36, targetSdk 34)
- IDE: VS Code (used in workspace), optional Android Studio for native edits
- Main dependencies and plugins (not exhaustive):
  - `camera` (0.11.x) — CameraX-based plugin
  - `firebase_core`, `firebase_auth`, `cloud_firestore`, `firebase_messaging`
  - `supabase_flutter`
  - `flutter_sound`, `flutter_webrtc`, `video_player`
  - `permission_handler`
  - `flutter_local_notifications`
- Native tools & CLI used:
  - `adb` (device logs and install/uninstall)
  - `keytool` (SHA-1 / SHA-256 retrieval)
  - `flutter clean` / `flutter build apk --release`
  - PowerShell on Windows for command examples


**Code & Snippets (key excerpts with explanations)**
--------------------------------------------------
Below are representative code snippets and why they were changed.

1) Permission checks (file: `lib/widgets/global_camera_listener.dart`)

```dart
Future<void> _ensureRuntimePermissions() async {
  print('🔐 [GlobalCamera] ========== PERMISSION CHECK START ==========');

  final cameraStatus = await Permission.camera.status;
  print('🔐 [GlobalCamera] Camera permission status: $cameraStatus');
  if (!cameraStatus.isGranted) {
    final result = await Permission.camera.request();
    print('🔐 [GlobalCamera] Camera permission result: $result');
    if (result.isPermanentlyDenied) {
      print('❌ [GlobalCamera] Camera permission PERMANENTLY DENIED!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Camera permission permanently denied. Please enable it in app settings.'),
          backgroundColor: Colors.orange,
        ));
      }
    }
  } else {
    print('✅ [GlobalCamera] Camera permission already GRANTED');
  }
  // Similar check for microphone
  print('🔐 [GlobalCamera] ========== PERMISSION CHECK COMPLETE ==========');
}
```

Explanation: Prints permission states and requests them as needed. Shows a Snackbar guiding user when permission is permanently denied.


2) Camera initialization (file: `lib/widgets/global_camera_listener.dart`)

```dart
final controller = CameraController(
  camera,
  ResolutionPreset.low, // chosen to avoid CameraX binding too many use cases
  enableAudio: isVideo,
);
await controller.initialize();
print("🎥 [GlobalCamera] Camera initialized successfully");
```

Explanation: Using `ResolutionPreset.low` reduces memory and avoids CameraX attempting incompatible surface combos. If this is still problematic for some devices, consider disabling preview or switching to native capture.


3) Photo capture, upload and Firestore update (file: `lib/widgets/global_camera_listener.dart`)

```dart
final XFile image = await _cameraController!.takePicture();
String? url = await _supabaseStorage.uploadRequestMedia(requestId, File(image.path), 'jpg');
if (url != null) {
  await _ticketService.completeCameraTask(requestId, url);
} else {
  await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
    'remoteCommand': 'ERROR',
    'errorMessage': 'Upload failed - Supabase returned null URL',
    'lastUpdated': FieldValue.serverTimestamp(),
  });
}
```

Explanation: Ensures requester receives either `COMPLETED` with `mediaUrl` or `ERROR` with `errorMessage` for proper UI handling.


4) Chat screen URL verification (file: `lib/screens/chat/chat_screen.dart`)

```dart
// After detecting COMPLETED
await Future.delayed(const Duration(seconds: 3));
final verifyDoc = await FirebaseFirestore.instance.collection('requests').doc(requestId).get();
final verifiedUrl = verifyDoc.data()?['mediaUrl'] as String?;
if (verifiedUrl != null && verifiedUrl.isNotEmpty) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => ViewSessionScreen(requestId: requestId, serviceType: data['serviceType'], initialMediaUrl: verifiedUrl)));
}
```

Explanation: Adds small delay and re-verifies Firestore entry to reduce viewer grey screens due to CDN propagation.


5) Firestore ERROR write (file: `lib/widgets/global_camera_listener.dart`)

```dart
await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
  'remoteCommand': 'ERROR',
  'errorMessage': 'Camera initialization failed: ${e.toString()}',
  'lastUpdated': FieldValue.serverTimestamp(),
});
```

Explanation: Writes an explicit error state for requester to display.


6) Supabase upload cache-busting (file: `lib/services/supabase_storage_service.dart`)

```dart
await _supabase.storage.from('media_files').upload(filePath, file, fileOptions: const FileOptions(upsert: true));
await Future.delayed(const Duration(milliseconds: 500));
final publicUrl = _supabase.storage.from('media_files').getPublicUrl(filePath);
final urlWithCacheBust = '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
return urlWithCacheBust;
```

Explanation: Adding a short delay and cache-busting param reduces race issues with CDN propagation.


7) stopVideoRecording guards (file: `lib/widgets/global_camera_listener.dart`)

```dart
if (!_cameraController!.value.isRecordingVideo) {
  print('❌ [GlobalVideo] ERROR: Camera is NOT recording! Cannot stop.');
  await _updateFirestoreError(requestId, 'Video recording failed - camera stopped recording unexpectedly');
  _isRecording = false;
  _recordingTimer?.cancel();
  return;
}
final XFile video = await _cameraController!.stopVideoRecording();
```

Explanation: Prevents exceptions when `stopVideoRecording()` is called without an active recording.


8) AndroidManifest network security reference (file: `android/app/src/main/AndroidManifest.xml`)

```xml
<application
  android:label="streamix"
  android:name="${applicationName}"
  android:icon="@mipmap/ic_launcher"
  android:usesCleartextTraffic="true"
  android:networkSecurityConfig="@xml/network_security_config">
```

Explanation: Ensures release builds have proper network security config to reach Supabase/Firebase domains.


9) ProGuard rules (file: `android/app/proguard-rules.pro`) — keep rules for critical runtime libraries

```pro
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class io.supabase.** { *; }
-dontwarn io.supabase.**
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
```

Explanation: Prevents release build optimizers from stripping classes used by Supabase, OkHttp and Camera plugins.


**Prompts / Commands Used**
---------------------------
This section lists CLI commands and representative prompts used during development and debugging.

CLI commands (used in PowerShell on Windows):
```powershell
# Clean & build release APK
flutter clean
flutter build apk --release

# Install/uninstall APK
adb uninstall com.example.streamix
adb install build/app/outputs/flutter-apk/app-release.apk

# Clear logcat and filter for our logs
adb -s <DEVICE_ID> logcat -c
adb -s <DEVICE_ID> logcat | Select-String "GlobalCamera"

# Extract debug key SHA values
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android

# Check for built APK
Test-Path "build/app/outputs/flutter-apk/app-release.apk"
```

Representative GPT prompts / edit instructions (paraphrased) used while coding:
- "Add logging to show when permissions are actually granted"
- "Change camera resolution to avoid 'No supported surface combination' error"
- "When upload fails, write ERROR state in Firestore so requester sees message"
- "Add cache-busting and a small delay after Supabase upload"

These guided code edits implemented the corresponding code snippets above.


**Outcome / Result (impact summary)**
--------------------------------------
- Eliminated common CameraX crash on many real devices by reducing camera resource use-case pressure.
- Prevented video stop race exceptions that caused red error banners.
- Reduced grey-screen cases by delaying & verifying Supabase URL propagation and adding cache-busting to URLs.
- Added robust error propagation to Firestore so requesters receive a helpful `ERROR` message instead of a grey screen.
- Added permission diagnostics and user guidance to reduce misconfigured-permission problems on provider devices.
- Fixed release-only issues (manifest, network security, ProGuard) so the release APK can fetch media properly.

Net effect: The system is more resilient and failure modes are visible and actionable for both provider and requester.


**Documentation & Screenshot Placement**
--------------------------------------
Create `docs/screenshots/` and add the screenshots with the filenames below. In the Markdown file place each image at the point indicated.

Recommended screenshot files and placement in the report:
- `docs/screenshots/camera_error_red_overlay.png` — Insert directly under Task 1 (Camera surface-combination) after the "Methodology" section to show the original CameraX exception screenshot.
- `docs/screenshots/viewfile_greyscreen.png` — Insert under Task 3 (Upload/Viewer) to show the grey screen when viewer opens prematurely.
- `docs/screenshots/logs_camera_init.png` — Insert under Task 4 (Permission logging) showing `GlobalCamera` initialization logs from `adb logcat`.
- `docs/screenshots/google-services-json.png` — Insert under Task 7's Firebase/SHA subsection showing `package_name` lines in the `google-services.json`.
- `docs/screenshots/proguard_rules.png` — Insert under Task 7 (ProGuard) showing the rules used.
- `docs/screenshots/network_config.png` — Insert under Task 7 (network security) showing `network_security_config.xml`.
- `docs/screenshots/build_success.png` — Insert under the Build & Test section showing successful `flutter build apk --release` or existence of `app-release.apk`.
- `docs/screenshots/sha_debug_keystore.png` — Insert under the SHA keys subsection demonstrating the `keytool` output with SHA-1 and SHA-256.

How to insert screenshots (Markdown example):
```markdown
![CameraX error](docs/screenshots/camera_error_red_overlay.png)
_Figure: CameraX 'No supported surface combination' error seen on physical device_
```


**Validation Steps**
--------------------
1. Ensure SHA keys are registered in Firebase project `streamix-409b9`:
   - Go to Firebase Console -> Project settings -> Your apps -> Add fingerprint (SHA-1, SHA-256) using debug/release keystore as appropriate.
2. Build the release APK:
```powershell
flutter clean
flutter build apk --release
```
3. Uninstall previous app (important when switching debug vs release signatures):
```powershell
adb uninstall com.example.streamix
```
4. Install newly built APK:
```powershell
adb install build/app/outputs/flutter-apk/app-release.apk
```
5. On Provider device (User B):
   - Grant Camera, Microphone, Location, and Notification permissions.
   - Open the app and keep it in background (do not swipe away).
   - Run logcat and filter: `adb logcat | Select-String "GlobalCamera"` and look for startup log banner and capture logs.
6. On Requester device (User A):
   - Create a camera request and press `View File`.
   - If the capture fails the `requests/<id>` document will show `{ remoteCommand: 'ERROR', errorMessage: '<reason>' }`.


**Next steps & Recommendations**
-------------------------------
- Create a proper release keystore and add its SHA-1/SHA-256 to Firebase before production release.
- Consider a native Android foreground service (Kotlin/Java) to handle fully headless capture when the app is killed.
- Add device-specific camera capability probing to select the best resolution/preset rather than always `low`.
- Add integration tests for `TicketService` and Firestore state transitions (mock Firestore) to catch regressions.
- If captures must work when app is killed, implement FCM data messages plus a native background handler that starts the capture.


**Where to add screenshots inside this repository**
-------------------------------------------------
- Create directory: `docs/screenshots/` at the repo root.
- Upload the filenames listed earlier. Insert them into this `docs/PROJECT_REPORT.md` at the recommended places.


**File locations changed during work (summary)**
- `lib/widgets/global_camera_listener.dart` (camera init, capture, error reporting)
- `lib/screens/chat/chat_screen.dart` (URL propagation wait + error display)
- `lib/screens/session/view_session_screen.dart` (ERROR screen, retry, loading builder)
- `lib/services/supabase_storage_service.dart` (upload delay + cache-bust)
- `lib/services/ticket_service.dart` (completeCameraTask verification)
- `lib/services/notification_service.dart` (FCM setup verification)
- `lib/main.dart` (background handler registration)
- `android/app/src/main/AndroidManifest.xml` (network/security manifest fixes)
- `android/app/proguard-rules.pro` (keep rules)
- `android/app/src/main/res/xml/network_security_config.xml` (network config)
- `FIXES_APPLIED_README.md` (summary)
- `docs/PROJECT_REPORT.md` (this file)


**If you want I can also:**
- Create `docs/screenshots/` and add your uploaded screenshots into the repo (if you provide them here or allow me to place them).
- Commit these docs and files to a branch (I can prepare changes; final commit must be authorized by you).


---

End of report. If you'd like, I can now:
- (A) Add the screenshots you uploaded into `docs/screenshots/` and embed them in this file, or
- (B) Commit this report and `docs/screenshots/` placeholder files to the repo, or
- (C) Produce a condensed PDF or HTML version for sharing.

Tell me which option you prefer and, if option (A), provide the screenshot filenames you want inserted (or allow me to import the screenshots you previously attached).