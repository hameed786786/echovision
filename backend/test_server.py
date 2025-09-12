"""
Quick Test Backend Server for Vision Mate
Fixed configuration with correct IP address
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

app = FastAPI(title="Vision Mate Backend - Test Server")

# Enable CORS for Flutter app
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
    return {
        "status": "healthy",
        "server": "test-backend",
        "ip": "172.17.16.212"
    }

@app.post("/analyze")
async def analyze_scene():
    """Dummy analyze endpoint for testing connection"""
    return {
        "description": "This is a test response from the backend server",
        "objects": [
            {"name": "test_object", "confidence": 0.95}
        ]
    }

@app.post("/qa")
async def question_answering():
    """Dummy Q&A endpoint for testing"""
    return {
        "answer": "Connection successful! Backend is responding."
    }

if __name__ == "__main__":
    print("🚀 Starting Vision Mate Test Backend Server...")
    print("📍 Local access: http://127.0.0.1:8000")
    print("📍 Network access: http://172.17.16.212:8000")
    print("📱 Flutter app should connect to: http://172.17.16.212:8000")
    print("🔧 Make sure your phone and laptop are on the same WiFi!")
    print("=" * 60)
    
    uvicorn.run(app, host="0.0.0.0", port=8000)
