from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import os
import json
from datetime import datetime
import boto3
import httpx
import asyncio
import re
from typing import Optional


def strip_think_tags(text: str) -> str:
    """Remove <think>...</think> tags and their content from LLM responses."""
    return re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL).strip()


app = FastAPI(title="Tube Demo API")

# CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Config
DEMO_MODE = os.getenv("DEMO_MODE", "quiz")
VLLM_ENDPOINT = os.getenv("VLLM_ENDPOINT", "http://vllm:8000")
VLLM_MODEL = os.getenv("VLLM_MODEL", "TheBloke/Mistral-7B-Instruct-v0.2-AWQ")
AWS_REGION = os.getenv("AWS_REGION", "eu-west-1")
PROJECT_NAME = os.getenv("PROJECT_NAME", "tube-demo")

# Get AWS account ID for unique bucket names
try:
    sts_client = boto3.client("sts", region_name=AWS_REGION)
    AWS_ACCOUNT = sts_client.get_caller_identity()["Account"]
except Exception:
    AWS_ACCOUNT = "default"

RESPONSES_BUCKET = f"{PROJECT_NAME}-responses-{AWS_ACCOUNT}"
QUESTIONS_BUCKET = f"{PROJECT_NAME}-questions-{AWS_ACCOUNT}"

try:
    s3_client = boto3.client("s3", region_name=AWS_REGION)
    # Ensure buckets exist
    for bucket in [RESPONSES_BUCKET, QUESTIONS_BUCKET]:
        try:
            s3_client.head_bucket(Bucket=bucket)
        except:
            try:
                s3_client.create_bucket(
                    Bucket=bucket,
                    CreateBucketConfiguration={"LocationConstraint": AWS_REGION}
                )
                # Block public access
                s3_client.put_public_access_block(
                    Bucket=bucket,
                    PublicAccessBlockConfiguration={
                        "BlockPublicAcls": True,
                        "IgnorePublicAcls": True,
                        "BlockPublicPolicy": True,
                        "RestrictPublicBuckets": True
                    }
                )
                # Enable versioning
                s3_client.put_bucket_versioning(
                    Bucket=bucket,
                    VersioningConfiguration={'Status': 'Enabled'}
                )
                print(f"Created bucket: {bucket}")
            except Exception as e:
                print(f"Could not create bucket {bucket}: {e}")
        
        # Ensure versioning is enabled on existing buckets
        try:
            s3_client.put_bucket_versioning(
                Bucket=bucket,
                VersioningConfiguration={'Status': 'Enabled'}
            )
        except Exception as e:
            print(f"Could not enable versioning on {bucket}: {e}")
except Exception:
    s3_client = None

# In-memory storage for demo (fallback if S3 unavailable)
questions_store = []
stats_cache = {
    "totalQuestions": 0,
    "queueDepth": 0,
    "currentPods": 1,
    "maxPods": 10,
    "scaling": False
}

@app.get("/api/health")
async def health():
    return {"status": "ok"}

@app.get("/api/config")
async def get_config():
    """Frontend polls this to detect mode"""
    winners_picked = False
    session_id = None
    
    if s3_client and DEMO_MODE == "survey":
        try:
            s3_client.head_object(
                Bucket=RESPONSES_BUCKET,
                Key="current/winners.json"
            )
            winners_picked = True
        except:
            pass
        
        try:
            response = s3_client.get_object(
                Bucket=RESPONSES_BUCKET,
                Key="current/session.json"
            )
            session_data = json.loads(response["Body"].read())
            session_id = session_data.get("sessionId")
        except:
            pass
    
    return {
        "mode": DEMO_MODE,
        "winnersPicked": winners_picked,
        "sessionId": session_id
    }

@app.post("/api/question/submit")
async def submit_question(data: dict):
    """Store audience question and get LLM response"""
    question = data.get("question", "").strip()
    is_test = data.get("test", False)  # Test questions don't amplify traffic
    
    if not question:
        raise HTTPException(status_code=400, detail="Question is required")
    
    question_id = f"question_{int(datetime.now().timestamp() * 1000)}"
    start_time = datetime.now()
    
    # Get answer from vLLM
    answer = "Processing your question..."
    
    # Use completions endpoint (not chat) to avoid Mistral chat template issues
    system_prompt = "You are a cheeky London Underground expert with a brilliant sense of humor. Answer questions about the Tube with wit, charm, and fascinating facts. Keep responses under 100 words. Throw in some British slang when appropriate, but stay respectful and helpful."
    prompt = f"[INST] {system_prompt}\n\n{question} [/INST]"
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            response = await client.post(
                f"{VLLM_ENDPOINT}/v1/completions",
                json={
                    "model": VLLM_MODEL,
                    "prompt": prompt,
                    "max_tokens": 75,
                    "temperature": 0.8
                }
            )
            result = response.json()
            if "choices" in result and len(result["choices"]) > 0:
                answer = strip_think_tags(result["choices"][0]["text"])
    except Exception as e:
        print(f"vLLM error: {e}")
        answer = "Blimey! The AI is having a bit of a moment. Your question is queued though! 🚇"
    
    # Calculate response time
    end_time = datetime.now()
    response_time_ms = int((end_time - start_time).total_seconds() * 1000)
    print(f"Response time: {response_time_ms}ms for question: {question[:50]}...")
    
    question_data = {
        "id": question_id,
        "timestamp": start_time.isoformat(),
        "question": question,
        "answer": answer,
        "multiplier": 1 if is_test else 50,  # Test questions don't amplify
        "response_time_ms": response_time_ms,
        "is_test": is_test
    }
    
    # Store in S3 if available (only non-test questions)
    if s3_client and not is_test:
        try:
            s3_client.put_object(
                Bucket=QUESTIONS_BUCKET,
                Key=f"current/questions/{question_id}.json",
                Body=json.dumps(question_data)
            )
        except Exception as e:
            print(f"S3 error: {e}")
    
    # Also store in memory (only non-test questions count)
    if not is_test:
        questions_store.append(question_data)
        stats_cache["totalQuestions"] = len(questions_store)
    
    return {
        "id": question_id,
        "status": "submitted",
        "answer": answer,
        "response_time_ms": response_time_ms,
        "is_test": is_test
    }

