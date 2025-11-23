# **Streamix — Real-Time Collaboration & Streaming Application**
### **Technical Documentation & Project Report**

---

## 🚀 **1. Executive Summary**

**Streamix** is a real-time collaboration application built using **Flutter**, designed to deliver secure, peer-to-peer (P2P) remote services.  
Instead of standard video calling apps like WhatsApp, Streamix enables **purpose-driven, time-bound, hardware-specific remote access** such as:

- Live location tracking
- Front/Back camera streaming
- Audio streaming
- Automated remote photo capture

Each interaction is executed under a **strictly controlled schedule**, ensuring privacy and precision in remote assistance.

---

## ⭐ **2. Key Features**

### **2.1 Service Request System (Ticket Model)**

Streamix uses a structured **Service Ticket** system instead of typical calls.

**Supported Service Types**
- Location Tracking
- Audio Stream
- Front Camera Stream
- Back Camera Stream
- Remote Photo Capture

**Request Lifecycle:**  
`Pending → Accepted → Active → Completed / Expired`

**Scheduling Rules:**
- Mandatory **Start Time** (minimum 2 minutes ahead)
- Mandatory **End Time**
- Access allowed only inside the defined time window

---

### **2.2 Real-Time Access Control**

- **Time-Lock Enforcement:** UI buttons “Start Sharing” and “View Live” are disabled until the time window begins.
- **Auto-Expiry:** Session stops automatically after the end time.
- **Status Sync:** Request status updates to **DONE** without user action.

---

### **2.3 Live Streaming (WebRTC)**

Streamix implements real-time media streaming using **WebRTC**.

#### **Architecture**
- Peer-to-Peer (P2P) Mesh Model
- **Signaling:** Cloud Firestore for exchanging SDP Offers/Answers & ICE Candidates
- **NAT Traversal:** Public STUN servers from Google & Mozilla

#### **Sender Features**
- Auto-start on session start
- Mute audio toggle
- Stop streaming anytime

#### **Receiver Features**
- Waiting Room UI
- Auto-connect
- Mute incoming audio

---

### **2.4 Live Location Tracking**

**Supabase PostgreSQL** is used for highly efficient real-time GPS updates.

- Sender continuously pushes coordinates into `live_sessions` table
- Receiver subscribes to row-level updates
- Map displayed using `flutter_map` with OpenStreetMap tiles
- Latency under ~200ms in practical tests

---

### **2.5 Automated Media Capture**

During a **Camera Photo Session**, the sender’s device:

1. Auto-opens the camera
2. Displays a **3-2-1 Countdown**
3. Captures the image
4. Uploads it to **Supabase Storage**
5. Updates the ticket with the media URL

Zero user intervention required.

---

### **2.6 Push Notifications (FCM)**

Streamix sends push notifications directly using:

- **FCM HTTP V1 API**
- **googleapis_auth** for generating Google OAuth tokens on-device
- **Service Account JSON** used securely

This enables:

- Notifications even when app is closed
- Deep linking to Requests List

No paid backend or Firebase Cloud Functions needed.

---

## 🧱 **3. Technical Architecture**

### **3.1 Technology Stack**

| Component | Technology | Purpose |
|----------|------------|---------|
| **Frontend** | Flutter (Dart) | Cross-platform UI |
| **Authentication** | Firebase Auth | Login/Session |
| **Database 1** | Cloud Firestore | User profiles, tickets, signaling |
| **Database 2** | Supabase | Live location & storage |
| **Push Notifications** | Firebase Cloud Messaging | Alerts & deep links |
| **Maps** | flutter_map + OSM | GPS visual tracking |

---

### **3.2 Data Models**

#### **User Collection**

```json
{
  "uid": "unique_user_id",
  "name": "John Doe",
  "email": "john@example.com",
  "phoneNumber": "+1234567890",
  "avatar": "https://... or emoji",
  "fcmToken": "device_token_for_push"
}
```

```json
{
  "id": "auto_generated_id",
  "requesterId": "user_a_uid",
  "peerUserId": "user_b_uid",
  "serviceType": "front_stream",
  "status": "pending", // accepted, completed, denied
  "startTime": "Timestamp",
  "endTime": "Timestamp",
  "mediaUrl": "https://..." // Optional result file
}
```

## **4. Key Implementation Challenges & Solutions**

### **4.1 The "Black Screen" (WebRTC Race Condition)**

**Problem:**  
The Receiver often saw a black screen because they attempted to add network paths (ICE Candidates) before the call connection (Remote Description) was fully established.

**Solution:**  
Implemented a **Candidate Queue** mechanism.  
The Receiver now buffers all incoming network paths into a list called `_candidateQueue` and processes them **only after** the "Offer" is successfully set.  
This ensures the correct order of signaling events and prevents WebRTC rendering issues.

---

### **4.2 Notification Complexity (Free Tier Constraint)**

**Problem:**  
Sending notifications usually requires a paid backend server. Firebase Cloud Functions requires a credit card and cannot run in free tier for V1 HTTP notifications.

**Solution:**  
Implemented a **Client-Side Notification Sender** using the `googleapis_auth` package.  
The app securely signs its own HTTP requests using a **Service Account JSON** file and sends messages directly to the **Firebase Cloud Messaging (FCM) V1 API** — completely free and with zero backend servers.

---

### **4.3 State Synchronization**

**Problem:**  
User A must always know when User B begins streaming, without manual refresh or delay.

**Solution:**  
Added **Auto-Join Firestore Listeners**.  
The `RequestsListScreen` actively listens to the ticket document in Firestore.  
As soon as the time window opens or the request status updates, the screen automatically navigates the user to the appropriate session screen.

---

## **5. Future Roadmap**

### **TURN Server**
Deploy a dedicated **TURN server** (e.g., Coturn) to achieve 100% connectivity on restrictive networks where STUN alone fails.

### **Group Streaming**
Extend WebRTC logic to support **1-to-Many broadcasting**, enabling multiple viewers for a single live stream.

### **End-to-End Encryption**
Even though WebRTC already encrypts data in transit, adding an **extra encryption layer for stored media** (images/videos in Supabase) would further enhance privacy.

---

### *Generated for Streamix Development Team*


