# 📄 Project Requirements Documentation (PRD)

## 1. **Project Title**

Accessible AI-Powered Navigation Assistant for the Visually Impaired
(Cross-Platform Flutter App)

------------------------------------------------------------------------

## 2. **Project Overview**

This project is a **cross-platform mobile application** (iOS + Android)
developed with **Flutter** that assists visually impaired individuals in
**navigating and understanding their surroundings in real-time**.

The app uses:\
- **YOLOv8n** for **object detection**.\
- **BLIP-2** for **scene description (image captioning)**.\
- **GPT-4o-mini (or LLaVA)** for **question answering** about the
detected scene.\
- **GPT-4o Realtime / OpenAI TTS** for **Text-to-Speech (TTS)**.\
- **OpenAI STT (Whisper API)** for **Speech-to-Text (STT)**.\
- **Gestures, vibrations, and voice guidance** instead of complex UI for
accessibility.

The app must be usable **without relying on visual UI**, making it
accessible for blind or visually impaired users.

------------------------------------------------------------------------

## 3. **Core Features**

### 3.1 Camera Input

-   Use the **phone's camera** to continuously capture the surrounding
    environment.\
-   Support both iOS and Android permissions for camera usage.

### 3.2 Object Detection (YOLOv8n)

-   Detect key objects in front of the user (e.g., cars, people, doors,
    obstacles).\
-   Run YOLOv8n locally (ONNX/TFLite) or through a FastAPI backend.\
-   Return results in JSON format (object type, confidence, bounding
    box).

**Example JSON Response:**

``` json
{
  "objects": [
    {"name": "person", "confidence": 0.92, "x": 120, "y": 200, "w": 60, "h": 180},
    {"name": "car", "confidence": 0.88, "x": 300, "y": 220, "w": 140, "h": 80}
  ]
}
```

### 3.3 Scene Description (BLIP-2)

-   Generate a **natural-language caption** summarizing the entire
    scene.\
-   Example output: *"A man is standing at a bus stop while cars are
    passing by."*

### 3.4 Audio Guidance (TTS via GPT)

-   Use **OpenAI GPT-4o Realtime / TTS API** to **speak out scene
    descriptions**.\
-   Provide **short, clear, safety-oriented sentences**.\
-   Example: Instead of *"There is a road with multiple vehicles passing
    in both directions"* → say *"Cars are passing. Do not cross yet."*

### 3.5 Voice Input (STT via Whisper API)

-   Use **OpenAI Whisper API** to capture user's spoken questions.\
-   Example questions:
    -   "Is it safe to cross?"\
    -   "Where is the nearest person?"\
    -   "What is in front of me?"

### 3.6 Contextual Question Answering (LLM)

-   Send scene description + detected objects + user question → to
    **GPT-4o-mini (or LLaVA)**.\
-   LLM should give **short, actionable answers**.\
-   Example:
    -   Scene: "A person is waiting at a crosswalk with cars passing."\
    -   User: "Can I cross?"\
    -   Answer: "No, it's not safe. Cars are still passing."

### 3.7 Accessibility-First UI (Cross-Platform)

-   Minimal visual UI → rely on gestures, voice, and haptic feedback.\
-   **Gestures:**
    -   Swipe up → Describe surroundings.\
    -   Swipe right → Ask a question.\
    -   Double-tap → Stop audio.\
-   **Haptics:**
    -   Short vibration when detection starts.\
    -   Long vibration when answer is ready.\
-   **Screen Reader (Semantics):** Ensure buttons and gestures are
    labeled for TalkBack (Android) and VoiceOver (iOS).

### 3.8 App Startup Flow

1.  On launch, TTS says:\
    \> "Camera is active. Swipe up to hear surroundings. Swipe right to
    ask a question."\
2.  User swipes up → Scene is described aloud.\
3.  User swipes right → Mic activates, user asks question.\
4.  Backend answers → Response is spoken aloud.

------------------------------------------------------------------------

## 4. **Technical Stack**

### Frontend (Cross-Platform Mobile)

