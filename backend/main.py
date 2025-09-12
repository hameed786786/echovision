from fastapi import FastAPI, File, UploadFile, HTTPException, Form, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import cv2
import numpy as np
from PIL import Image
import io
import base64
import os
import torch
import logging
import json
import time
import asyncio
from dotenv import load_dotenv
import openai
from ultralytics import YOLO
from transformers import BlipProcessor, BlipForConditionalGeneration
import easyocr

load_dotenv()

# Set up Hugging Face authentication
huggingface_token = os.getenv("HUGGINGFACE_TOKEN")
if huggingface_token:
    os.environ["HUGGINGFACE_HUB_TOKEN"] = huggingface_token
    print(f"✅ Hugging Face token configured")
else:
    print("⚠️  No Hugging Face token found - some models may download slower")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables for models
yolo_model = None
blip_model = None
blip_processor = None
openai_client = None
ocr_reader = None
device = None

# API Models
from pydantic import BaseModel, root_validator, Field
from typing import List, Optional, Dict, Any


class ObjectDetection(BaseModel):
    """Represents an object detection; supports either bbox=[x1,y1,x2,y2] or x,y,w,h from frontend."""
    name: str
    confidence: float
    # Accept either format (both optional for input flexibility)
    bbox: Optional[List[float]] = None  # [x1,y1,x2,y2]
    x: Optional[float] = None
    y: Optional[float] = None
    w: Optional[float] = None
    h: Optional[float] = None

    @root_validator(pre=True)
    def ensure_bbox(cls, values):  # type: ignore
        # If bbox not provided but x,y,w,h are, build it
        if 'bbox' not in values or values.get('bbox') is None:
            x = values.get('x')
            y = values.get('y')
            w = values.get('w')
            h = values.get('h')
            if None not in (x, y, w, h):
                try:
                    x1 = float(x)
                    y1 = float(y)
                    x2 = x1 + float(w)
                    y2 = y1 + float(h)
                    values['bbox'] = [x1, y1, x2, y2]
                except Exception:
                    pass
        return values

    def to_client_dict(self) -> dict:
        """Return dict shape expected by Flutter (x,y,w,h)."""
        if self.bbox and len(self.bbox) == 4:
            x1, y1, x2, y2 = self.bbox
            x = int(x1)
            y = int(y1)
            w = int(max(0, x2 - x1))
            h = int(max(0, y2 - y1))
        else:
            # Fall back to provided separate values
            x = int(self.x or 0)
            y = int(self.y or 0)
            w = int(self.w or 0)
            h = int(self.h or 0)
        return {
            "name": self.name,
            "confidence": float(self.confidence),
            "x": x,
            "y": y,
            "w": w,
            "h": h,
        }


class QuestionRequest(BaseModel):
    question: str
    scene_description: Optional[str] = ""  # optional => prevents 422
    objects: Optional[List[ObjectDetection]] = None  # will coerce to [] in logic


class ObjectSearchRequest(BaseModel):
    image_data: str  # base64 encoded image
    object_name: str  # object to search for


class NavigationRequest(BaseModel):
    image_data: str  # base64 encoded image
    destination: str  # place or object to navigate to


class AnswerResponse(BaseModel):
    answer: str


class AnalyzeResponse(BaseModel):
    scene_description: str
    objects: List[ObjectDetection]

class ObstacleInfo(BaseModel):
    name: str
    distance: str
    position: str
    threat: str
    confidence: float = Field(default=0.0)


class GuideResponse(BaseModel):
    target: Optional[str]
    direction: str
    distance: str
    confidence: float
    instruction: str
    scene_description: str
    objects: List[ObjectDetection]
    obstacles: List[ObstacleInfo] = Field(default_factory=list)

# Create FastAPI app
app = FastAPI(
    title="Vision Mate Backend",
    description="AI-powered navigation assistant for visually impaired users",
    version="1.0.0"
)

@app.on_event("startup")
async def startup_event():
    """Load models on startup"""
    global yolo_model, blip_model, blip_processor, openai_client, ocr_reader, device
    
    try:
        print("🔄 Loading AI models...")
        logger.info("Starting up...")
        
        # Detect device
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        logger.info(f"Using device: {device}")
        print(f"🔧 Using device: {device}")
        
        # Load YOLOv8n model
        logger.info("Loading YOLOv8n model...")
        print("🔄 Loading YOLOv8n model...")
        try:
            # Handle PyTorch 2.6+ compatibility for YOLO model loading
            import warnings
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                yolo_model = YOLO('yolov8n.pt')
            if device.type == 'cuda':
                yolo_model.to(device)
            print("✅ YOLOv8n model loaded successfully!")
        except Exception as yolo_err:
            print(f"❌ YOLOv8n model failed to load: {yolo_err}")
            raise
        
        # Load BLIP-2 model
        logger.info("Loading BLIP-2 model...")
        print("🔄 Loading BLIP-2 model...")
        model_kwargs = {}
        if huggingface_token:
            model_kwargs["use_auth_token"] = huggingface_token
        
        try:
            blip_processor = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-base", **model_kwargs)
            blip_model = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-base", **model_kwargs)
            if device.type == 'cuda':
                blip_model.to(device)
            print("✅ BLIP-2 model loaded successfully!")
        except Exception as blip_err:
            print(f"❌ BLIP-2 model failed to load: {blip_err}")
            raise
        
        # Initialize OCR Reader
        logger.info("Loading OCR reader...")
        print("🔄 Loading OCR reader...")
        try:
            # Initialize EasyOCR with English support (can add more languages)
            ocr_reader = easyocr.Reader(['en'], gpu=(device.type == 'cuda'))
            print("✅ OCR reader loaded successfully!")
        except Exception as ocr_err:
            print(f"❌ OCR reader failed to load: {ocr_err}")
            # OCR is optional, so don't raise - just log the error
            logger.warning(f"OCR initialization failed: {ocr_err}")
            ocr_reader = None
        
        # Initialize OpenAI client
        print("🔄 Loading OpenAI client...")
        openai_api_key = os.getenv("OPENAI_API_KEY")
        if openai_api_key:
            try:
                openai_client = openai.OpenAI(api_key=openai_api_key)
                print("✅ OpenAI client loaded successfully!")
            except TypeError:
                # Fallback for older OpenAI client versions
                openai.api_key = openai_api_key
                openai_client = openai
                print("✅ OpenAI client loaded (fallback method)!")
        else:
            logger.warning("OpenAI API key not found")
            print("⚠️ OpenAI API key not found")
        
        logger.info("All models loaded successfully!")
        print("🎉 All models loaded successfully!")
        
    except Exception as e:
        error_msg = f"Error during startup: {e}"
        logger.error(error_msg)
        print(f"❌ STARTUP FAILED: {error_msg}")
        import traceback
        traceback.print_exc()
        raise  # Re-raise to prevent server from starting with failed models

# Enable CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    return {"message": "Vision Mate Backend is running!", "status": "healthy"}

@app.get("/health")
async def health_check():
    """Detailed health check"""
    return {
        "status": "healthy",
        "models": {
            "yolo": yolo_model is not None,
            "blip": blip_model is not None and blip_processor is not None,
            "openai": openai_client is not None,
            "ocr": ocr_reader is not None
        },
        "device": str(device) if device else "unknown"
    }

