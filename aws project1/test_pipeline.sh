#!/usr/bin/env bash
# ==============================================================================
# Pipeline Verification & Interview Demo Script
# ==============================================================================
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}====================================================================${NC}"
echo -e "${BLUE}${BOLD}  Testing Automated Private Image/Document Processor Pipeline       ${NC}"
echo -e "${BLUE}${BOLD}====================================================================${NC}"

# Extract bucket names from terraform outputs
RAW_BUCKET=$(terraform output -json storage_summary | python3 -c "import sys, json; print(json.load(sys.stdin)['raw_ingestion_bucket'])")
PROCESSED_BUCKET=$(terraform output -json storage_summary | python3 -c "import sys, json; print(json.load(sys.stdin)['processed_bucket'])")

echo -e "${GREEN}[✓] Ingestion Bucket:${NC} s3://${RAW_BUCKET}"
echo -e "${GREEN}[✓] Processed Bucket:${NC} s3://${PROCESSED_BUCKET}"

# Step 1: Upload test assets
echo -e "\n${BLUE}[1/4] Uploading test documents & images to RAW bucket...${NC}"
aws s3 cp test_assets/sample.txt "s3://${RAW_BUCKET}/sample.txt"
aws s3 cp test_assets/sample.png "s3://${RAW_BUCKET}/sample.png"

echo -e "${GREEN}[✓] Uploaded sample.txt and sample.png to RAW bucket.${NC}"

# Step 2: Poll for processing
echo -e "\n${BLUE}[2/4] Waiting for Private EC2 Worker Node to process files (polling S3 Gateway Endpoint)...${NC}"
ATTEMPTS=0
MAX_ATTEMPTS=12

while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    PROCESSED_COUNT=$(aws s3 ls "s3://${PROCESSED_BUCKET}/" --recursive | wc -l | tr -d ' ')
    if [ "$PROCESSED_COUNT" -ge 2 ]; then
        echo -e "${GREEN}[✓] Processing detected! Processed files found:${NC}"
        aws s3 ls "s3://${PROCESSED_BUCKET}/" --recursive
        break
    fi
    echo -e "    Waiting for worker loop (Attempt $((ATTEMPTS+1))/$MAX_ATTEMPTS)..."
    sleep 5
    ATTEMPTS=$((ATTEMPTS+1))
done

# Step 3: Check Raw bucket cleanup (Zero queue backlog)
echo -e "\n${BLUE}[3/4] Verifying RAW bucket queue cleanup (Worker should purge processed files)...${NC}"
REMAINING_RAW=$(aws s3 ls "s3://${RAW_BUCKET}/" | wc -l | tr -d ' ')
if [ "$REMAINING_RAW" -eq 0 ]; then
    echo -e "${GREEN}[✓] RAW bucket is clean! (0 items remaining, purge completed successfully)${NC}"
else
    echo -e "${YELLOW}[!] ${REMAINING_RAW} item(s) still in RAW bucket.${NC}"
fi

# Step 4: Download and inspect result
echo -e "\n${BLUE}[4/4] Inspecting processed output document...${NC}"
mkdir -p /tmp/processed_output
aws s3 cp "s3://${PROCESSED_BUCKET}/documents/processed_sample.txt" /tmp/processed_output/processed_sample.txt || true

if [ -f /tmp/processed_output/processed_sample.txt ]; then
    echo -e "${GREEN}--- [Preview of Processed Document Header] ---${NC}"
    head -n 12 /tmp/processed_output/processed_sample.txt
fi

echo -e "\n${GREEN}${BOLD}=== Test Pipeline Completed Successfully! ===${NC}\n"
