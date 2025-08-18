"""
RefaceKit Ops API
FastAPI application for CSV ingestion and VICIdial export management
"""

import os
import re
import json
import logging
from datetime import datetime
from typing import Optional
from io import StringIO

import redis
import pandas as pd
from fastapi import FastAPI, UploadFile, File, HTTPException, status
from pydantic import BaseModel
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO').upper()))
logger = logging.getLogger(__name__)

# Redis configuration
REDIS_HOST = os.getenv('REDIS_HOST', 'redis')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
REDIS_DB = int(os.getenv('REDIS_DB', 0))

# Initialize FastAPI app
app = FastAPI(
    title="RefaceKit Ops API",
    description="CSV ingestion and VICIdial export management API",
    version="1.0.0"
)

# Initialize Redis connection
try:
    redis_client = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        db=REDIS_DB,
        decode_responses=True,
        socket_connect_timeout=5,
        socket_timeout=5
    )
    # Test connection
    redis_client.ping()
    logger.info(f"Connected to Redis at {REDIS_HOST}:{REDIS_PORT}")
except Exception as e:
    logger.error(f"Failed to connect to Redis: {e}")
    redis_client = None

# Pydantic models
class HealthResponse(BaseModel):
    api: str
    redis: str
    timestamp: str

class IngestResponse(BaseModel):
    status: str
    message: str
    rows_processed: int
    job_id: str

def normalize_phone_number(phone: str) -> Optional[str]:
    """Normalize phone number by removing non-digits and validating length"""
    if not phone or pd.isna(phone):
        return None
    
    # Remove all non-digit characters
    digits_only = re.sub(r'\D', '', str(phone))
    
    # Must have at least 10 digits
    if len(digits_only) < 10:
        return None
    
    # Take last 10 digits if longer than 10
    if len(digits_only) > 10:
        digits_only = digits_only[-10:]
    
    return digits_only

def normalize_csv_headers(df: pd.DataFrame) -> pd.DataFrame:
    """Normalize CSV headers to common format"""
    # Create header mapping for common variations
    header_mapping = {
        'firstname': 'first_name', 'fname': 'first_name', 'first': 'first_name',
        'lastname': 'last_name', 'lname': 'last_name', 'last': 'last_name',
        'phone': 'phone_number', 'telephone': 'phone_number', 'mobile': 'phone_number',
        'address': 'address1', 'street': 'address1', 'addr1': 'address1',
        'zip': 'postal_code', 'zipcode': 'postal_code', 'zip_code': 'postal_code',
    }
    
    # Normalize column names to lowercase and map
    df.columns = df.columns.str.lower().str.strip()
    df = df.rename(columns=header_mapping)
    
    return df

@app.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    redis_status = "ok"
    
    if redis_client:
        try:
            redis_client.ping()
        except Exception as e:
            logger.error(f"Redis health check failed: {e}")
            redis_status = "dead"
    else:
        redis_status = "dead"
    
    return HealthResponse(
        api="ok",
        redis=redis_status,
        timestamp=datetime.now().isoformat()
    )

@app.post("/ingest/csv", response_model=IngestResponse)
async def ingest_csv(file: UploadFile = File(...)):
    """Ingest CSV file, normalize data, and queue for processing"""
    if not redis_client:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Redis connection not available"
        )
    
    # Validate file type
    if not file.filename.lower().endswith('.csv'):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="File must be a CSV"
        )
    
    try:
        # Read CSV content
        content = await file.read()
        csv_string = content.decode('utf-8')
        
        # Parse CSV
        df = pd.read_csv(StringIO(csv_string))
        
        if df.empty:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="CSV file is empty"
            )
        
        logger.info(f"Loaded CSV with {len(df)} rows and columns: {list(df.columns)}")
        
        # Normalize headers
        df = normalize_csv_headers(df)
        
        # Normalize phone numbers if phone_number column exists
        if 'phone_number' in df.columns:
            df['phone_number_normalized'] = df['phone_number'].apply(normalize_phone_number)
            # Remove rows with invalid phone numbers
            initial_count = len(df)
            df = df.dropna(subset=['phone_number_normalized'])
            removed_count = initial_count - len(df)
            if removed_count > 0:
                logger.info(f"Removed {removed_count} rows with invalid phone numbers")
        
        # Remove duplicates based on phone number if available
        if 'phone_number_normalized' in df.columns:
            initial_count = len(df)
            df = df.drop_duplicates(subset=['phone_number_normalized'])
            deduped_count = initial_count - len(df)
            if deduped_count > 0:
                logger.info(f"Removed {deduped_count} duplicate phone numbers")
        
        if df.empty:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No valid records found after processing"
            )
        
        # Convert back to CSV string
        processed_csv = df.to_csv(index=False)
        
        # Generate job ID
        job_id = f"csv_job_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        # Queue job for worker
        job_data = {
            'job_id': job_id,
            'filename': file.filename,
            'csv_data': processed_csv,
            'timestamp': datetime.now().isoformat(),
            'rows': len(df)
        }
        
        # Push to Redis queue
        redis_client.lpush('lead_jobs', json.dumps(job_data))
        
        logger.info(f"Queued job {job_id} with {len(df)} rows")
        
        return IngestResponse(
            status="success",
            message=f"CSV processed and queued successfully",
            rows_processed=len(df),
            job_id=job_id
        )
        
    except Exception as e:
        logger.error(f"Error processing CSV: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error processing CSV"
        )

@app.get("/")
async def root():
    """Root endpoint"""
    return {
        "message": "RefaceKit Ops API",
        "version": "1.0.0",
        "endpoints": {
            "health": "/health",
            "ingest_csv": "/ingest/csv"
        }
    }

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host=os.getenv('API_HOST', '0.0.0.0'),
        port=int(os.getenv('API_PORT', 8000))
    )
