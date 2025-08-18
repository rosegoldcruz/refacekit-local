"""
RefaceKit Ops Worker
Background worker for processing CSV data and converting to VICIdial format
"""

import os
import json
import time
import logging
from datetime import datetime
from io import StringIO

import redis
import pandas as pd
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(
    level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO').upper()),
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
REDIS_HOST = os.getenv('REDIS_HOST', 'redis')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
REDIS_DB = int(os.getenv('REDIS_DB', 0))
EXPORT_DIR = os.getenv('EXPORT_DIR', '/data/exports')

# Ensure export directory exists
os.makedirs(EXPORT_DIR, exist_ok=True)

class VICIdialWorker:
    def __init__(self):
        """Initialize the worker with Redis connection"""
        self.redis_client = None
        self.connect_redis()
    
    def connect_redis(self):
        """Connect to Redis with retry logic"""
        max_retries = 5
        retry_delay = 5
        
        for attempt in range(max_retries):
            try:
                self.redis_client = redis.Redis(
                    host=REDIS_HOST,
                    port=REDIS_PORT,
                    db=REDIS_DB,
                    decode_responses=True,
                    socket_connect_timeout=10,
                    socket_timeout=10
                )
                # Test connection
                self.redis_client.ping()
                logger.info(f"Connected to Redis at {REDIS_HOST}:{REDIS_PORT}")
                return
            except Exception as e:
                logger.error(f"Redis connection attempt {attempt + 1} failed: {e}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                else:
                    raise Exception("Failed to connect to Redis after all retries")
    
    def map_to_vicidial_format(self, df: pd.DataFrame, list_id: int = 999) -> pd.DataFrame:
        """Convert DataFrame to VICIdial format with required columns"""
        # Create new DataFrame with VICIdial structure
        vici_df = pd.DataFrame()
        
        # Map list_id
        vici_df['list_id'] = list_id
        
        # Map phone number (use normalized if available)
        if 'phone_number_normalized' in df.columns:
            vici_df['phone_number'] = df['phone_number_normalized']
        elif 'phone_number' in df.columns:
            vici_df['phone_number'] = df['phone_number']
        else:
            # Try common phone column variations
            phone_cols = ['phone', 'telephone', 'mobile', 'cell']
            for col in phone_cols:
                if col in df.columns:
                    vici_df['phone_number'] = df[col]
                    break
            else:
                vici_df['phone_number'] = ''
        
        # Map names
        vici_df['first_name'] = df.get('first_name', '').fillna('')
        vici_df['last_name'] = df.get('last_name', '').fillna('')
        
        # Map address fields
        vici_df['address1'] = df.get('address1', '').fillna('')
        vici_df['city'] = df.get('city', '').fillna('')
        vici_df['state'] = df.get('state', '').fillna('')
        vici_df['postal_code'] = df.get('postal_code', '').fillna('')
        
        # Clean up data
        for col in vici_df.columns:
            if col != 'list_id':
                vici_df[col] = vici_df[col].astype(str).str.strip()
        
        # Remove rows with empty phone numbers
        vici_df = vici_df[vici_df['phone_number'].str.len() > 0]
        
        logger.info(f"Converted {len(df)} input rows to {len(vici_df)} VICIdial rows")
        
        return vici_df
    
    def process_csv_job(self, job_data):
        """Process a CSV job and convert to VICIdial format"""
        try:
            job_id = job_data.get('job_id', 'unknown')
            csv_data = job_data.get('csv_data', '')
            filename = job_data.get('filename', 'unknown.csv')
            
            logger.info(f"Processing job {job_id} from file {filename}")
            
            # Parse CSV data
            df = pd.read_csv(StringIO(csv_data))
            
            if df.empty:
                logger.warning(f"Job {job_id}: CSV data is empty")
                return False
            
            # Convert to VICIdial format
            vici_df = self.map_to_vicidial_format(df)
            
            if vici_df.empty:
                logger.warning(f"Job {job_id}: No valid records after VICIdial conversion")
                return False
            
            # Generate output filename
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            output_filename = f"vici_export_{timestamp}.csv"
            output_path = os.path.join(EXPORT_DIR, output_filename)
            
            # Write VICIdial CSV
            vici_df.to_csv(output_path, index=False)
            
            logger.info(f"Job {job_id}: Exported {len(vici_df)} records to {output_filename}")
            
            return True
            
        except Exception as e:
            logger.error(f"Error processing CSV job: {e}")
            return False
    
    def run(self):
        """Main worker loop"""
        logger.info("Starting VICIdial worker...")
        
        while True:
            try:
                # Check for CSV processing jobs
                job_data = self.redis_client.brpop('lead_jobs', timeout=5)
                
                if job_data:
                    queue_name, job_json = job_data
                    job = json.loads(job_json)
                    
                    logger.info(f"Received job from {queue_name}: {job.get('job_id', 'unknown')}")
                    
                    success = self.process_csv_job(job)
                    
                    if success:
                        logger.info(f"Successfully processed job {job.get('job_id', 'unknown')}")
                    else:
                        logger.error(f"Failed to process job {job.get('job_id', 'unknown')}")
                
            except redis.ConnectionError as e:
                logger.error(f"Redis connection error: {e}")
                logger.info("Attempting to reconnect to Redis...")
                try:
                    self.connect_redis()
                except Exception as reconnect_error:
                    logger.error(f"Failed to reconnect: {reconnect_error}")
                    time.sleep(10)
                    
            except KeyboardInterrupt:
                logger.info("Worker shutdown requested")
                break
                
            except Exception as e:
                logger.error(f"Unexpected error in worker loop: {e}")
                time.sleep(5)
        
        logger.info("Worker stopped")

if __name__ == "__main__":
    worker = VICIdialWorker()
    worker.run()