def _focused_description(objects: List[ObjectDetection]) -> str:
    """Generate concise, navigation-focused description from detected objects.
    Rules: prioritize people, vehicles, obstacles; mention counts and relative position (left/center/right).
    Limit to ~110 characters.
    """
    if not objects:
        return "No clear objects ahead. Path may be open."

    # Map priority groups
    priority_order = [
        {"person"},  # highest
        {"car", "bus", "truck", "motorcycle", "bicycle"},
        {"dog", "cat"},
        {"chair", "bench"},
    ]

    def horiz_pos(obj: ObjectDetection) -> str:
        if not obj.bbox:
            return "center"
        x1, _, x2, _ = obj.bbox
        mid = (x1 + x2) / 2.0
        # Normalize using assumed image width ~640 if not provided
        width = 640.0
        rel = mid / width
        if rel < 0.33:
            return "left"
        if rel > 0.66:
            return "right"
        return "center"

    # Count objects by name & position
    info: Dict[tuple, int] = {}
    for o in objects:
        pos = horiz_pos(o)
        key = (o.name, pos)
        info[key] = info.get(key, 0) + 1

    # Build sentences by priority
    phrases = []
    used_names = set()
    for group in priority_order:
        group_entries = [
            (name, pos, cnt) for (name, pos), cnt in info.items() if name in group
        ]
        if not group_entries:
            continue
        # aggregate counts across positions for same name
        name_totals: Dict[str, int] = {}
        for name, pos, cnt in group_entries:
            name_totals[name] = name_totals.get(name, 0) + cnt
        for name in sorted(name_totals.keys()):
            if name in used_names:
                continue
            total = name_totals[name]
            pos_counts: Dict[str, int] = {
                pos: cnt for (n, pos, cnt) in group_entries if n == name
            }
            dom_pos = max(pos_counts.keys(), key=lambda k: pos_counts[k])
            noun = name + ("s" if total > 1 and not name.endswith('s') else "")
            phrase = (
                f"1 {name} {dom_pos}" if total == 1 else f"{total} {noun} {dom_pos}"
            )
            phrases.append(phrase)
            used_names.add(name)
        # Stop if description getting long
        if len("; ".join(phrases)) > 90:
            break

    if not phrases:
        flat_counts: Dict[str, int] = {}
        for (name, _pos), cnt in info.items():
            flat_counts[name] = flat_counts.get(name, 0) + cnt
        top = sorted(flat_counts.items(), key=lambda x: -x[1])[:3]
        phrases = [f"{cnt} {nm}{'s' if cnt>1 and not nm.endswith('s') else ''}" for nm, cnt in top]

    sentence = "; ".join(phrases)
    sentence = sentence.replace("  ", " ").strip()
    if not sentence:
        sentence = "Scene detected, no key obstacles."
    return sentence.capitalize()


def _extract_text_from_image(image_array: np.ndarray) -> str:
    """Extract text from image using OCR."""
    if ocr_reader is None:
        return ""
    
    try:
        # EasyOCR expects image in RGB format
        if len(image_array.shape) == 3 and image_array.shape[2] == 3:
            # Convert BGR to RGB for OCR
            rgb_image = cv2.cvtColor(image_array, cv2.COLOR_BGR2RGB)
        else:
            rgb_image = image_array
        
        # Extract text using EasyOCR
        results = ocr_reader.readtext(rgb_image)
        
        if not results:
            return ""
        
        # Extract text content and filter by confidence
        text_segments = []
        for (bbox, text, confidence) in results:
            # Only include text with reasonable confidence (>0.5)
            if confidence > 0.5 and text.strip():
                # Clean up the text
                cleaned_text = text.strip()
                if len(cleaned_text) > 1:  # Skip single characters
                    text_segments.append(cleaned_text)
        
        if not text_segments:
            return ""
        
        # Join text segments and create a readable description
        extracted_text = " ".join(text_segments)
        
        # Format the text for accessibility
        if len(extracted_text) > 200:
            # Truncate very long text
            extracted_text = extracted_text[:200] + "..."
        
        return extracted_text
        
    except Exception as e:
        logger.error(f"OCR extraction failed: {e}")
        return ""


def _extract_targets(question: str) -> List[str]:
    q = question.lower()
    # Simple keyword extraction (could be extended)
    tokens = [t.strip("?.,! ") for t in q.split()]
    # Filter out stopwords
    stop = {"the","a","an","to","is","are","there","on","at","my","in","for","of","do","i","can","you","me","near"}
    nouns = [t for t in tokens if t and t not in stop and len(t) > 2]
    return list(dict.fromkeys(nouns))[:3]


def _estimate_distance(obj: ObjectDetection, img_height: float = 480.0) -> str:
    """Estimate relative distance based on object size and position."""
    if not obj.bbox or len(obj.bbox) != 4:
        return "unknown"
    
    x1, y1, x2, y2 = obj.bbox
    height = y2 - y1
    bottom_y = y2
    
    # Distance heuristics based on object size and vertical position
    rel_height = height / img_height
    rel_bottom = bottom_y / img_height
    
    # Larger objects lower in frame = closer
    if rel_height > 0.4 and rel_bottom > 0.7:
        return "very close"
    elif rel_height > 0.25 and rel_bottom > 0.6:
        return "close"
    elif rel_height > 0.15 and rel_bottom > 0.5:
        return "medium"
    elif rel_height > 0.08:
        return "far"
    else:
        return "very far"


def _calculate_precise_position(obj: ObjectDetection, img_width: float = 640.0, img_height: float = 480.0) -> Dict[str, Any]:
    """Calculate precise position and angle for navigation."""
    if not obj.bbox or len(obj.bbox) != 4:
        return {"angle": 0, "distance_meters": 0, "position": "unknown", "coordinates": [0, 0]}
    
    x1, y1, x2, y2 = obj.bbox
    center_x = (x1 + x2) / 2.0
    center_y = (y1 + y2) / 2.0
    width = x2 - x1
    height = y2 - y1
    
    # Calculate angle from center of frame
    frame_center_x = img_width / 2.0
    frame_center_y = img_height / 2.0
    
    # Horizontal angle calculation (assuming 60-70 degree FOV for typical phone camera)
    horizontal_fov = 60.0  # degrees
    pixels_per_degree = img_width / horizontal_fov
    angle_offset = (center_x - frame_center_x) / pixels_per_degree
    
    # Distance estimation in meters (rough approximation based on object type and size)
    object_real_sizes = {
        "person": 1.7,  # average human height in meters
        "car": 4.5,     # average car length
        "chair": 0.9,   # average chair height
        "table": 0.75,  # average table height
        "door": 2.0,    # average door height
        "laptop": 0.35, # laptop width
        "cell phone": 0.15, # phone height
        "bottle": 0.25, # bottle height
        "cup": 0.1,     # cup height
        "book": 0.25,   # book height
        "clock": 0.3,   # wall clock diameter
        "tv": 1.0,      # TV width (medium size)
        "refrigerator": 1.8, # fridge height
        "microwave": 0.5,    # microwave width
        "oven": 0.6,    # oven width
        "sink": 0.6,    # sink width
        "toilet": 0.7,  # toilet height
        "bed": 2.0,     # bed length
        "dining table": 1.5, # table length
        "sofa": 2.0,    # sofa length
        "potted plant": 0.5, # plant height
        "bicycle": 1.7, # bike length
        "motorcycle": 2.0, # bike length
        "airplane": 50.0,   # large plane
        "bus": 12.0,    # bus length
        "train": 25.0,  # train car length
        "truck": 8.0,   # truck length
        "boat": 6.0,    # small boat length
        "stop sign": 0.8, # stop sign height
        "parking meter": 1.2, # meter height
        "bench": 1.5,   # bench length
        "bird": 0.15,   # small bird
        "cat": 0.4,     # cat body length
        "dog": 0.6,     # medium dog body length
        "horse": 2.5,   # horse length
        "sheep": 1.5,   # sheep body length
        "cow": 2.5,     # cow body length
        "elephant": 6.0, # elephant length
        "bear": 2.0,    # bear body length
        "zebra": 2.5,   # zebra body length
        "giraffe": 5.0, # giraffe height
    }
    
    # Get expected real-world size for the object
    real_size = object_real_sizes.get(obj.name.lower(), 1.0)  # default 1 meter
    
    # Estimate distance using object height in pixels vs expected real height
    # This is a simplified camera model: distance = (real_height * focal_length) / pixel_height
    # Using approximation: focal_length ≈ img_height for typical phone cameras
    focal_length_approx = img_height
    estimated_distance = (real_size * focal_length_approx) / height
    
    # Apply some bounds to make estimates more reasonable
    estimated_distance = max(0.5, min(estimated_distance, 100.0))  # between 0.5m and 100m
    
    # Determine precise position description
    if abs(angle_offset) < 5:
        position = "directly ahead"
    elif abs(angle_offset) < 15:
        position = f"slightly {'left' if angle_offset < 0 else 'right'}"
    elif abs(angle_offset) < 30:
        position = f"{'left' if angle_offset < 0 else 'right'}"
    elif abs(angle_offset) < 45:
        position = f"far {'left' if angle_offset < 0 else 'right'}"
    else:
        position = f"extreme {'left' if angle_offset < 0 else 'right'}"
    
    return {
        "angle": round(angle_offset, 1),  # degrees from center (-left, +right)
        "distance_meters": round(estimated_distance, 1),
        "position": position,
        "coordinates": [round(center_x), round(center_y)],
        "size_pixels": [round(width), round(height)],
        "confidence": obj.confidence
    }


