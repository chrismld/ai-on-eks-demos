#!/bin/bash
# Upload model weights to S3 for vLLM streaming
# This replaces the EFS-based model loading approach
# Supports resumable downloads and parallel S3 uploads
set -e

SCRIPT_DIR=$(dirname "$0")

# Source demo config if it exists
CONFIG_FILE="$SCRIPT_DIR/../.demo-config"
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Model configuration from config or defaults
# Using AWQ quantized model (~4GB) for faster loading and T4 GPU compatibility
MODEL_NAME="${MODEL_NAME:-TheBloke/Mistral-7B-Instruct-v0.2-AWQ}"
MODEL_S3_PATH="${MODEL_S3_PATH:-models/mistral-7b-awq}"

# Local cache directory (persists between runs for resume support)
CACHE_DIR="${HOME}/.cache/llm-models"

# Get region from config, environment, or default
AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-west-1}}"

# Get cluster name from config or default (used for S3 bucket discovery)
CLUSTER_NAME="${CLUSTER_NAME:-kedify-on-eks-blueprint}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

# Get bucket name from environment or discover via AWS CLI
if [ -n "$MODELS_BUCKET_NAME" ]; then
    BUCKET_NAME="$MODELS_BUCKET_NAME"
else
    log "🔍 Discovering models bucket via AWS CLI..."
    BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?contains(Name, '${CLUSTER_NAME}-models')].Name | [0]" --output text 2>/dev/null || echo "")
    
    if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" = "None" ]; then
        echo "❌ Error: Could not find models bucket"
        echo "   Either set MODELS_BUCKET_NAME environment variable, or ensure the bucket exists"
        echo "   Expected bucket name pattern: *${CLUSTER_NAME}-models*"
        exit 1
    fi
fi

log "📦 Model Upload Configuration:"
log "   Model: $MODEL_NAME"
log "   Bucket: s3://$BUCKET_NAME/$MODEL_S3_PATH/"
log "   Region: $AWS_REGION"
log "   Local cache: $CACHE_DIR"
echo ""

# Check if model already exists in S3
EXISTING_FILES=$(aws s3 ls "s3://$BUCKET_NAME/$MODEL_S3_PATH/" --region "$AWS_REGION" 2>/dev/null | wc -l || echo "0")
if [ "$EXISTING_FILES" -gt 5 ]; then
    log "✅ Model already exists in S3 ($EXISTING_FILES files found)"
    if [ -t 0 ]; then
        read -p "Re-upload model? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping upload"
            exit 0
        fi
    else
        log "Skipping upload (non-interactive mode)"
        exit 0
    fi
fi

# Create cache directory
mkdir -p "$CACHE_DIR"
MODEL_DIR="$CACHE_DIR/$(echo $MODEL_NAME | tr '/' '_')"

# Check if hf CLI is available (huggingface_hub package)
if ! command -v hf &> /dev/null; then
    log "Installing huggingface_hub via pipx..."
    if ! command -v pipx &> /dev/null; then
        echo "❌ Error: pipx is not installed"
        echo "   Install it with: brew install pipx"
        exit 1
    fi
    pipx install huggingface_hub
fi

# Check if model is already downloaded locally
if [ -d "$MODEL_DIR" ] && [ -f "$MODEL_DIR/config.json" ]; then
    log "[1/3] Model already downloaded locally, skipping download..."
    log "      Location: $MODEL_DIR"
else
    log "[1/3] Downloading model from HuggingFace..."
    log "      This may take a few minutes depending on your connection..."
    log "      (Downloads are resumable - safe to interrupt and restart)"
    
    # Download model to persistent cache
    hf download "$MODEL_NAME" \
        --local-dir "$MODEL_DIR"
fi

log "[2/3] Uploading model to S3..."
log "      Destination: s3://$BUCKET_NAME/$MODEL_S3_PATH/"
log "      (Using parallel multipart uploads)"

# Configure S3 for faster parallel uploads
# - multipart_threshold: Start multipart at 64MB (default 8MB)
# - multipart_chunksize: 64MB chunks for better throughput
# - max_concurrent_requests: 20 parallel uploads (default 10)
export AWS_MAX_CONCURRENT_REQUESTS=20

# Upload large files first (model weights) with multipart
log "      Uploading large model weight files..."
for safetensor in "$MODEL_DIR"/*.safetensors; do
    if [ -f "$safetensor" ]; then
        filename=$(basename "$safetensor")
        # Check if file already exists in S3 with same size
        local_size=$(stat -f%z "$safetensor" 2>/dev/null || stat -c%s "$safetensor" 2>/dev/null)
        s3_size=$(aws s3api head-object --bucket "$BUCKET_NAME" --key "$MODEL_S3_PATH/$filename" --region "$AWS_REGION" --query 'ContentLength' --output text 2>/dev/null || echo "0")
        
        if [ "$local_size" = "$s3_size" ]; then
            log "      ✓ $filename (already uploaded)"
        else
            log "      ↑ $filename ($(numfmt --to=iec-i --suffix=B $local_size 2>/dev/null || echo "${local_size} bytes"))..."
            aws s3 cp "$safetensor" "s3://$BUCKET_NAME/$MODEL_S3_PATH/$filename" \
                --region "$AWS_REGION" \
                --only-show-errors
        fi
    fi
done

# Upload remaining small files with sync
log "      Uploading config and metadata files..."
aws s3 sync "$MODEL_DIR" "s3://$BUCKET_NAME/$MODEL_S3_PATH/" \
    --region "$AWS_REGION" \
    --only-show-errors \
    --exclude ".cache/*" \
    --exclude "*.lock" \
    --exclude "*.safetensors"

log "[3/3] Verifying upload..."
UPLOADED_FILES=$(aws s3 ls "s3://$BUCKET_NAME/$MODEL_S3_PATH/" --region "$AWS_REGION" | wc -l)
UPLOADED_SIZE=$(aws s3 ls "s3://$BUCKET_NAME/$MODEL_S3_PATH/" --region "$AWS_REGION" --summarize --human-readable | grep "Total Size" | awk '{print $3, $4}')

log ""
log "✅ Model uploaded successfully!"
log "   Files: $UPLOADED_FILES"
log "   Size: $UPLOADED_SIZE"
log "   Path: s3://$BUCKET_NAME/$MODEL_S3_PATH/"
log ""
log "💡 Local cache kept at: $MODEL_DIR"
log "   Delete with: rm -rf $MODEL_DIR"
