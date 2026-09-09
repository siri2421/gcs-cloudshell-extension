# Google Cloud Shell Storage Extension via Cloud Storage FUSE (`gcsfuse`)

This repository provides an automated script and step-by-step instructions to expand the persistent storage capacity of **Google Cloud Shell** beyond its default **5 GB `$HOME` quota** by mounting a Google Cloud Storage (GCS) bucket using **Cloud Storage FUSE (`gcsfuse`)**.

---

## 📌 Background & Motivation

Google Cloud Shell runs inside a Google-managed Docker container with a fixed, non-resizable 5 GB persistent disk mounted at `$HOME`. 

While you cannot resize this disk, Cloud Shell comes with **`gcsfuse` pre-installed**. Mounting a Cloud Storage bucket directly into your Cloud Shell directory gives you **virtually unlimited object storage** directly accessible like a local POSIX filesystem.

---

## 🔑 Permissions & IAM Roles Required

To create the bucket and mount it, the identity executing the commands requires the following IAM permissions:

### 1. Same Project Setup (User owns or has editor rights in the bucket project)
* **Storage Admin** (`roles/storage.admin`) OR **Storage Object Admin** (`roles/storage.objectAdmin`) in the bucket project (`PROJECT_ID`).
* **Service Usage Consumer** (`roles/serviceusage.serviceUsageConsumer`) in the billing project.

### 2. Cross-Project Setup (Mounting from a different GCP Project or Service Account)
If Cloud Shell is active under a different project, or if a VM / external service account is mounting the bucket:
1. The bucket resides in the host project (`PROJECT_ID`).
2. The user or service account in the foreign project must be granted **Storage Object Admin** on the bucket in the host project:
   ```bash
   gcloud storage buckets add-iam-policy-binding gs://${PROJECT_ID}-cloudshell-storage \
     --member="user:USER_EMAIL@domain.com" \
     --role="roles/storage.objectAdmin" \
     --project="${PROJECT_ID}"
   ```
   Or for a Service Account:
   ```bash
   gcloud storage buckets add-iam-policy-binding gs://${PROJECT_ID}-cloudshell-storage \
     --member="serviceAccount:SA_NAME@OTHER_PROJECT.iam.gserviceaccount.com" \
     --role="roles/storage.objectAdmin" \
     --project="${PROJECT_ID}"
   ```

---

## 🚀 Quick Start (Automated Script)

Clone this repository in Cloud Shell and run `setup_gcs_storage.sh`:

```bash
git clone https://github.com/siri2421/gcs-cloudshell-extension.git
cd gcs-cloudshell-extension
chmod +x setup_gcs_storage.sh

# Run with your GCP project ID (automatically defaults bucket to <PROJECT_ID>-cloudshell-storage)
./setup_gcs_storage.sh -p "YOUR_PROJECT_ID"
```

> If you omit `-p`, the script will interactively prompt you for your GCP Project ID or use the current active gcloud project (`gcloud config get-value project`).

### Customizing Arguments:
```bash
./setup_gcs_storage.sh \
  --project "my-gcp-project" \
  --bucket "custom-bucket-name" \
  --location "us-central1" \
  --mount-dir "$HOME/bucket-storage" \
  --grant "user:external-user@example.com"
```

The script will:
1. Prompt for or parse the user's `PROJECT_ID`.
2. Default the bucket name to `<PROJECT_ID>-cloudshell-storage` (if not provided).
3. Verify `gcsfuse` is present.
4. Check if the bucket exists in the target GCP project and create it if necessary (with uniform bucket-level access enabled).
5. Apply cross-project IAM bindings if specified via `--grant`.
6. Mount the bucket to `$HOME/bucket-storage` with `--implicit-dirs`.
7. Persist the mount in `~/.customize_environment` so it re-mounts automatically on every Cloud Shell session restart.
8. Display the mount verification and capacity.

---

## 🛠️ Step-by-Step Manual Instructions

If you prefer running the commands manually:

### Step 1: Define Variables & Create Bucket
```bash
# Set your GCP Project ID
export PROJECT_ID="YOUR_PROJECT_ID"
export BUCKET_NAME="${PROJECT_ID}-cloudshell-storage"
export LOCATION="us-central1"
export MOUNT_DIR="$HOME/bucket-storage"

# Create the GCS bucket in the target project
gcloud storage buckets create "gs://$BUCKET_NAME" \
  --project="$PROJECT_ID" \
  --location="$LOCATION" \
  --uniform-bucket-level-access
```

### Step 2: Mount the Bucket
```bash
# Create local mount directory
mkdir -p "$MOUNT_DIR"

# Mount via gcsfuse
gcsfuse --implicit-dirs --billing-project="$PROJECT_ID" "$BUCKET_NAME" "$MOUNT_DIR"
```

### Step 3: Configure Persistent Auto-Mount on Session Startup
Cloud Shell executes `~/.customize_environment` every time a new container boots up. Add the mount command to persist it:

```bash
cat << 'EOF' >> ~/.customize_environment

# Auto-mount GCS Bucket
export PROJECT_ID="YOUR_PROJECT_ID"
export BUCKET_NAME="${PROJECT_ID}-cloudshell-storage"
export MOUNT_DIR="$HOME/bucket-storage"

mkdir -p "$MOUNT_DIR"
if ! mountpoint -q "$MOUNT_DIR"; then
  gcsfuse --implicit-dirs --billing-project="$PROJECT_ID" "$BUCKET_NAME" "$MOUNT_DIR" >/dev/null 2>&1 || true
fi
EOF

chmod +x ~/.customize_environment
```

---

## 📊 Checking Mount & Storage Capacity

### 1. Verify Virtual Capacity (`df -h`)
```bash
df -h "$MOUNT_DIR"
```
*Output:*
```text
Filesystem                           Size  Used Avail Use% Mounted on
siri-foundations-cloudshell-storage  1.0P     0  1.0P   0% /home/username/bucket-storage
```
> **Note:** Because Google Cloud Storage is virtually unlimited object storage, `gcsfuse` reports a synthetic size of **1.0 Petabyte (`1.0P`)** to the operating system so tools do not raise out-of-disk-space warnings.

### 2. Check Actual Bucket Usage
To see the true size of files stored inside the GCS bucket:

* **Using `gcloud storage du` (Fastest, direct API call):**
  ```bash
  gcloud storage du -s -h "gs://$BUCKET_NAME"
  ```
* **Using standard POSIX `du` on the mount folder:**
  ```bash
  du -sh "$MOUNT_DIR"
  ```

### 3. Unmounting
If you need to unmount the directory:
```bash
fusermount -u "$MOUNT_DIR"
```

---

## ⚠️ Performance & Best Practices

* **Ideal Use Cases:** Large datasets, model weights, build archives, logs, machine learning checkpoints, media, and long-term project artifacts.
* **Not Recommended For:**
  * High-frequency random I/O or SQLite databases (`.sqlite`, `.db`).
  * Active Git repositories (`.git` directories have thousands of small file lookups and locking semantics that can suffer from object storage latency). Keep your active cloned repos on `$HOME` and store artifacts/datasets on `$HOME/bucket-storage`.