def _direction_for_targets(target_objs: List[ObjectDetection], width: float = 640.0, height: float = 480.0) -> Dict[str, Any]:
    """Enhanced direction calculation with precise positioning and navigation guidance."""
    if not target_objs:
        return {"direction": "unknown", "distance": "unknown", "confidence": 0.0, "navigation": {}}
    
    # Calculate precise positions for all target objects
    positions = []
    for obj in target_objs:
        pos_data = _calculate_precise_position(obj, width, height)
        positions.append(pos_data)
    
    if not positions:
        return {"direction": "unknown", "distance": "unknown", "confidence": 0.0, "navigation": {}}
    
    # Find the closest and most confident target
    best_target = min(positions, key=lambda p: p["distance_meters"])
    avg_confidence = sum(p["confidence"] for p in positions) / len(positions)
    
    # Generate precise navigation instruction
    angle = best_target["angle"]
    distance = best_target["distance_meters"]
    
    # Determine turn instruction
    if abs(angle) < 2:
        turn_instruction = "Continue straight ahead"
        turn_direction = "straight"
    elif abs(angle) < 10:
        turn_instruction = f"Slight adjustment: turn {abs(angle):.1f} degrees {'left' if angle < 0 else 'right'}"
        turn_direction = "slight_left" if angle < 0 else "slight_right"
    elif abs(angle) < 30:
        turn_instruction = f"Turn {abs(angle):.1f} degrees {'left' if angle < 0 else 'right'}"
        turn_direction = "left" if angle < 0 else "right"
    elif abs(angle) < 60:
        turn_instruction = f"Sharp turn: {abs(angle):.1f} degrees {'left' if angle < 0 else 'right'}"
        turn_direction = "sharp_left" if angle < 0 else "sharp_right"
    else:
        turn_instruction = f"Turn around: object is {abs(angle):.1f} degrees {'left' if angle < 0 else 'right'} behind you"
        turn_direction = "turn_around_left" if angle < 0 else "turn_around_right"
    
    # Distance description with more precision
    if distance < 0.5:
        distance_desc = f"very close ({distance:.1f} meters)"
        approach_instruction = "Move very slowly and carefully"
    elif distance < 1.5:
        distance_desc = f"close ({distance:.1f} meters)"
        approach_instruction = "Take a few careful steps forward"
    elif distance < 3.0:
        distance_desc = f"medium distance ({distance:.1f} meters)"
        approach_instruction = "Walk forward steadily"
    elif distance < 10.0:
        distance_desc = f"far ({distance:.1f} meters)"
        approach_instruction = "Walk forward at normal pace"
    else:
        distance_desc = f"very far ({distance:.1f} meters)"
        approach_instruction = "Walk forward, it's quite far"
    
    # Combine instructions
    if abs(angle) < 2:
        full_instruction = f"{approach_instruction}. Target is directly ahead, {distance_desc}."
    else:
        full_instruction = f"{turn_instruction}, then {approach_instruction.lower()}. Target is {distance_desc}."
    
    return {
        "direction": turn_direction,
        "distance": distance_desc,
        "confidence": avg_confidence,
        "target_count": len(target_objs),
        "navigation": {
            "angle_degrees": angle,
            "distance_meters": distance,
            "turn_instruction": turn_instruction,
            "approach_instruction": approach_instruction,
            "full_instruction": full_instruction,
            "position_description": best_target["position"],
            "coordinates": best_target["coordinates"]
        }
    }


def _free_path_direction(objects: List[ObjectDetection], img_width: float = 640.0) -> Dict[str, Any]:
    """Fallback: infer best open path direction when requested target not detected.
    Strategy: build occupied horizontal intervals from object bboxes, find widest gap, map its center to direction.
    """
    intervals = []
    for o in objects:
        if not o.bbox or len(o.bbox) != 4:
            continue
        x1, _, x2, _ = o.bbox
        # clip
        x1 = max(0.0, min(img_width, x1))
        x2 = max(0.0, min(img_width, x2))
        if x2 <= x1:
            continue
        intervals.append((x1 / img_width, x2 / img_width))

    if not intervals:
        # Completely clear
        return {"direction": "center", "distance": "clear", "confidence": 0.5}

    # Merge overlapping intervals
    intervals.sort(key=lambda x: x[0])
    merged = []
    cur_s, cur_e = intervals[0]
    for s, e in intervals[1:]:
        if s <= cur_e + 0.01:  # small tolerance
            cur_e = max(cur_e, e)
        else:
            merged.append((cur_s, cur_e))
            cur_s, cur_e = s, e
    merged.append((cur_s, cur_e))

    # Find gaps between merged intervals
    gaps = []
    prev_end = 0.0
    for s, e in merged:
        if s - prev_end > 0.05:  # meaningful gap
            gaps.append((prev_end, s))
        prev_end = e
    if 1.0 - prev_end > 0.05:
        gaps.append((prev_end, 1.0))

    if not gaps:
        # No discernible gap; pick smallest coverage side
        # Choose side with less coverage
        left_coverage = sum(max(0.0, min(e, 0.5) - s) for s, e in merged if s < 0.5)
        right_coverage = sum(max(0.0, e - max(s, 0.5)) for s, e in merged if e > 0.5)
        direction = "left" if left_coverage < right_coverage else "right"
        nearest_distance = _nearest_obstacle_distance(objects)
        return {"direction": direction, "distance": nearest_distance, "confidence": 0.3}

    # Widest gap
    widest = max(gaps, key=lambda g: g[1] - g[0])
    gap_center = (widest[0] + widest[1]) / 2.0
    rel = gap_center - 0.5
    if abs(rel) < 0.06:
        direction = "center"
    elif rel < -0.3:
        direction = "hard left"
    elif rel < -0.15:
        direction = "left"
    elif rel < -0.06:
        direction = "slightly left"
    elif rel > 0.3:
        direction = "hard right"
    elif rel > 0.15:
        direction = "right"
    elif rel > 0.06:
        direction = "slightly right"
    else:
        direction = "center"

    nearest_distance = _nearest_obstacle_distance(objects)
    return {"direction": direction, "distance": nearest_distance, "confidence": 0.45, "target_count": 0}


