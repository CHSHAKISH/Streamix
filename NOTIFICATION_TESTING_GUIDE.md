# 🧪 Interactive Notification Testing Guide

## Prerequisites

### **1. Two Physical Devices Required**
- ✅ **Device A** (Requester - sends request)
- ✅ **Device B** (Provider - receives request, accepts/rejects)
- ❌ Emulators may have limited FCM support

### **2. Internet Connection**
- Both devices connected to internet (WiFi or mobile data)

### **3. App Installed**
- Release APK installed on both devices
- Both users logged in with different accounts

### **4. Notification Permissions**
- Settings → Apps → Streamix → Notifications → **Enabled**
- Allow all notification types

---

## Test Case 1: App Foreground (Both Users)

### **Setup**
- Device A: App open
- Device B: App open

### **Steps**
1. **Device A**: Open Requests screen → Tap "+" → Select Device B's user → Select service type → Send request
2. **Device B**: Observe notification banner appears **in-app**
3. **Device B**: Tap **"Accept"** button on notification
4. **Device A**: Observe **"Request Accepted ✅"** notification appears

### **Expected Results**
- ✅ Device B sees interactive notification banner with Accept/Reject buttons
- ✅ Device B taps Accept → Request status updates to "accepted"
- ✅ Device A receives "Request Accepted" notification immediately
- ✅ Both devices show updated status in Requests List

---

## Test Case 2: App Background (Device B)

