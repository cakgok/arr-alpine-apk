#!/usr/bin/env bash
set -euo pipefail

# 1. Check for required variables
for var in APP_NAME TARGET_ARCH KEY_NAME PRIVATE_KEY; do
  [[ -z "${!var:-}" ]] && { echo "::error::$var is not set"; exit 1; }
done

SRC_DIR="${PWD}/${APP_NAME}"
OUT_DIR="${SRC_DIR}/out"
mkdir -p "${OUT_DIR}"

echo "🔧 Building ${APP_NAME} for ${TARGET_ARCH}"
echo "📦 Output directory: ${OUT_DIR}"

# 2. Run the build inside a Docker container
docker run --rm \
  -v "${SRC_DIR}":/work \
  -v "${OUT_DIR}":/out \
  -e "PRIVATE_KEY=${PRIVATE_KEY}" \
  -e "KEY_NAME=${KEY_NAME}" \
  -e "TARGET_ARCH=${TARGET_ARCH}" \
  alpine:edge sh -euxo pipefail -c '
    apk update
    apk add --no-cache alpine-sdk sudo openssl

    adduser -D builder
    addgroup builder abuild
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
    chown -R builder:abuild /work /out

    su builder -c "
      set -euo pipefail
      cd /work

      mkdir -p ~/.abuild
      printf \"%s\n\" \"\${PRIVATE_KEY}\" > ~/.abuild/\${KEY_NAME}.rsa
      chmod 600 ~/.abuild/\${KEY_NAME}.rsa
      
      openssl rsa -in ~/.abuild/\${KEY_NAME}.rsa -pubout -out ~/.abuild/\${KEY_NAME}.rsa.pub
      chmod 644 ~/.abuild/\${KEY_NAME}.rsa.pub
      
      sudo cp ~/.abuild/\${KEY_NAME}.rsa.pub /etc/apk/keys/
      echo \"PACKAGER_PRIVKEY=\$HOME/.abuild/\${KEY_NAME}.rsa\" >> ~/.abuild/abuild.conf

      export CARCH=\${TARGET_ARCH}

      ls -la ~/.abuild/
      cat ~/.abuild/abuild.conf

      # Run the build
      abuild -r
      
      # Copy the built packages to the output directory
      echo \"📦 Copying packages to output directory...\"
      find ~/packages -name \"*.apk\" -type f -exec cp {} /out/ \; || echo \"No packages found to copy\"
      
      # List what we copied
      echo \"📋 Files in output directory:\"
      ls -la /out/ || echo \"Output directory is empty\"
    "
  '
  
echo "✅ Build complete. Artifacts now in ${OUT_DIR}"