def _nearest_obstacle_distance(objects: List[ObjectDetection]) -> str:
    order = ["very close", "close", "medium", "far", "very far", "unknown", "clear"]
    best_rank = len(order)
    best = "clear"
    for o in objects:
        d = _estimate_distance(o)
        if d in order and order.index(d) < best_rank:
            best_rank = order.index(d)
            best = d
    return best


def _analyze_obstacles(objects: List[ObjectDetection], target_objs: List[ObjectDetection], img_width: float = 640.0, img_height: float = 480.0) -> List[Dict[str, Any]]:
    """Analyze obstacles in path with distance and position info."""
    obstacles = []
    
    for o in objects:
        if o in target_objs or not o.bbox:
            continue
            
        x1, y1, x2, y2 = o.bbox
        cx = (x1 + x2) / 2.0
        cy = (y1 + y2) / 2.0
        width = x2 - x1
        height = y2 - y1
        area = width * height
        
        # Horizontal position
        rel_x = cx / img_width
        rel_y = cy / img_height
        
        # Distance estimation
        distance = _estimate_distance(o, img_height)
        
        # Check if obstacle is in path (central area)
        in_path = 0.25 < rel_x < 0.75 and rel_y > 0.3
        
        # Size-based threat level
        rel_area = area / (img_width * img_height)
        if rel_area > 0.15:
            threat = "high"
        elif rel_area > 0.08:
            threat = "medium" 
        else:
            threat = "low"
            
        # Only include significant obstacles
        if in_path and (threat in ["high", "medium"] or distance in ["very close", "close"]):
            obstacles.append({
                "name": str(o.name),
                "distance": str(distance),
                "position": "left" if rel_x < 0.4 else "right" if rel_x > 0.6 else "center",
                "threat": str(threat),
                "confidence": float(o.confidence),
            })
    
    # Sort by distance (closest first) then by threat
    distance_order = {"very close": 0, "close": 1, "medium": 2, "far": 3, "very far": 4}
    threat_order = {"high": 0, "medium": 1, "low": 2}

    def _sort_key(o: Dict[str, Any]):
        # ensure keys accessed as strings for type checker
        d_val = o.get("distance")  # type: ignore[arg-type]
        t_val = o.get("threat")    # type: ignore[arg-type]
        d = str(d_val) if d_val is not None else ""
        t = str(t_val) if t_val is not None else ""
        return (distance_order.get(d, 5), threat_order.get(t, 3))

    obstacles.sort(key=_sort_key)
    return obstacles[:3]  # Max 3 most important obstacles


def _path_smoothing_instruction(direction_info: Dict[str, Any], obstacles: List[Dict[str, Any]], target_name: Optional[str]) -> str:
    """Generate smooth, human-friendly navigation instruction with varied phrasing."""
    direction = direction_info["direction"]
    distance = direction_info["distance"]
    confidence = direction_info["confidence"]
    target_count = direction_info.get("target_count", 0)

    # Human readable target reference
    if target_name and target_name != "path":
        if target_count > 1:
            target_ref = f"the {target_name}s"
        else:
            article = "the" if target_name.lower().startswith(('d','e','a','o','u')) else "the"
            target_ref = f"{article} {target_name}".strip()
    elif target_name == "path":
        target_ref = "the clear path"
    else:
        target_ref = "it"

    # Variant templates (each list contains alternative phrasings)
    variants = {
        "center": {
            "very close": [f"{target_ref} is right in front. Slow and steady.", f"Almost there—{target_ref} directly ahead, ease forward."],
            "close": [f"{target_ref} straight ahead, move forward carefully.", f"Head straight—{target_ref} is just ahead."],
            "medium": [f"{target_ref} ahead, continue forward.", f"Keep going straight toward {target_ref}."],
            "far": [f"{target_ref} further ahead, steady pace.", f"Stay centered and continue forward."],
            "very far": [f"{target_ref} is far ahead, you can walk confidently.", f"Long way ahead—proceed straight."]
        },
        "slightly left": {
            "very close": [f"{target_ref} just left, small step left then forward.", f"Tiny left adjustment, then move ahead."],
            "close": [f"Drift a little left toward {target_ref}.", f"Slight left, then forward."],
            "medium": [f"Slight left adjustment toward {target_ref}.", f"Nudge left and go ahead."],
            "far": [f"Angle slightly left to line up with {target_ref}.", f"Veer gently left then continue."],
            "very far": [f"Turn a touch left and continue toward it.", f"Bring your direction a bit left and walk on."]
        },
        "left": {
            "very close": [f"{target_ref} is close on your left—turn carefully.", f"Slow left turn, {target_ref} is right there."],
            "close": [f"Turn left and move forward slowly.", f"Left turn now, then straight."],
            "medium": [f"Turn left toward {target_ref} then walk ahead.", f"Face left and proceed forward."],
            "far": [f"Turn left and advance toward it.", f"Rotate left then continue walking."],
            "very far": [f"Head left and keep a steady pace.", f"Take a left heading and continue."]
        },
        "hard left": {
            "very close": [f"Sharp left needed now—go slowly.", f"Hard left turn here, take care."],
            "close": [f"Make a firm left turn toward {target_ref}.", f"Strong left turn, then forward."],
            "medium": [f"Hard left to align, then continue.", f"Pivot left sharply and proceed."],
            "far": [f"Big left turn, then head forward.", f"Swing left strongly and advance."],
            "very far": [f"Hard left then steady walk ahead.", f"Rotate left fully and continue."]
        },
        "slightly right": {
            "very close": [f"Just right a little, then ahead.", f"Tiny step right then move forward."],
            "close": [f"Ease slightly right toward {target_ref}.", f"Shift a bit right then continue."],
            "medium": [f"Nudge right and go on.", f"Slight right correction then forward."],
            "far": [f"Angle a little right then continue.", f"Veer gently right toward it."],
            "very far": [f"Turn a touch right and walk forward.", f"Bring your direction a bit right and proceed."]
        },
        "right": {
            "very close": [f"{target_ref} close on your right—turn carefully.", f"Slow right turn, it's right there."],
            "close": [f"Turn right and move forward slowly.", f"Right turn now, then straight ahead."],
            "medium": [f"Turn right toward {target_ref} then walk ahead.", f"Face right and proceed forward."],
            "far": [f"Turn right and advance toward it.", f"Rotate right then continue walking."],
            "very far": [f"Head right and keep a steady pace.", f"Take a right heading and continue."]
        },
        "hard right": {
            "very close": [f"Sharp right needed now—go slowly.", f"Hard right turn here, take care."],
            "close": [f"Make a firm right turn toward {target_ref}.", f"Strong right turn, then forward."],
            "medium": [f"Hard right to align, then continue.", f"Pivot right sharply and proceed."],
            "far": [f"Big right turn, then head forward.", f"Swing right strongly and advance."],
            "very far": [f"Hard right then steady walk ahead.", f"Rotate right fully and continue."]
        }
    }

    # Default catch-all
    phrase_list = variants.get(direction, {}).get(distance, [f"Move {direction} ({distance})."])
    # Deterministic selection (avoid randomness jitter): hash of direction+distance
    idx = (abs(hash(direction + distance)) % len(phrase_list)) if phrase_list else 0
    base_instruction = phrase_list[idx]

    # Obstacle warnings (concise, natural)
    if obstacles:
        close_obs = [obs for obs in obstacles if obs.get("distance") in ("very close", "close")]
        if close_obs:
            names = []
            for o in close_obs[:2]:
                names.append(f"{o['name']} {o['position']}")
            warn = ", ".join(names)
            base_instruction += f". Watch for {warn}."

    # Low confidence hint
    if confidence < 0.4:
        base_instruction += " I'm not fully sure—double check."  # human tone

    # Gentle ending punctuation normalization
    base_instruction = base_instruction.strip()
    if not base_instruction.endswith(('.', '!', '?')):
        base_instruction += '.'
    return base_instruction


