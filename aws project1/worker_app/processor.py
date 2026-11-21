#!/usr/bin/env python3
"""
Automated Private Image/Document Processor Worker
--------------------------------------------------
Continuously polls the RAW S3 bucket, processes images and documents,
uploads results to the PROCESSED S3 bucket, and purges processed raw items.

Resilience Engineering:
- First-class support for `boto3`.
- Transparent fallback to `/usr/bin/aws` CLI (preinstalled on AL2023)
  if boto3 is unavailable in an isolated private subnet.
- Zero credentials in code: authenticates via EC2 IAM Instance Profile.
- Zero inbound network ports: routes via private VPC S3 Gateway Endpoint.
"""

import os
import sys
import time
import json
import logging
import datetime
import tempfile
import gzip
import shutil
import subprocess

# Configure logging to stdout
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] (WorkerNode) %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("worker")

# Optional image processing library (Pillow)
PILLOW_AVAILABLE = False
try:
    from PIL import Image, ImageDraw
    PILLOW_AVAILABLE = True
    logger.info("PIL/Pillow is available for advanced image manipulation.")
except ImportError:
    logger.warning("PIL/Pillow not available. Worker will use native lossless compression & audit watermarking.")

# Environment configuration
RAW_BUCKET = os.environ.get("RAW_BUCKET")
PROCESSED_BUCKET = os.environ.get("PROCESSED_BUCKET")
POLL_INTERVAL_SECONDS = int(os.environ.get("POLL_INTERVAL", "5"))

if not RAW_BUCKET or not PROCESSED_BUCKET:
    logger.error("RAW_BUCKET and PROCESSED_BUCKET environment variables must be set.")
    sys.exit(1)


# S3 Backend Abstraction (boto3 with AWS CLI fallback)
class S3Backend:
    def __init__(self):
        self.use_boto3 = False
        try:
            import boto3
            self.s3_client = boto3.client("s3")
            self.use_boto3 = True
            logger.info("S3 Backend initialized using AWS boto3 SDK.")
        except ImportError:
            logger.info("boto3 not found. Falling back to native AWS CLI engine.")

    def list_objects(self, bucket: str) -> list:
        if self.use_boto3:
            resp = self.s3_client.list_objects_v2(Bucket=bucket, MaxKeys=20)
            return [item["Key"] for item in resp.get("Contents", []) if not item["Key"].endswith("/")]
        else:
            cmd = ["aws", "s3api", "list-objects-v2", "--bucket", bucket, "--query", "Contents[].Key", "--output", "json"]
            res = subprocess.run(cmd, capture_output=True, text=True)
            if res.returncode == 0 and res.stdout.strip() and res.stdout.strip() != "null":
                try:
                    keys = json.loads(res.stdout)
                    return [k for k in keys if k and not k.endswith("/")]
                except Exception:
                    return []
            return []

    def download_file(self, bucket: str, key: str, local_path: str):
        if self.use_boto3:
            self.s3_client.download_file(bucket, key, local_path)
        else:
            s3_uri = f"s3://{bucket}/{key}"
            subprocess.run(["aws", "s3", "cp", s3_uri, local_path], check=True, capture_output=True)

    def upload_file(self, local_path: str, bucket: str, key: str, metadata: dict):
        if self.use_boto3:
            self.s3_client.upload_file(local_path, bucket, key, ExtraArgs={"Metadata": metadata})
        else:
            s3_uri = f"s3://{bucket}/{key}"
            meta_str = ",".join(f"{k}={v}" for k, v in metadata.items())
            cmd = ["aws", "s3", "cp", local_path, s3_uri, "--metadata", meta_str]
            subprocess.run(cmd, check=True, capture_output=True)

    def delete_object(self, bucket: str, key: str):
        if self.use_boto3:
            self.s3_client.delete_object(Bucket=bucket, Key=key)
        else:
            s3_uri = f"s3://{bucket}/{key}"
            subprocess.run(["aws", "s3", "rm", s3_uri], check=True, capture_output=True)


s3 = S3Backend()


