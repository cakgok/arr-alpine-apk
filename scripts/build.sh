#!/usr/bin/env bash
set -euo pipefail

### 0. Sanity-check env --------------------------------------------------------
for var in APP_NAME TARGET_ARCH KEY_NAME PRIVATE_KEY; do
  [[ -z "${!var:-}" ]] && { echo "::error::$var is not set"; exit 1; }
done

SRC_DIR="${PWD}/${APP_NAME}"
OUT_DIR="${SRC_DIR}/out"
mkdir -p "${OUT_DIR}"

echo "🔧 Building ${APP_NAME} for ${TARGET_ARCH}"
echo "📦 Output directory: ${OUT_DIR}"

### 1. Launch a disposable Alpine builder container ---------------------------
docker run --rm \
  -v "${SRC_DIR}":/work \
  -v "${OUT_DIR}":/packages \
  -e "ABUILD_REPODEST=/packages" \         # where abuild drops finished APKs
  alpine:edge sh -euxo pipefail -c '

    ##### a) Bootstrap build environment #####################################
    apk add --no-cache alpine-sdk sudo

    # Non-root builder user (required by abuild)
    adduser -D builder
    addgroup builder abuild
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
    chown -R builder:abuild /work /packages

    ##### b) Build as the builder user #######################################
    su builder -c "
      set -euo pipefail
      cd /work

      # 1. Install signing key ----------------------------------------------
      mkdir -p ~/.abuild
      printf \"%s\n\" \"$PRIVATE_KEY\" > ~/.abuild/${KEY_NAME}.rsa
      chmod 600 ~/.abuild/${KEY_NAME}.rsa
      echo 'PACKAGER_PRIVKEY=\"~/.abuild/'${KEY_NAME}'.rsa\"' >> ~/.abuild/abuild.conf

      # 2. Select architecture & build --------------------------------------
      export CARCH=${TARGET_ARCH}
      abuild -r            # -r = clean, checksum, build, sign

      # APKs appear in \$ABUILD_REPODEST/<repo>/\$CARCH
    "
  '

echo "✅ Build complete. Artifacts now in ${OUT_DIR}"