-   **Flutter (Dart)**\
-   Packages:
    -   `camera` → Capture environment.\
    -   `provider` or `riverpod` → State management.

### Backend (AI Inference)

-   **FastAPI (Python)**\
-   Models:
    -   YOLOv8n → Object Detection.\
    -   BLIP-2 (small) → Scene Captioning.\
    -   GPT-4o-mini API (preferred) OR LLaVA → Contextual Q&A.\
    -   OpenAI Whisper API → STT.\
    -   OpenAI GPT-4o Realtime TTS → Audio responses.\
-   Deployment: Hugging Face Spaces / Render / Heroku.

------------------------------------------------------------------------

## 5. **System Architecture**

**Flow of Data:**\
1. Flutter app → Captures camera frame.\
2. Sends frame to backend `/detect` + `/describe`.\
3. Backend → Runs YOLOv8n + BLIP-2 → Returns objects + caption.\
4. Flutter app → Narrates caption with GPT TTS.\
5. User speaks question → Whisper API converts to text.\
6. App sends (objects + caption + question) → Backend `/qa`.\
7. Backend → GPT-4o-mini/LLaVA → Returns answer.\
8. Flutter app → Speaks answer aloud with GPT TTS + vibrates.

------------------------------------------------------------------------

## 6. **Non-Functional Requirements**

-   **Cross-platform**: Must run smoothly on Android + iOS.\
-   **Accessibility**: Fully usable without visual UI.\
-   **Performance**: Real-time or near real-time (\<1s lag preferred).\
-   **Privacy**: Images should not be stored; only processed
    temporarily.\
-   **Offline fallback**: If internet unavailable, app should at least
    run YOLOv8 locally and speak object names.

------------------------------------------------------------------------

## 7. **Hackathon Deliverables**

1.  A **working Flutter app** with:
    -   Camera input\
    -   Gesture navigation\
    -   GPT-based TTS & Whisper-based STT\
    -   Haptic feedback\
    -   Backend integration\
2.  A **FastAPI backend** running YOLOv8n + BLIP-2 + GPT-4o-mini/LLaVA.\
3.  Demo flow:
    -   Open app → Instructions narrated.\
    -   Swipe up → Scene described.\
    -   Swipe right → Ask question → Answer spoken aloud.

------------------------------------------------------------------------

## 🌟 Must add features:

To make the project stand out in a hackathon setting, the following
innovative features are added on top of the core requirements:

### 1. Context-Aware Safety Alerts 🚨

Instead of just describing scenes, the app provides real-time safety
warnings such as: - "Obstacle ahead in 2 meters." - "Car approaching
from the left." - "Crosswalk detected, but traffic is moving."

Uses YOLO object positions + distance estimation to alert users
proactively.

------------------------------------------------------------------------

### 2. Smart Navigation Mode (Guide me to X) 🧭

Allows the user to speak commands like:\
- "Guide me to the door."\
- "Take me to the bus stop."

The app will track the chosen object and provide step-by-step navigation
with directional voice guidance.

------------------------------------------------------------------------

### 3. SOS / Emergency Assistance 🆘

A special gesture (long press or 3-finger tap) triggers an emergency
mode where:\
- Live location, camera snapshot, and a pre-recorded audio message are
sent to an emergency contact.\
- Optionally calls a family member with: "Help needed, I'm near XYZ."

------------------------------------------------------------------------

### ✅ Hackathon Killer Combo

For maximum impact in a hackathon, the following 3 features are strongly
recommended to be implemented together: 1. Context-Aware Safety Alerts
🚨\
2. Smart Navigation Mode 🧭\
3. SOS Emergency Assistance 🆘


### Version I have:

java 17.0.16

Python 3.12.6

Flutter 3.35.2 • channel stable • https://github.com/flutter/flutter.git
Framework • revision 05db968908 (3 days ago) • 2025-08-25 10:21:35 -0700
Engine • hash abb725c9a5211af2a862b83f74b7eaf2652db083 (revision a8bfdfc394) (6 days
ago) • 2025-08-22 23:51:12.000Z
Tools • Dart 3.9.0 • DevTools 2.48.0