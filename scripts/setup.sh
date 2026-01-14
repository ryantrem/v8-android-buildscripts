#!/bin/bash -e

GCLIENT_SYNC_ARGS="--reset --with_branch_head"
while getopts 'r:s' opt; do
  case ${opt} in
    r)
      GCLIENT_SYNC_ARGS+=" --revision ${OPTARG}"
      ;;
    s)
      GCLIENT_SYNC_ARGS+=" --no-history"
      ;;
  esac
done
shift $(expr ${OPTIND} - 1)

source $(dirname $0)/env.sh

# Install NDK
function installNDK() {
  local host_arch=$1
  pushd .
  cd "${V8_DIR}"
  wget -q https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-${host_arch}.zip
  unzip -q android-ndk-${NDK_VERSION}-${host_arch}.zip
  rm -f android-ndk-${NDK_VERSION}-${host_arch}.zip
  popd
}

if [[ ! -d "${DEPOT_TOOLS_DIR}" || ! -f "${DEPOT_TOOLS_DIR}/gclient" ]]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "${DEPOT_TOOLS_DIR}"
  pushd "${DEPOT_TOOLS_DIR}"
  git checkout 'main@{2022-07-05}'
  popd
fi

gclient config --name v8 --unmanaged "https://chromium.googlesource.com/v8/v8.git"

if [[ ${PLATFORM} = "ios" ]]; then
  # First sync may fail due to third_party/requests tag issue, allow it to fail
  gclient sync --deps=ios ${GCLIENT_SYNC_ARGS} || true

  # Fix third_party/requests tag issue - replace tag reference with commit hash
  # The v2.23.0 tag may not be fetchable from the chromium mirror, use commit hash instead
  # Commit hash determined from: https://github.com/psf/requests/releases/tag/v2.23.0
  # (c7e0fc087ceeadb8b4c84a0953a422c474093d6d is the commit that v2.23.0 tag points to)
  if [[ -f "${V8_DIR}/DEPS" ]]; then
    sed -i "" "s|refs/tags/v2.23.0|c7e0fc087ceeadb8b4c84a0953a422c474093d6d|g" "${V8_DIR}/DEPS"
  fi

  # Retry sync after DEPS fix
  gclient sync --deps=ios
  exit 0
fi

if [[ ${PLATFORM} = "android" ]]; then
  # First sync may fail due to third_party/requests tag issue, allow it to fail
  gclient sync --deps=android ${GCLIENT_SYNC_ARGS} || true

  # Fix third_party/requests tag issue - replace tag reference with commit hash
  # The v2.23.0 tag may not be fetchable from the chromium mirror, use commit hash instead
  # Commit hash determined from: https://github.com/psf/requests/releases/tag/v2.23.0
  # (c7e0fc087ceeadb8b4c84a0953a422c474093d6d is the commit that v2.23.0 tag points to)
  if [[ -f "${V8_DIR}/DEPS" ]]; then
    sed -i "s|refs/tags/v2.23.0|c7e0fc087ceeadb8b4c84a0953a422c474093d6d|g" "${V8_DIR}/DEPS"
  fi

  # Retry sync after DEPS fix
  gclient sync --deps=android

  # Patch build-deps installer for snapd not available in docker
  patch -d "${V8_DIR}" -p1 < "${PATCHES_DIR}/prebuild_no_snapd.patch"

  sudo bash -c 'v8/build/install-build-deps-android.sh'
  sudo apt-get -y install \
      ninja-build \
      libc6-dev \
      libc6-dev-i386 \
      libc6-dev-armel-cross \
      libc6-dev-armhf-cross \
      libc6-dev-arm64-cross \
      libc6-dev-armel-armhf-cross \
      libgcc-10-dev-armhf-cross \
      libstdc++-9-dev \
      lib32stdc++-9-dev \
      libx32stdc++-9-dev \
      libstdc++-10-dev-armhf-cross \
      libstdc++-9-dev-armhf-cross \
      libsfstdc++-10-dev-armhf-cross

  # Reset changes after installation
  patch -d "${V8_DIR}" -p1 -R < "${PATCHES_DIR}/prebuild_no_snapd.patch"

  # Workaround to install missing sysroot
  gclient sync

  # Workaround to install missing android_sdk tools
  gclient sync --deps=android

  installNDK "linux"
  exit 0
fi

if [[ ${PLATFORM} = "macos_android" ]]; then
  gclient sync --deps=android ${GCLIENT_SYNC_ARGS} || true
  sed -i "" "s#2c2138e811487b13020eb331482fb991fd399d4e#083aa67a0d3309ebe37eafbe7bfd96c235a019cf#g" v8/DEPS
  # Fix third_party/requests tag issue - replace tag reference with commit hash
  # Commit hash determined from: https://github.com/psf/requests/releases/tag/v2.23.0
  # (c7e0fc087ceeadb8b4c84a0953a422c474093d6d is the commit that v2.23.0 tag points to)
  sed -i "" "s|refs/tags/v2.23.0|c7e0fc087ceeadb8b4c84a0953a422c474093d6d|g" v8/DEPS
  gclient sync --deps=android

  installNDK "darwin"
  exit 0
fi
