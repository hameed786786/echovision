"""
Vision Mate Backend Server - Fixed Version
Handles scene analysis and Q&A for visually impaired users
"""

from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager
import cv2
import numpy as np
from PIL import Image
import io
import base64
import os
import torch
import logging
from dotenv import load_dotenv
import openai
from ultralytics import YOLO
from transformers import BlipProcessor, BlipForConditionalGeneration

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global variables for models
yolo_model = None
blip_model = None
blip_processor = None
openai_client = None
device = None

# API Models
from pydantic import BaseModel
from typing import List, Optional

class ObjectDetection(BaseModel):
    name: str
    confidence: float
    bbox: List[float]

class DetectionResponse(BaseModel):
    objects: List[ObjectDetection]
    count: int

class SceneDescription(BaseModel):
    description: str

class QuestionRequest(BaseModel):
    scene_description: str
    objects: List[ObjectDetection]
    question: str

class AnswerResponse(BaseModel):
    answer: str

class AnalyzeResponse(BaseModel):
    description: str
    objects: List[ObjectDetection]

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events"""
    global yolo_model, blip_model, blip_processor, openai_client, device
    
    try:
        logger.info("Starting up...")
        
        # Detect device
        device = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
        logger.info(f"Using device: {device}")
        
        # Load YOLOv8n model
        logger.info("Loading YOLOv8n model...")
        yolo_model = YOLO('yolov8n.pt')
        if device.type == 'cuda':
            yolo_model.to(device)
        
        # Load BLIP-2 model
        logger.info("Loading BLIP-2 model...")
        blip_processor = BlipProcessor.from_pretrained("Salesforce/blip-image-captioning-base")
        blip_model = BlipForConditionalGeneration.from_pretrained("Salesforce/blip-image-captioning-base")
        if device.type == 'cuda':
            blip_model.to(device)
        
        # Initialize OpenAI client
        openai_api_key = os.getenv("OPENAI_API_KEY")
        if openai_api_key:
            openai_client = openai.OpenAI(api_key=openai_api_key)
        else:
            logger.warning("OpenAI API key not found")
        
        logger.info("All models loaded successfully!")
        
        yield
        
    except Exception as e:
        logger.error(f"Error during startup: {e}")
        yield
    finally:
        logger.info("Shutting down...")

# Create FastAPI app
app = FastAPI(
    title="Vision Mate Backend",
    description="AI-powered navigation assistant for visually impaired users",
    version="1.0.0",
    lifespan=lifespan
)

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
            "openai": openai_client is not None
        },
        "device": str(device) if device else "unknown"
    }

@app.post("/analyze", response_model=AnalyzeResponse)
async def analyze_scene(file: UploadFile = File(...)):
    """Analyze scene: detect objects and generate description"""
    try:
        if not yolo_model or not blip_model or not blip_processor:
            raise HTTPException(status_code=500, detail="Models not loaded")
        
        logger.info(f"Analyzing image: {file.filename}")
        
        # Read and preprocess image
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))
        
        # Resize for faster processing
        max_size = 640
        if max(image.size) > max_size:
            image.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        
        # Convert for YOLO
        img_array = cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR)
        
        # Object detection with YOLO
        with torch.no_grad():
            results = yolo_model(img_array, conf=0.25, verbose=False)
        
        objects = []
        if results and len(results) > 0:
            for result in results:
                if result.boxes is not None:
                    for box in result.boxes:
                        conf = float(box.conf[0])
                        if conf > 0.3:  # Confidence threshold
                            cls_id = int(box.cls[0])
                            name = yolo_model.names[cls_id]
                            bbox = box.xyxy[0].tolist()
                            objects.append(ObjectDetection(
                                name=name,
                                confidence=conf,
                                bbox=bbox
                            ))
        
        # Scene description with BLIP-2
        with torch.no_grad():
            inputs = blip_processor(image, return_tensors="pt")
            if device.type == 'cuda':
                inputs = {k: v.to(device) for k, v in inputs.items()}
            
            out = blip_model.generate(**inputs, max_length=30, num_beams=5)
            description = blip_processor.decode(out[0], skip_special_tokens=True)
        
        logger.info(f"Analysis complete: {len(objects)} objects, description: {description[:50]}...")
        
        return AnalyzeResponse(
            description=description,
            objects=objects
        )
        
    except Exception as e:
        logger.error(f"Error analyzing scene: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/qa", response_model=AnswerResponse)
async def question_answering(request: QuestionRequest):
    """Answer questions about the scene using GPT-4o-mini"""
    try:
        if not openai_client:
            raise HTTPException(status_code=500, detail="OpenAI client not initialized")
        
        # Prepare context for GPT
        high_conf_objects = [obj for obj in request.objects if obj.confidence > 0.5]
        objects_text = ", ".join([obj.name for obj in high_conf_objects[:5]])
        
        prompt = f"""Scene: {request.scene_description[:100]}...
Objects: {objects_text}
Question: {request.question}

Answer briefly for vision assistance (1-2 sentences max):"""

        response = openai_client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You help visually impaired users. Give brief, clear answers."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=60,
            temperature=0.1,
            top_p=0.9,
        )
        
        answer = response.choices[0].message.content.strip()
        return AnswerResponse(answer=answer)
        
    except Exception as e:
        logger.error(f"Error in question answering: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    
    print(f"\n🚀 Starting Vision Mate Backend Server...")
    print(f"📍 Local access: http://127.0.0.1:{port}")
    print(f"📍 Network access: http://172.17.16.212:{port}")
    print(f"📍 Health check: http://172.17.16.212:{port}/health")
    print("🔧 Make sure your phone and laptop are on the same WiFi!")
    print("📱 Flutter app configured for: http://172.17.16.212:8000")
    print("=" * 65)
    
    uvicorn.run(app, host=host, port=port)