def _movement_instruction(direction: str, target: Optional[str], obstacles: List[str]) -> str:
    base_target = f"Target {target}" if target else "Target object"
    dir_map = {
        "center": f"{base_target} ahead. Move forward.",
        "slightly left": f"{base_target} slightly to your left. Step a little left then forward.",
        "left": f"{base_target} to your left. Turn left and move forward cautiously.",
        "slightly right": f"{base_target} slightly to your right. Step a little right then forward.",
        "right": f"{base_target} to your right. Turn right and move forward cautiously.",
        "unknown": "Target not clearly detected. Adjust slowly or ask again with another image.",
    }
    instr = dir_map.get(direction, dir_map["unknown"])
    if obstacles:
        unique_obs = sorted(set(obstacles))[:3]
        instr += f" Caution: {', '.join(unique_obs)} ahead." 
    return instr


def _compute_guidance(objects: List[ObjectDetection], question: str, img_width: float = 640.0, img_height: float = 480.0) -> Dict[str, Any]:
    """Enhanced guidance computation with precise positioning and navigation instructions."""
    targets = _extract_targets(question or "")
    target_name = None
    target_objs: List[ObjectDetection] = []
    
    # Find best matching target
    for t in targets:
        matches = [o for o in objects if t in o.name.lower()]
        if matches:
            target_name = t
            target_objs = matches
            break
    
    # Get enhanced direction info with precise positioning
    direction_info = _direction_for_targets(target_objs, img_width, img_height)

    # Fallback: if user asked for something not in COCO (e.g., 'door', 'exit')
    if direction_info["direction"] == "unknown":
        # Try open path inference
        open_path = _free_path_direction(objects, img_width)
        direction_info.update(open_path)
        if not target_name:
            target_name = "path"
    
    # Analyze obstacles in path
    obstacles = _analyze_obstacles(objects, target_objs, img_width, img_height)
    
    # Generate enhanced instruction with precise positioning
    if "navigation" in direction_info and direction_info["navigation"]:
        nav_data = direction_info["navigation"]
        instruction = nav_data["full_instruction"]
        
        # Add obstacle warnings if needed
        if obstacles:
            close_obs = [obs for obs in obstacles if obs.get("distance") in ("very close", "close")]
            if close_obs:
                obstacle_warning = f" Caution: {close_obs[0]['name']} detected {close_obs[0]['position']}."
                instruction += obstacle_warning
    else:
        # Fallback to basic instruction
        instruction = _path_smoothing_instruction(direction_info, obstacles, target_name)
    
    return {
        "target": target_name,
        "direction": direction_info["direction"],
        "distance": direction_info["distance"],
        "confidence": direction_info["confidence"],
        "instruction": instruction,
        "obstacles": obstacles,
        "target_count": direction_info.get("target_count", 0),
        "navigation_data": direction_info.get("navigation", {}),
        "precise_positioning": True
    }


@app.post("/find-object")
async def find_specific_object(file: UploadFile = File(...), query: str = Form(...)):
    """Find a specific object requested by voice command and provide its precise location."""
    try:
        if not yolo_model:
            raise HTTPException(status_code=500, detail="Detection model not loaded")

        logger.info(f"Finding object: '{query}' in image: {file.filename}")

        contents = await file.read()
        image = Image.open(io.BytesIO(contents))

        # Resize image for processing
        max_size = 640
        original_width, original_height = image.size
        if max(image.size) > max_size:
            image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        img_width, img_height = image.size
        img_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

        # Run object detection
        with torch.no_grad():
            results = yolo_model(img_array, conf=0.25, verbose=False)

        # Extract target object from query
        target_keywords = _extract_targets(query)
        target_objects = []
        all_objects = []

        if results:
            for result in results:
                if getattr(result, 'boxes', None):
                    for box in result.boxes:
                        try:
                            conf = float(box.conf[0])
                            if conf <= 0.35:
                                continue
                            cls_id = int(box.cls[0])
                            name = yolo_model.names[cls_id]
                            bbox = box.xyxy[0].tolist()
                            
                            obj = ObjectDetection(name=name, confidence=conf, bbox=bbox)
                            all_objects.append(obj)
                            
                            # Check if this object matches what user is looking for
                            for target in target_keywords:
                                if target.lower() in name.lower() or name.lower() in target.lower():
                                    target_objects.append(obj)
                                    
                        except Exception:
                            continue

        # Determine object location and response
        if target_objects:
            # Find the best match (highest confidence)
            best_match = max(target_objects, key=lambda x: x.confidence)
            
            # Calculate precise position using enhanced positioning
            precise_pos = _calculate_precise_position(best_match, img_width, img_height)
            
            # Generate detailed navigation instruction
            angle = precise_pos["angle"]
            distance_m = precise_pos["distance_meters"]
            
            # Create detailed turn-by-turn instruction
            if abs(angle) < 2:
                direction_instruction = "The object is directly in front of you."
                navigation_steps = ["Continue walking straight ahead"]
            elif abs(angle) < 15:
                direction_instruction = f"The object is {abs(angle):.1f} degrees to your {'left' if angle < 0 else 'right'}."
                navigation_steps = [
                    f"Turn slightly {'left' if angle < 0 else 'right'} by about {abs(angle):.0f} degrees",
                    "Then walk straight towards the object"
                ]
            elif abs(angle) < 45:
                direction_instruction = f"The object is {abs(angle):.1f} degrees to your {'left' if angle < 0 else 'right'}."
                navigation_steps = [
                    f"Turn {'left' if angle < 0 else 'right'} by {abs(angle):.0f} degrees",
                    f"Walk forward approximately {distance_m:.1f} meters"
                ]
            else:
                direction_instruction = f"The object is {abs(angle):.1f} degrees to your {'left' if angle < 0 else 'right'} - almost behind you."
                navigation_steps = [
                    f"Turn around {'left' if angle < 0 else 'right'} by {abs(angle):.0f} degrees",
                    f"Walk forward approximately {distance_m:.1f} meters"
                ]
            
            # Distance guidance
            if distance_m < 1:
                distance_guidance = "You're very close. Move carefully."
            elif distance_m < 3:
                distance_guidance = f"Take about {int(distance_m * 1.5)} steps forward."
            elif distance_m < 10:
                distance_guidance = f"Walk about {distance_m:.0f} meters forward."
            else:
                distance_guidance = f"The object is quite far - about {distance_m:.0f} meters away."
            
            response = {
                "status": "found",
                "object_name": best_match.name,
                "confidence": float(best_match.confidence),
                "position": precise_pos["position"],
                "distance": f"{distance_m:.1f} meters",
                "message": f"Found {best_match.name}! {direction_instruction} Distance: {distance_m:.1f} meters.",
                "bbox": best_match.bbox,
                "precise_position": {
                    "angle_degrees": angle,
                    "distance_meters": distance_m,
                    "coordinates": precise_pos["coordinates"],
                    "direction_instruction": direction_instruction,
                    "navigation_steps": navigation_steps,
                    "distance_guidance": distance_guidance
                },
                "navigation_instruction": f"{direction_instruction} {distance_guidance}",
                "step_by_step": navigation_steps,
                "all_detected": [obj.to_client_dict() for obj in all_objects[:5]]
            }
            
        else:
            # Object not found - provide helpful alternatives
            response = {
                "status": "not_found",
                "object_name": target_keywords[0] if target_keywords else query,
                "message": f"Could not find {target_keywords[0] if target_keywords else query}. Try looking around or describe what you're looking for differently.",
                "all_detected": [obj.to_client_dict() for obj in all_objects[:5]],
                "suggestions": []
            }
            
            # Add helpful suggestions based on what was detected
            if all_objects:
                similar_objects = []
                query_lower = query.lower()
                for obj in all_objects:
                    obj_name = obj.name.lower()
                    # Look for partial matches or related objects
                    if any(word in obj_name for word in query_lower.split()) or any(word in query_lower for word in obj_name.split()):
                        similar_objects.append(obj.name)
                
                if similar_objects:
                    response["suggestions"] = similar_objects[:3]
                    response["message"] += f" However, I found similar objects: {', '.join(similar_objects[:3])}"

        logger.info(f"Object search complete: {response['status']}")
        return JSONResponse(content=response)
        
    except Exception as e:
        logger.error(f"Error in object finding: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/analyze")