def process_image(input_path: str, output_path: str, filename: str) -> dict:
    """Process image: watermark, resize, optimize quality."""
    metadata = {
        "processed-by": "ec2-private-worker",
        "processor-type": "image",
        "processed-at": datetime.datetime.utcnow().isoformat()
    }

    if PILLOW_AVAILABLE:
        try:
            with Image.open(input_path) as img:
                if img.mode in ("RGBA", "P") and output_path.lower().endswith((".jpg", ".jpeg")):
                    img = img.convert("RGB")

                max_dim = 1920
                if max(img.size) > max_dim:
                    img.thumbnail((max_dim, max_dim))

                draw = ImageDraw.Draw(img)
                watermark_text = f"PROCESSED [AWS EC2 PRIVATE WORKER] - {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}"
                width, height = img.size
                banner_height = max(28, int(height * 0.05))
                draw.rectangle([(0, height - banner_height), (width, height)], fill="black")
                draw.text((15, height - banner_height + 5), watermark_text, fill="white")

                ext = os.path.splitext(output_path)[1].lower()
                if ext in [".jpg", ".jpeg"]:
                    img.save(output_path, "JPEG", optimize=True, quality=80)
                elif ext == ".png":
                    img.save(output_path, "PNG", optimize=True)
                else:
                    img.save(output_path)

                metadata["watermarked"] = "true"
                metadata["original_size"] = str(img.size)
                return metadata
        except Exception as e:
            logger.warning(f"PIL error ({e}), falling back to gzip compressor.")

    # Fallback lossless compression
    with open(input_path, "rb") as f_in:
        with gzip.open(output_path, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
    metadata["fallback_compression"] = "gzip"
    return metadata


def process_document(input_path: str, output_path: str, filename: str) -> dict:
    """Process text or document: add enterprise audit header and metadata."""
    timestamp = datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
    header = (
        "======================================================================\n"
        "           PROCESSED BY SECURE AWS PRIVATE EC2 WORKER NODE             \n"
        f"  Timestamp: {timestamp}                                              \n"
        f"  Original Document: {filename}                                        \n"
        "  Isolation: Private Subnet (0 Inbound Rules, Gateway S3 Endpoint)     \n"
        "======================================================================\n\n"
    )

    try:
        with open(input_path, "r", encoding="utf-8", errors="ignore") as f_in:
            body = f_in.read()

        with open(output_path, "w", encoding="utf-8") as f_out:
            f_out.write(header)
            f_out.write(body)
            f_out.write(f"\n\n--- [END OF PROCESSED DOCUMENT - {timestamp}] ---\n")

        return {
            "processed-by": "ec2-private-worker",
            "processor-type": "document",
            "watermarked": "true",
            "processed-at": datetime.datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Error processing document {filename}: {e}")
        shutil.copy2(input_path, output_path)
        return {"processed-by": "ec2-private-worker", "error": str(e)}


def process_file(key: str):
    """Download file from raw bucket, process it, upload to processed bucket, delete from raw."""
    filename = os.path.basename(key)
    logger.info(f"==> Detected new raw file: '{key}' in bucket '{RAW_BUCKET}'")

    with tempfile.TemporaryDirectory() as tmpdir:
        input_file = os.path.join(tmpdir, f"raw_{filename}")
        output_file = os.path.join(tmpdir, f"processed_{filename}")

        # 1. Download
        try:
            logger.info(f"Downloading s3://{RAW_BUCKET}/{key} ...")
            s3.download_file(RAW_BUCKET, key, input_file)
        except Exception as e:
            logger.error(f"Failed to download '{key}': {e}")
            return

        # 2. Process based on extension
        ext = os.path.splitext(filename)[1].lower()
        if ext in [".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif"]:
            metadata = process_image(input_file, output_file, filename)
            output_key = f"images/processed_{filename}"
        elif ext in [".txt", ".log", ".json", ".csv", ".md"]:
            metadata = process_document(input_file, output_file, filename)
            output_key = f"documents/processed_{filename}"
        else:
            output_file = output_file + ".gz"
            output_key = f"archives/processed_{filename}.gz"
            with open(input_file, "rb") as f_in:
                with gzip.open(output_file, "wb") as f_out:
                    shutil.copyfileobj(f_in, f_out)
            metadata = {
                "processed-by": "ec2-private-worker",
                "compression": "gzip",
                "processed-at": datetime.datetime.utcnow().isoformat()
            }

        # 3. Upload
        try:
            logger.info(f"Uploading result to s3://{PROCESSED_BUCKET}/{output_key} ...")
            s3.upload_file(output_file, PROCESSED_BUCKET, output_key, metadata)
            logger.info(f"Successfully uploaded: s3://{PROCESSED_BUCKET}/{output_key}")
        except Exception as e:
            logger.error(f"Failed to upload '{output_key}': {e}")
            return

        # 4. Delete original from RAW bucket
        try:
            logger.info(f"Purging original s3://{RAW_BUCKET}/{key} ...")
            s3.delete_object(RAW_BUCKET, key)
            logger.info(f"Successfully purged raw object: '{key}'")
        except Exception as e:
            logger.error(f"Failed to delete '{key}': {e}")


def main_loop():
    logger.info("=================================================================")
    logger.info("  AWS Private EC2 Worker Node: Automated Processor Started        ")
    logger.info(f"  Watching Raw Bucket:       {RAW_BUCKET}")
    logger.info(f"  Target Processed Bucket:   {PROCESSED_BUCKET}")
    logger.info(f"  Poll Interval:             {POLL_INTERVAL_SECONDS} seconds")
    logger.info("=================================================================")

    while True:
        try:
            keys = s3.list_objects(RAW_BUCKET)
            if keys:
                logger.info(f"Found {len(keys)} object(s) awaiting processing: {keys}")
                for key in keys:
                    process_file(key)
        except Exception as e:
            logger.error(f"Worker loop error: {e}")

        time.sleep(POLL_INTERVAL_SECONDS)


if __name__ == "__main__":
    main_loop()
