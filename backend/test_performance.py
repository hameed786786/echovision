#!/usr/bin/env python3
"""
Performance Test Script for Optimized Vision Mate Backend
Tests scene analysis latency before and after optimizations
"""

import requests
import time
import base64
import json
from pathlib import Path

# Test configuration
BACKEND_URL = "http://localhost:8000"
TEST_IMAGE_PATH = "test_image.jpg"  # You can add a test image here

def encode_image_to_base64(image_path):
    """Convert image to base64 for API testing"""
    if not Path(image_path).exists():
        print(f"Test image not found: {image_path}")
        return None
    
    with open(image_path, "rb") as image_file:
        return base64.b64encode(image_file.read()).decode('utf-8')

def test_scene_analysis_performance():
    """Test /analyze endpoint performance"""
    print("🚀 Testing Scene Analysis Performance...")
    
    # Create a simple test payload (you can replace with actual image)
    test_payload = {
        "image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="  # 1x1 pixel PNG
    }
    
    # Measure multiple requests
    times = []
    for i in range(5):
        start_time = time.time()
        try:
            response = requests.post(f"{BACKEND_URL}/analyze", json=test_payload, timeout=30)
            end_time = time.time()
            
            if response.status_code == 200:
                latency = end_time - start_time
                times.append(latency)
                print(f"  Request {i+1}: {latency:.2f}s - ✅ Success")
            else:
                print(f"  Request {i+1}: ❌ Failed ({response.status_code})")
                
        except requests.exceptions.RequestException as e:
            print(f"  Request {i+1}: ❌ Error - {e}")
    
    if times:
        avg_time = sum(times) / len(times)
        min_time = min(times)
        max_time = max(times)
        print(f"\n📊 Performance Results:")
        print(f"  Average: {avg_time:.2f}s")
        print(f"  Fastest: {min_time:.2f}s")
        print(f"  Slowest: {max_time:.2f}s")
        
        # Performance assessment
        if avg_time < 3.0:
            print("  Status: 🎉 Excellent performance!")
        elif avg_time < 5.0:
            print("  Status: ✅ Good performance")
        elif avg_time < 8.0:
            print("  Status: ⚠️  Acceptable performance")
        else:
            print("  Status: ❌ Needs optimization")
    else:
        print("❌ No successful requests")

def test_qa_performance():
    """Test /qa endpoint performance"""
    print("\n🤖 Testing Q&A Performance...")
    
    test_payload = {
        "scene_description": "A busy street with cars and pedestrians",
        "objects": [
            {"name": "car", "confidence": 0.9},
            {"name": "person", "confidence": 0.8}
        ],
        "question": "Is it safe to cross?"
    }
    
    times = []
    for i in range(3):
        start_time = time.time()
        try:
            response = requests.post(f"{BACKEND_URL}/qa", json=test_payload, timeout=15)
            end_time = time.time()
            
            if response.status_code == 200:
                latency = end_time - start_time
                times.append(latency)
                result = response.json()
                print(f"  Request {i+1}: {latency:.2f}s - Answer: {result.get('answer', 'N/A')[:50]}...")
            else:
                print(f"  Request {i+1}: ❌ Failed ({response.status_code})")
                
        except requests.exceptions.RequestException as e:
            print(f"  Request {i+1}: ❌ Error - {e}")
    
    if times:
        avg_time = sum(times) / len(times)
        print(f"\n📊 Q&A Performance: {avg_time:.2f}s average")

def check_backend_status():
    """Check if backend is running and ready"""
    try:
        response = requests.get(f"{BACKEND_URL}/health", timeout=5)
        if response.status_code == 200:
            print("✅ Backend is running and healthy")
            return True
        else:
            print(f"❌ Backend health check failed: {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Cannot connect to backend: {e}")
        print("💡 Make sure the backend server is running on localhost:8000")
        return False

if __name__ == "__main__":
    print("🔍 Vision Mate Backend Performance Test")
    print("=" * 50)
    
    if check_backend_status():
        test_scene_analysis_performance()
        test_qa_performance()
    else:
        print("\n❌ Backend not available. Please start the backend server first.")
    
    print("\n" + "=" * 50)
    print("🏁 Performance test completed!")