async def analyze_scene(file: UploadFile = File(...)):
    """Detect objects and return a concise scene description plus objects in frontend shape."""
    try:
        if not yolo_model or not blip_model or not blip_processor:
            error_details = []
            if not yolo_model:
                error_details.append("YOLOv8 model not loaded")
            if not blip_model:
                error_details.append("BLIP model not loaded")
            if not blip_processor:
                error_details.append("BLIP processor not loaded")
            error_msg = f"Models still loading: {', '.join(error_details)}"
            logger.warning(error_msg)
            # Return a friendly response instead of crashing
            return JSONResponse(content={
                "scene_description": "Camera is working perfectly. Automatic flashlight is active. AI models are still loading - please try again in a moment.",
                "objects": []
            })

        logger.info(f"Analyzing image: {file.filename}")

        contents = await file.read()
        image = Image.open(io.BytesIO(contents))

        # Resize
        max_size = 640
        if max(image.size) > max_size:
            image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)

        img_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

        # YOLO detection
        with torch.no_grad():
            results = yolo_model(img_array, conf=0.25, verbose=False)

        objects: List[ObjectDetection] = []
        if results:
            for result in results:
                if getattr(result, 'boxes', None):
                    for box in result.boxes:
                        try:
                            conf = float(box.conf[0])
                            if conf <= 0.35:
                                continue
                            cls_id = int(box.cls[0])
                            name = yolo_model.names[cls_id]
                            bbox = box.xyxy[0].tolist()
                            objects.append(ObjectDetection(name=name, confidence=conf, bbox=bbox))
                        except Exception:
                            continue

        # (Optional) quick BLIP run to keep model warm
        try:
            with torch.no_grad():
                inputs = blip_processor(image, return_tensors="pt")
                if device and getattr(device, 'type', '') == 'cuda':
                    inputs = {k: v.to(device) for k, v in inputs.items()}
                    blip_output = blip_model.generate(**inputs, max_length=30, num_beams=4)
                else:
                    blip_output = blip_model.generate(**inputs, max_length=30, num_beams=4)
                scene_caption = blip_processor.decode(blip_output[0], skip_special_tokens=True)
        except Exception as cap_err:
            logger.warning(f"BLIP skipped: {cap_err}")
            scene_caption = "Scene analysis unavailable"

        # Extract text using OCR
        extracted_text = _extract_text_from_image(img_array)
        
        focused = _focused_description(objects)
        
        # Combine scene caption with object-focused description and text
        description_parts = [f"Scene: {scene_caption}"]
        
        if objects:
            description_parts.append(f"Objects detected: {focused}")
        else:
            description_parts.append("No specific objects detected in view")
            
        if extracted_text:
            description_parts.append(f"Text found: {extracted_text}")
        
        full_description = ". ".join(description_parts) + "."
        
        logger.info(f"Analysis complete: {len(objects)} objects, text: {'Yes' if extracted_text else 'None'}. Full description: {full_description}")

        client_objects = [o.to_client_dict() for o in objects]
        
        # Include OCR text in response
        response_data = {
            "scene_description": full_description, 
            "objects": client_objects
        }
        
        if extracted_text:
            response_data["extracted_text"] = extracted_text
            
        return JSONResponse(content=response_data)
    except Exception as e:
        error_msg = f"Error analyzing scene: {str(e)} | Type: {type(e).__name__}"
        logger.error(error_msg)
        import traceback
        logger.error(f"Traceback: {traceback.format_exc()}")
        raise HTTPException(status_code=500, detail=error_msg)


@app.post("/guide", response_model=GuideResponse)
async def real_time_guidance(file: UploadFile = File(...), question: str = Form(...)):
    """Real-time guidance: analyze current frame and provide precise navigation with angles and distances."""
    try:
        if not yolo_model:
            raise HTTPException(status_code=500, detail="Detection model not loaded")

        contents = await file.read()
        image = Image.open(io.BytesIO(contents))

        max_size = 640
        if max(image.size) > max_size:
            image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        img_width, img_height = image.size
        img_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

        with torch.no_grad():
            results = yolo_model(img_array, conf=0.25, verbose=False)

        objects: List[ObjectDetection] = []
        if results:
            for result in results:
                if getattr(result, 'boxes', None):
                    for box in result.boxes:
                        try:
                            conf = float(box.conf[0])
                            if conf <= 0.35:
                                continue
                            cls_id = int(box.cls[0])
                            name = yolo_model.names[cls_id]
                            bbox = box.xyxy[0].tolist()
                            objects.append(ObjectDetection(name=name, confidence=conf, bbox=bbox))
                        except Exception:
                            continue

        focused = _focused_description(objects)
        
        # Use enhanced guidance computation with precise positioning
        guidance = _compute_guidance(objects, question, img_width, img_height)

        # Create enhanced response with navigation data
        response_data = {
            "target": guidance["target"],
            "direction": guidance["direction"],
            "distance": guidance["distance"],
            "confidence": float(guidance["confidence"]),
            "instruction": guidance["instruction"],
            "scene_description": focused,
            "objects": objects,
            "obstacles": [ObstacleInfo(**o) for o in guidance.get("obstacles", [])],
        }
        
        # Add navigation data if available
        if guidance.get("navigation_data"):
            nav_data = guidance["navigation_data"]
            # Store navigation data in the instruction for now (can be enhanced in Flutter)
            if nav_data.get("angle_degrees") is not None:
                angle = nav_data["angle_degrees"]
                distance_m = nav_data.get("distance_meters", 0)
                
                # Add precise positioning to instruction
                if abs(angle) > 2:
                    response_data["instruction"] += f" [Precise: {abs(angle):.1f}° {'left' if angle < 0 else 'right'}, {distance_m:.1f}m]"
                else:
                    response_data["instruction"] += f" [Precise: straight ahead, {distance_m:.1f}m]"

        return GuideResponse(**response_data)
    except Exception as e:
        logger.error(f"Error in guidance: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/qa", response_model=AnswerResponse)
