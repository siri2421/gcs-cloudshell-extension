#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Shell Storage Extension Script (via Cloud Storage FUSE)
# ==============================================================================
# This script automates:
#   1. Creating a Google Cloud Storage (GCS) bucket (if it does not exist)
#   2. Configuring cross-project IAM permissions (optional)
#   3. Mounting the bucket to a local directory using gcsfuse
#   4. Persisting the mount across Cloud Shell restarts via ~/.customize_environment
# ==============================================================================

set -euo pipefail

# Configuration (can be provided via environment variables or flags)
PROJECT_ID="${PROJECT_ID:-}"
BUCKET_NAME="${BUCKET_NAME:-}"
LOCATION="${LOCATION:-us-central1}"
MOUNT_DIR="${MOUNT_DIR:-$HOME/bucket-storage}"
CROSS_PROJECT_MEMBER="${CROSS_PROJECT_MEMBER:-}" # e.g., user:someone@domain.com or serviceAccount:sa@proj.iam.gserviceaccount.com

usage() {
  cat <<EOF
Usage: $(basename "$0") -p PROJECT_ID [OPTIONS]

Required:
  -p, --project PROJECT_ID       GCP Project ID where the bucket resides

Options:
  -b, --bucket BUCKET_NAME       GCS Bucket name (default: <PROJECT_ID>-cloudshell-storage)
  -l, --location LOCATION        GCS Bucket region/location (default: $LOCATION)
  -m, --mount-dir MOUNT_DIR      Local directory to mount the bucket (default: $MOUNT_DIR)
  -g, --grant MEMBER             Grant roles/storage.objectAdmin to a cross-project member
                                 (e.g., user:email@domain.com or serviceAccount:sa@project.iam.gserviceaccount.com)
  -h, --help                     Show this help message
EOF
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--project) PROJECT_ID="$2"; shift 2 ;;
    -b|--bucket) BUCKET_NAME="$2"; shift 2 ;;
    -l|--location) LOCATION="$2"; shift 2 ;;
    -m|--mount-dir) MOUNT_DIR="$2"; shift 2 ;;
    -g|--grant) CROSS_PROJECT_MEMBER="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1"; usage ;;
  esac
done

# Prompt for PROJECT_ID if not provided via flag or environment variable
if [[ -z "$PROJECT_ID" ]]; then
  CURRENT_GCLOUD_PROJECT=$(CLOUDSDK_CORE_FORCE_IPV4=true gcloud config get-value project 2>/dev/null || true)
  if [[ -t 0 ]]; then
    read -r -p "Enter GCP Project ID [${CURRENT_GCLOUD_PROJECT}]: " INPUT_PROJECT_ID
    PROJECT_ID="${INPUT_PROJECT_ID:-$CURRENT_GCLOUD_PROJECT}"
  else
    PROJECT_ID="$CURRENT_GCLOUD_PROJECT"
  fi
fi

if [[ -z "$PROJECT_ID" ]]; then
  echo "❌ Error: PROJECT_ID is required. Provide it with -p <PROJECT_ID> or set the PROJECT_ID environment variable."
  usage
fi

# Default bucket name to <PROJECT_ID>-cloudshell-storage if not explicitly set
BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-cloudshell-storage}"

echo "=================================================================="
echo "🚀 Starting Cloud Shell Storage Extension Setup"
echo "  Project ID : $PROJECT_ID"
echo "  Bucket Name: gs://$BUCKET_NAME"
echo "  Location   : $LOCATION"
echo "  Mount Point: $MOUNT_DIR"
echo "=================================================================="

# 1. Verify gcsfuse is installed
if ! command -v gcsfuse &>/dev/null; then
  echo "❌ Error: gcsfuse is not installed. Please run inside Google Cloud Shell or install gcsfuse."
  exit 1
fi

# 2. Check / Create GCS Bucket
echo "📦 Checking GCS bucket gs://$BUCKET_NAME in project $PROJECT_ID..."
if ! CLOUDSDK_CORE_FORCE_IPV4=true gcloud storage buckets describe "gs://$BUCKET_NAME" --project="$PROJECT_ID" &>/dev/null; then
  echo "➕ Bucket does not exist. Creating gs://$BUCKET_NAME in $LOCATION..."
  CLOUDSDK_CORE_FORCE_IPV4=true gcloud storage buckets create "gs://$BUCKET_NAME" \
    --project="$PROJECT_ID" \
    --location="$LOCATION" \
    --uniform-bucket-level-access
  echo "✅ Bucket created successfully."
else
  echo "✅ Bucket gs://$BUCKET_NAME already exists."
fi

# 3. Grant Cross-Project IAM Permissions (if specified)
if [[ -n "$CROSS_PROJECT_MEMBER" ]]; then
  echo "🔐 Granting roles/storage.objectAdmin on gs://$BUCKET_NAME to $CROSS_PROJECT_MEMBER..."
  CLOUDSDK_CORE_FORCE_IPV4=true gcloud storage buckets add-iam-policy-binding "gs://$BUCKET_NAME" \
    --member="$CROSS_PROJECT_MEMBER" \
    --role="roles/storage.objectAdmin" \
    --project="$PROJECT_ID"
  echo "✅ IAM permission granted."
fi

# 4. Create Mount Directory and Mount Bucket
echo "📂 Preparing mount point at $MOUNT_DIR..."
mkdir -p "$MOUNT_DIR"

if mountpoint -q "$MOUNT_DIR"; then
  echo "ℹ️  $MOUNT_DIR is already mounted."
else
  echo "🔗 Mounting gs://$BUCKET_NAME to $MOUNT_DIR via gcsfuse..."
  gcsfuse --implicit-dirs --billing-project="$PROJECT_ID" "$BUCKET_NAME" "$MOUNT_DIR"
  echo "✅ Successfully mounted gs://$BUCKET_NAME to $MOUNT_DIR."
fi

# 5. Persist Mount in ~/.customize_environment
CUSTOMIZE_FILE="$HOME/.customize_environment"
echo "⚙️  Checking Cloud Shell persistence in $CUSTOMIZE_FILE..."

if [[ ! -f "$CUSTOMIZE_FILE" ]] || ! grep -q "$BUCKET_NAME" "$CUSTOMIZE_FILE"; then
  cat <<EOF >> "$CUSTOMIZE_FILE"

# --- Auto-mount GCS Bucket ($BUCKET_NAME) ---
export BUCKET_NAME="$BUCKET_NAME"
export MOUNT_DIR="$MOUNT_DIR"
mkdir -p "\$MOUNT_DIR"
if ! mountpoint -q "\$MOUNT_DIR"; then
  gcsfuse --implicit-dirs --billing-project="$PROJECT_ID" "\$BUCKET_NAME" "\$MOUNT_DIR" >/dev/null 2>&1 || true
fi
EOF
  chmod +x "$CUSTOMIZE_FILE"
  echo "✅ Added auto-mount configuration to $CUSTOMIZE_FILE."
else
  echo "ℹ️  Auto-mount configuration already present in $CUSTOMIZE_FILE."
fi

# 6. Verify Capacity and Usage
echo ""
echo "📊 Storage Verification:"
echo "------------------------------------------------------------------"
df -h "$MOUNT_DIR"
echo "------------------------------------------------------------------"
echo "🎉 Setup Complete! Files written to $MOUNT_DIR are stored in GCS."