### **Setup**
- Device A: App open
- Device B: App **minimized** (press Home button, don't swipe away)

### **Steps**
1. **Device A**: Send request to Device B
2. **Device B**: Observe **system notification** appears in notification shade
3. **Device B**: Pull down notification shade → See Accept/Reject buttons
4. **Device B**: Tap **"Reject"** button
5. **Device A**: Observe **"Request Denied ❌"** notification

### **Expected Results**
- ✅ Device B receives system notification with action buttons
- ✅ Device B can tap Reject without opening app
- ✅ Request status updates to "denied"
- ✅ Device A receives "Request Denied" notification
- ✅ App doesn't open when Reject is tapped

---

## Test Case 3: App Terminated (Device B)

### **Setup**
- Device A: App open
- Device B: App **completely closed** (swipe away from recent apps)

### **Steps**
1. **Device A**: Send request to Device B
2. **Device B**: Wait 5-10 seconds → Observe notification
3. **Device B**: Pull down notification shade → See notification with actions
4. **Device B**: Tap **"Accept"** button
5. **Device B**: App opens automatically
6. **Device A**: Observe **"Request Accepted ✅"** notification

### **Expected Results**
- ✅ Device B receives notification even when app is killed
- ✅ Background handler processes the message
- ✅ Device B taps Accept → App opens to Requests screen
- ✅ Request status updates to "accepted"
- ✅ Device A receives result notification

---

## Test Case 4: Both Apps Closed

### **Setup**
- Device A: App open (will close after sending)
- Device B: App completely closed

### **Steps**
1. **Device A**: Send request to Device B
2. **Device A**: Close app (swipe away)
3. **Device B**: Receive notification → Tap **"Accept"**
4. **Device B**: App opens
5. **Device A**: Open app later → Check notification history

### **Expected Results**
- ✅ Device B receives notification when closed
- ✅ Device B accepts request successfully
- ✅ Device A receives notification (stored by FCM)
- ✅ When Device A opens app, notification appears

---

## Test Case 5: Multiple Requests

### **Setup**
- Device A: App open
- Device B: App minimized
- Device C: App open (optional, for 3-way test)

### **Steps**
1. **Device A**: Send request to Device B (Service: Video Recording)
2. **Device A**: Send another request to Device B (Service: Live Streaming)
3. **Device B**: Observe 2 separate notifications
4. **Device B**: Accept first request
5. **Device B**: Reject second request
6. **Device A**: Observe 2 result notifications

### **Expected Results**
- ✅ Device B receives 2 independent notifications
- ✅ Each notification has its own Accept/Reject buttons
- ✅ Actions for each notification work independently
- ✅ Device A receives 2 separate result notifications
- ✅ Requests List shows correct status for each request

---

## Test Case 6: Notification While Viewing Request

### **Setup**
- Device A: App open, viewing Requests screen
- Device B: App open, viewing Requests screen

### **Steps**
1. **Device A**: Send request to Device B
2. **Device B**: Observe both:
   - In-app notification banner
   - Request appears in Requests List
3. **Device B**: Tap Accept on **notification banner**
4. **Device A**: Observe request status updates in real-time

### **Expected Results**
- ✅ Device B sees notification banner + list update
- ✅ Device B can accept from either notification or list item
- ✅ Device A sees instant status update in list
- ✅ No duplicate actions or race conditions

---

## Test Case 7: Notification Tap (No Action Buttons)

### **Setup**
- Device A: App closed
- Device B: App open, send request to A

### **Steps**
1. **Device B**: Send request to Device A
2. **Device A**: Receive notification
3. **Device A**: Tap on **notification body** (not buttons)
4. **Device A**: App opens

### **Expected Results**
- ✅ Device A app opens to Requests screen
- ✅ Navigation works correctly
- ✅ Device A can see pending request in list

---

## Test Case 8: Network Interruption

### **Setup**
- Device A: App open, WiFi connected
- Device B: App minimized, WiFi connected

### **Steps**
1. **Device B**: Turn off WiFi → Switch to mobile data
2. **Device A**: Send request to Device B
3. **Device B**: Observe notification still arrives (FCM uses mobile data)
4. **Device B**: Tap Accept
5. **Device A**: Observe result notification

### **Expected Results**
- ✅ Notification arrives via mobile data
- ✅ Action works even on different network
- ✅ Firestore updates sync when back online

---

## Test Case 9: Notification Sound & Vibration

### **Setup**
- Device B: Volume up, vibration enabled
- Device B: App closed

### **Steps**
1. **Device A**: Send request to Device B
2. **Device B**: Observe notification with:
   - Sound plays
   - Device vibrates
   - Notification appears

### **Expected Results**
- ✅ Default notification sound plays
- ✅ Device vibrates
- ✅ Notification is marked as high priority

---

## Test Case 10: Rapid Actions

### **Setup**
- Device A: App open
- Device B: App minimized

### **Steps**
1. **Device A**: Send 3 requests quickly to Device B
2. **Device B**: Receive 3 notifications
3. **Device B**: Quickly tap Accept on all 3
4. **Device A**: Observe 3 result notifications

### **Expected Results**
- ✅ All 3 actions process correctly
- ✅ No race conditions or missed updates
- ✅ Firestore handles concurrent writes
- ✅ All notifications clear after action

---

## Debugging Tools

### **1. Check FCM Token**
```dart
// In notification_service.dart
String? token = await _firebaseMessaging.getToken();
print('FCM Token: $token');
```

### **2. Verify Firestore Token Storage**
- Open Firebase Console → Firestore
- Navigate to `users` collection
- Check each user document has `fcmToken` field

### **3. Check Notification Logs**
```bash
# Android logs
adb logcat | grep -E "FCM|Notification|📲"
```

### **4. Test Notification Payload**
```dart
// Add to _sendNotificationV1 in ticket_service.dart
print('Sending notification to: $fcmToken');
print('Payload: ${jsonEncode(message)}');
```

### **5. Verify Service Account**
- Check `assets/service_account.json` exists
- Verify project_id matches Firebase project
- Ensure FCM API is enabled in Google Cloud Console

---

## Common Issues & Fixes

### **Issue 1: Notifications Not Received**
**Symptoms**: Device doesn't get notification  
**Fixes**:
- ✅ Check internet connection
- ✅ Verify FCM token stored in Firestore
- ✅ Enable notification permissions in device settings
- ✅ Check Firebase Cloud Messaging API is enabled

### **Issue 2: Actions Not Working**
**Symptoms**: Tapping Accept/Reject does nothing  
**Fixes**:
- ✅ Verify background handler registered in `main.dart`
- ✅ Check `requestId` is in notification payload
- ✅ Ensure `request_channel` notification channel created
- ✅ Test with app in background (not just foreground)

### **Issue 3: User A Not Getting Result**
**Symptoms**: User B accepts but User A doesn't know  
**Fixes**:
- ✅ Check `updateRequestStatus()` calls `_sendNotificationV1()`
- ✅ Verify User A's FCM token exists in Firestore
- ✅ Check User A's device has internet connection
- ✅ Open User A's app to trigger token refresh

### **Issue 4: Notification Arrives Late**
**Symptoms**: 30+ second delay  
**Fixes**:
- ✅ Check device battery optimization (Settings → Battery → Streamix → Don't optimize)
- ✅ Verify high priority set in FCM payload
- ✅ Ensure device not in Doze mode
- ✅ Test with device plugged in and screen on

### **Issue 5: App Crashes on Action**
**Symptoms**: App force closes when tapping action  
**Fixes**:
- ✅ Check logs for null pointer exceptions
- ✅ Verify `requestId` is valid
- ✅ Ensure Firestore rules allow write access
- ✅ Add try-catch around Firestore updates

---

## Performance Metrics

### **Expected Latency**
| Scenario | Expected Time |
|----------|---------------|
| Send request → Notification received | 1-3 seconds |
| Tap action → Firestore updated | <1 second |
| Status update → Result notification | 1-3 seconds |
| Total round-trip (request → accept → result) | 2-6 seconds |

### **Success Criteria**
- ✅ 95%+ notifications delivered within 5 seconds
- ✅ 100% actions update Firestore correctly
- ✅ 0% crashes when tapping actions
- ✅ Works on Android 8+ devices

---

## Final Checklist Before Release

- [ ] Test all 10 scenarios above
- [ ] Verify notifications work when both apps closed
- [ ] Check notification sound and vibration
- [ ] Test with poor network conditions
- [ ] Verify multiple concurrent requests
- [ ] Check notification permission flow for new users
- [ ] Test on different Android versions (8, 10, 12, 13+)
- [ ] Verify FCM token refresh on app updates
- [ ] Check battery optimization warnings
- [ ] Test notification channel settings (user can customize)

---

## 📱 Testing Devices Used

| Device | Android Version | Status | Notes |
|--------|-----------------|--------|-------|
| Device A | Android XX | ✅ Passed | |
| Device B | Android XX | ✅ Passed | |
| Device C | Android XX | ⏳ Pending | |

---

## ✅ Test Results Summary

### **Overall Status**: 🟢 Ready for Testing

| Test Case | Status | Notes |
|-----------|--------|-------|
| Foreground Notifications | ⏳ Pending | |
| Background Notifications | ⏳ Pending | |
| Terminated Notifications | ⏳ Pending | |
| Both Apps Closed | ⏳ Pending | |
| Multiple Requests | ⏳ Pending | |
| Notification Tap | ⏳ Pending | |
| Network Interruption | ⏳ Pending | |
| Sound & Vibration | ⏳ Pending | |
| Rapid Actions | ⏳ Pending | |

---

**Testing Started**: [Date]  
**Testing Completed**: [Date]  
**Tested By**: [Name]  
**Status**: Ready for User Acceptance Testing