async def question_answering(request: QuestionRequest):
    """Answer questions about the scene using GPT-4o-mini."""
    try:
        if not openai_client:
            raise HTTPException(status_code=500, detail="OpenAI client not initialized")

        objs = request.objects or []
        high_conf_objects = [o for o in objs if o.confidence > 0.5]
        objects_text = ", ".join([o.name for o in high_conf_objects[:5]])
        scene_snip = (request.scene_description or "").strip()[:120]

        prompt = (
            f"Scene summary: {scene_snip if scene_snip else 'No summary available'}\n"
            f"Key objects: {objects_text if objects_text else 'none'}\n"
            f"Question: {request.question}\n\n"
            "Provide a concise actionable answer (<=2 short sentences) for a blind user. Avoid percentages."
        )

        response = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You help visually impaired users. Give brief, clear answers."},
                {"role": "user", "content": prompt},
            ],
            max_tokens=60,
            temperature=0.1,
            top_p=0.9,
        )
        raw_answer = response.choices[0].message.content if response.choices else ""
        answer = (raw_answer or "").strip()
        for token in ["confidence", "%"]:
            if token in answer.lower():
                answer = answer.replace(token, "")
        return AnswerResponse(answer=answer.strip())
    except Exception as e:
        logger.error(f"Error in question answering: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/navigate-to")
