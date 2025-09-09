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
  -v "${OUT_DIR}":/packages \
  -e "ABUILD_REPODEST=/packages" \
  -e "PRIVATE_KEY=${PRIVATE_KEY}" \
  -e "KEY_NAME=${KEY_NAME}" \
  -e "TARGET_ARCH=${TARGET_ARCH}" \
  alpine:edge sh -euxo pipefail -c '
    # Install build dependencies
    apk add --no-cache alpine-sdk sudo openssl

    # Set up a non-root builder user
    adduser -D builder
    addgroup builder abuild
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
    chown -R builder:abuild /work /packages

    # Switch to the builder user to perform the build
    su builder -c "
      set -euo pipefail
      cd /work

      # Set up the abuild private key from the environment variable
      mkdir -p ~/.abuild
      printf \"%s\n\" \"\${PRIVATE_KEY}\" > ~/.abuild/\${KEY_NAME}.rsa
      chmod 600 ~/.abuild/\${KEY_NAME}.rsa
      
      # Generate the public key from the private key
      openssl rsa -in ~/.abuild/\${KEY_NAME}.rsa -pubout -out ~/.abuild/\${KEY_NAME}.rsa.pub
      chmod 644 ~/.abuild/\${KEY_NAME}.rsa.pub
      
      # Write the config file with proper path
      echo \"PACKAGER_PRIVKEY=\$HOME/.abuild/\${KEY_NAME}.rsa\" >> ~/.abuild/abuild.conf

      # Set the target architecture from the environment variable
      export CARCH=\${TARGET_ARCH}

      # Debug: verify files exist
      ls -la ~/.abuild/
      cat ~/.abuild/abuild.conf

      # Run the build
      abuild -r
    "
  '
  
echo "✅ Build complete. Artifacts now in ${OUT_DIR}"