@app.get("/api/stats")
async def get_stats():
    """Get current cluster stats"""
    # In a real implementation, this would query Prometheus/KEDA
    # For now, return cached stats that can be updated by monitoring script
    return stats_cache

@app.post("/api/stats/update")
async def update_stats(data: dict):
    """Update stats (called by monitoring script)"""
    stats_cache.update(data)
    return {"status": "updated"}

@app.get("/api/questions")
async def get_questions():
    """Get all submitted questions (for load generator)"""
    if s3_client:
        try:
            response = s3_client.list_objects_v2(
                Bucket=QUESTIONS_BUCKET,
                Prefix="current/questions/"
            )
            questions = []
            if "Contents" in response:
                for obj in response["Contents"]:
                    data = s3_client.get_object(
                        Bucket=QUESTIONS_BUCKET,
                        Key=obj["Key"]
                    )
                    questions.append(json.loads(data["Body"].read()))
            return {"questions": questions}
        except Exception as e:
            print(f"S3 error: {e}")
    
    return {"questions": questions_store}

@app.post("/v1/chat/completions")
async def chat_completion(request: dict):
    """OpenAI-compatible proxy"""
    try:
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(
                f"{VLLM_ENDPOINT}/v1/chat/completions",
                json=request
            )
            result = response.json()
            # Strip think tags from all choices
            if "choices" in result:
                for choice in result["choices"]:
                    if "message" in choice and "content" in choice["message"]:
                        choice["message"]["content"] = strip_think_tags(choice["message"]["content"])
            return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/api/survey/submit")
async def submit_survey(data: dict):
    """Store survey response"""
    response_id = f"survey_{int(datetime.now().timestamp() * 1000)}"
    
    response_data = {
        "id": response_id,
        "timestamp": datetime.now().isoformat(),
        "rating": data.get("rating"),
        "company": data.get("company"),
        "feedback": data.get("feedback", "")
    }
    
    if s3_client:
        try:
            s3_client.put_object(
                Bucket=RESPONSES_BUCKET,
                Key=f"current/responses/{response_id}.json",
                Body=json.dumps(response_data)
            )
            print(f"Survey response saved to S3: {response_id}")
        except Exception as e:
            print(f"S3 error (survey will work without it): {e}")
    
    return {"id": response_id}

@app.get("/api/survey/winners")
async def get_winners():
    """Fetch winner announcement"""
    if not s3_client:
        return {"winners": []}
    
    try:
        response = s3_client.get_object(
            Bucket=RESPONSES_BUCKET,
            Key="current/winners.json"
        )
        return json.loads(response["Body"].read())
    except:
        return {"winners": []}

@app.get("/api/sessions")
async def list_sessions():
    """List all archived sessions with response counts"""
    if not s3_client:
        return {"sessions": []}
    
    try:
        # List all archived sessions
        response = s3_client.list_objects_v2(
            Bucket=RESPONSES_BUCKET,
            Prefix="archive/",
            Delimiter='/'
        )
        
        sessions = []
        if "CommonPrefixes" in response:
            for prefix in response["CommonPrefixes"]:
                session_code = prefix["Prefix"].replace("archive/", "").rstrip('/')
                
                # Count responses for this session
                resp_count = 0
                try:
                    resp_list = s3_client.list_objects_v2(
                        Bucket=RESPONSES_BUCKET,
                        Prefix=f"archive/{session_code}/responses/"
                    )
                    if "Contents" in resp_list:
                        resp_count = len(resp_list["Contents"])
                except:
                    pass
                
                # Check if winners were picked
                has_winners = False
                try:
                    s3_client.head_object(
                        Bucket=RESPONSES_BUCKET,
                        Key=f"archive/{session_code}/winners.json"
                    )
                    has_winners = True
                except:
                    pass
                
                sessions.append({
                    "code": session_code,
                    "responses": resp_count,
                    "hasWinners": has_winners
                })
        
        # Sort by session code (most recent first)
        sessions.sort(key=lambda x: x["code"], reverse=True)
        
        return {"sessions": sessions}
    except Exception as e:
        print(f"Error listing sessions: {e}")
        return {"sessions": []}