async def navigate_to(file: UploadFile = File(...), destination: str = Form(...)):
    """Provide precise turn-by-turn navigation guidance to reach a specific location or object"""
    try:
        if not yolo_model or not blip_model or not blip_processor:
            raise HTTPException(status_code=500, detail="Models not loaded")
        
        logger.info(f"Navigating to: '{destination}' in image: {file.filename}")
        
        # Read and process image
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))
        
        # Resize image for processing
        max_size = 640
        original_width, original_height = image.size
        if max(image.size) > max_size:
            image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        
        img_width, img_height = image.size
        img_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
        
        # YOLO object detection for spatial awareness
        with torch.no_grad():
            results = yolo_model(img_array, conf=0.25, verbose=False)
        
        detections = []
        objects = []
        for result in results:
            if getattr(result, 'boxes', None):
                for box in result.boxes:
                    try:
                        conf = float(box.conf[0])
                        if conf <= 0.35:
                            continue
                        cls_id = int(box.cls[0])
                        label = yolo_model.names[cls_id]
                        bbox = box.xyxy[0].tolist()
                        
                        obj = ObjectDetection(name=label, confidence=conf, bbox=bbox)
                        objects.append(obj)
                        
                        # Calculate precise position for each detection
                        precise_pos = _calculate_precise_position(obj, img_width, img_height)
                        
                        detections.append({
                            "label": label,
                            "confidence": conf,
                            "bbox": bbox,
                            "precise_position": precise_pos
                        })
                    except Exception:
                        continue
        
        # Get image caption for environmental context
        with torch.no_grad():
            inputs = blip_processor(image, return_tensors="pt")
            if device and getattr(device, 'type', '') == 'cuda':
                inputs = {k: v.to(device) for k, v in inputs.items()}
            outputs = blip_model.generate(**inputs, max_length=30, num_beams=4)
            caption = blip_processor.decode(outputs[0], skip_special_tokens=True)
        
        # Find target object/location using enhanced guidance computation
        guidance_result = _compute_guidance(objects, f"navigate to {destination}", img_width, img_height)
        
        found_target = None
        target_keywords = _extract_targets(destination)
        
        # Look for direct matches first
        for target in target_keywords:
            for detection in detections:
                if target.lower() in detection["label"].lower() or detection["label"].lower() in target.lower():
                    found_target = detection
                    break
            if found_target:
                break
        
        if found_target or guidance_result.get("navigation_data"):
            # Target found or navigation guidance available
            if found_target:
                # Use found target's precise positioning
                precise_pos = found_target["precise_position"]
                angle = precise_pos["angle"]  # Fixed: use "angle" not "angle_degrees"
                distance_m = precise_pos["distance_meters"]
                target_name = found_target["label"]
            else:
                # Use guidance system's navigation data
                nav_data = guidance_result.get("navigation_data", {})
                angle = nav_data.get("angle_degrees", 0)
                distance_m = nav_data.get("distance_meters", 5.0)
                target_name = guidance_result.get("target", destination)
            
            # Generate comprehensive turn-by-turn navigation
            navigation_steps = []
            
            # Step 1: Initial orientation
            if abs(angle) < 3:
                navigation_steps.append("1. You're facing the right direction")
                heading_instruction = "Continue straight ahead"
            elif abs(angle) < 15:
                navigation_steps.append(f"1. Turn slightly {'left' if angle < 0 else 'right'} ({abs(angle):.0f} degrees)")
                heading_instruction = f"Small adjustment: turn {abs(angle):.0f} degrees {'left' if angle < 0 else 'right'}"
            elif abs(angle) < 45:
                navigation_steps.append(f"1. Turn {'left' if angle < 0 else 'right'} ({abs(angle):.0f} degrees)")
                heading_instruction = f"Turn {'left' if angle < 0 else 'right'} by {abs(angle):.0f} degrees"
            elif abs(angle) < 90:
                navigation_steps.append(f"1. Turn sharply {'left' if angle < 0 else 'right'} ({abs(angle):.0f} degrees)")
                heading_instruction = f"Sharp turn {'left' if angle < 0 else 'right'} - {abs(angle):.0f} degrees"
            else:
                navigation_steps.append(f"1. Turn around {'left' if angle < 0 else 'right'} ({abs(angle):.0f} degrees)")
                heading_instruction = f"Turn around {'left' if angle < 0 else 'right'} - the target is behind you"
            
            # Step 2: Distance and movement
            if distance_m < 1:
                navigation_steps.append("2. Move very slowly - you're almost there")
                movement_instruction = "Take 1-2 careful steps forward"
                estimated_steps = "1-2 steps"
            elif distance_m < 3:
                steps = int(distance_m * 1.3)  # ~1.3 steps per meter
                navigation_steps.append(f"2. Walk forward about {steps} steps")
                movement_instruction = f"Walk {steps} steps forward"
                estimated_steps = f"{steps} steps"
            elif distance_m < 10:
                navigation_steps.append(f"2. Walk forward about {distance_m:.0f} meters")
                movement_instruction = f"Walk {distance_m:.0f} meters forward"
                estimated_steps = f"{distance_m:.0f} meters"
            else:
                navigation_steps.append(f"2. Walk forward - it's quite far ({distance_m:.0f} meters)")
                movement_instruction = f"Long walk ahead - {distance_m:.0f} meters"
                estimated_steps = f"{distance_m:.0f} meters"
            
            # Step 3: Safety and obstacles
            obstacles_in_path = [d for d in detections if d["precise_position"]["angle"] < 30 and d["precise_position"]["distance_meters"] < distance_m + 2]
            if obstacles_in_path:
                obstacle_names = [d["label"] for d in obstacles_in_path[:2]]
                navigation_steps.append(f"3. Watch out for: {', '.join(obstacle_names)} on your path")
                safety_warning = f"Caution: {', '.join(obstacle_names)} detected ahead"
            else:
                navigation_steps.append("3. Path appears clear")
                safety_warning = "Path looks clear"
            
            # Create comprehensive response
            summary_instruction = f"To reach {target_name}: {heading_instruction}, then {movement_instruction.lower()}."
            
            response = {
                "status": "found",
                "found": True,
                "target": target_name,
                "direction": {
                    "angle_degrees": angle,  # Ensure consistent naming for frontend
                    "distance_meters": distance_m,
                    "heading_instruction": heading_instruction,
                    "movement_instruction": movement_instruction,
                    "estimated_steps": estimated_steps
                },
                "navigation": {
                    "steps": navigation_steps,
                    "summary": summary_instruction,
                    "safety_warning": safety_warning,
                    "total_distance": f"{distance_m:.1f} meters",
                    "estimated_time": f"{int(distance_m / 1.2)} seconds" if distance_m < 20 else f"{int(distance_m / 1.2 / 60)} minutes"
                },
                "response": summary_instruction,
                "message": summary_instruction,
                "step_by_step_navigation": navigation_steps,
                "environment": caption,
                "precise_positioning": True
            }
        else:
            # Target not found, provide environmental guidance with enhanced obstacle analysis
            obstacles = []
            path_analysis = []
            
            # Analyze environment for navigation
            left_objects = [d for d in detections if d["precise_position"]["angle"] < -15]
            right_objects = [d for d in detections if d["precise_position"]["angle"] > 15]
            center_objects = [d for d in detections if abs(d["precise_position"]["angle"]) <= 15]
            
            # Provide path recommendations
            if not center_objects:
                path_analysis.append("Path ahead is clear")
                recommended_action = "Continue straight and explore ahead"
            elif len(left_objects) < len(right_objects):
                path_analysis.append("Clearer path to the left")
                recommended_action = "Try turning left to explore"
            elif len(right_objects) < len(left_objects):
                path_analysis.append("Clearer path to the right")
                recommended_action = "Try turning right to explore"
            else:
                path_analysis.append("Objects detected in multiple directions")
                recommended_action = "Proceed carefully and look around"
            
            # List nearby objects with their positions
            for detection in detections[:4]:  # Limit to 4 most confident
                pos = detection["precise_position"]
                obstacles.append(f"{detection['label']} at {pos['distance_meters']:.1f}m, {pos['angle']:.0f}° {'left' if pos['angle'] < 0 else 'right'}")
            
            response_text = f"I don't see {destination} in your current view. Environment: {caption}. "
            response_text += f"Nearby objects: {'; '.join(obstacles[:3]) if obstacles else 'none detected'}. "
            response_text += f"Recommendation: {recommended_action}."
            
            response = {
                "status": "not_found",
                "found": False,
                "target": destination,
                "obstacles": obstacles,
                "path_analysis": path_analysis,
                "recommended_action": recommended_action,
                "environment": caption,
                "response": response_text,
                "message": response_text,
                "exploration_suggestions": [
                    "Turn left 90 degrees and look again",
                    "Turn right 90 degrees and look again", 
                    "Move forward 2-3 steps and scan again",
                    "Ask for help describing the area"
                ]
            }
        
        logger.info(f"Navigation complete: {response['status']}")
        return JSONResponse(content=response)
        
    except Exception as e:
        logger.error(f"Error in navigate_to: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.websocket("/ws/guide")
async def ws_real_time_guidance(ws: WebSocket):
    """WebSocket for continuous real-time guidance.
    Client sends JSON messages: {"image": base64_jpeg, "question": "find door"}
    Server responds with JSON containing scene_description, instruction, direction, target, objects.
    Throttles processing to avoid GPU overload; will acknowledge throttled frames.
    """
    await ws.accept()
    if not yolo_model:
        await ws.send_json({"error": "model_not_loaded"})
        await ws.close()
        return

    last_instruction = None
    last_sent_time = 0.0
    throttle_seconds = 0.3  # adjust for performance
    instruction_repeat_sec = 2.0

    try:
        while True:
            try:
                msg = await ws.receive_text()
            except WebSocketDisconnect:
                break
            except Exception as rec_err:
                await ws.send_json({"error": "receive_error", "detail": str(rec_err)})
                continue

            try:
                data = json.loads(msg)
            except json.JSONDecodeError:
                await ws.send_json({"error": "bad_json"})
                continue

            b64 = data.get("image")
            question = data.get("question", "")
            now = time.time()
            if not b64:
                await ws.send_json({"error": "no_image"})
                continue
            if now - last_sent_time < throttle_seconds:
                # Skip heavy processing, inform client
                await ws.send_json({"status": "throttled"})
                continue

            try:
                img_bytes = base64.b64decode(b64)
                image = Image.open(io.BytesIO(img_bytes)).convert("RGB")
                if max(image.size) > 640:
                    image.thumbnail((640, 640), Image.Resampling.LANCZOS)
                img_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)

                with torch.no_grad():
                    results = yolo_model(img_array, conf=0.25, verbose=False)

                objects: List[ObjectDetection] = []
                if results:
                    for result in results:
                        if getattr(result, 'boxes', None):
                            for box in result.boxes:
                                try:
                                    conf = float(box.conf[0])
                                    if conf <= 0.35:
                                        continue
                                    cls_id = int(box.cls[0])
                                    name = yolo_model.names[cls_id]
                                    bbox = box.xyxy[0].tolist()
                                    objects.append(ObjectDetection(name=name, confidence=conf, bbox=bbox))
                                except Exception:
                                    continue

                focused = _focused_description(objects)
                guidance = _compute_guidance(objects, question)

                # Only send full instruction if changed or timeout
                send_instruction = (
                    guidance["instruction"] != last_instruction or
                    (now - last_sent_time) > instruction_repeat_sec
                )
                if send_instruction:
                    last_instruction = guidance["instruction"]
                    last_sent_time = now

                payload = {
                    "scene_description": focused,
                    "instruction": guidance["instruction"] if send_instruction else "",
                    "direction": guidance["direction"],
                    "distance": guidance["distance"],
                    "confidence": guidance["confidence"],
                    "target": guidance["target"],
                    "obstacles": guidance.get("obstacles", []),
                    "objects": [o.to_client_dict() for o in objects],
                    "ts": now,
                }
                await ws.send_text(json.dumps(payload))
            except Exception as frame_err:
                logger.error(f"ws frame error: {frame_err}")
                await ws.send_json({"error": "frame_processing_failed"})
                continue
    finally:
        try:
            await ws.close()
        except Exception:
            pass

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    
    print(f"\n🚀 Starting Vision Mate Backend Server...")
    print(f"📍 Local access: http://127.0.0.1:{port}")
    print(f"📍 Network access: http://10.227.99.126:{port}")
    print(f"📍 Health check: http://10.227.99.126:{port}/health")
    print("🔧 Make sure your phone and laptop are on the same WiFi!")
    print("📱 Flutter app configured for: http://10.227.99.126:8000")
    print("=" * 65)
    
    uvicorn.run(app, host=host, port=port)
