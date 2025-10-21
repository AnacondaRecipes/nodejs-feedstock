#!/usr/bin/env bash

export CC=${CC:-clang}
export CXX=${CXX:-clang++}
export LINK="${CXX}"

export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

export CXXFLAGS="${CXXFLAGS:-} -stdlib=libc++"
export LDFLAGS="${LDFLAGS:-} -stdlib=libc++ -L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib -lc++"

# scrub -std=... flag which conflicts with builds
export CXXFLAGS=$(echo ${CXXFLAGS:-} | sed -E 's@\-std=[^ ]*@@g')

EXTRA_ARGS=

# Tame warnings from OpenSSL 3.x (deprecated) and nullability (Clang on macOS)
# Prevent treat warning as errors on different compilers
export CFLAGS="${CFLAGS:-} -Wno-deprecated-declarations"
export CXXFLAGS="${CXXFLAGS:-} -Wno-deprecated-declarations"
if [[ "$target_platform" == osx-* ]]; then
  export CFLAGS="$CFLAGS -Wno-nullability-completeness"
  export CXXFLAGS="$CXXFLAGS -Wno-nullability-completeness"
fi

if [[ "$target_platform" == linux-* ]]; then
   # need librt for clock_gettime with nodejs >= 12.12
  export LDFLAGS="$LDFLAGS -lrt"
  # fixes for cares on some Linux
  # https://github.com/nodejs/node/issues/52223
  sed -i 's/define HAVE_SYS_RANDOM_H 1/undef HAVE_SYS_RANDOM_H/g' deps/cares/config/linux/ares_config.h
  sed -i 's/define HAVE_GETRANDOM 1/undef HAVE_GETRANDOM/g' deps/cares/config/linux/ares_config.h
fi

export CC_host=$CC_FOR_BUILD
export CXX_host=$CXX_FOR_BUILD
export AR_host=$($CC_FOR_BUILD -print-prog-name=ar)
export LDFLAGS_host="$(echo $LDFLAGS | sed s@${PREFIX}@${BUILD_PREFIX}@g)"

# === macOS SDK override for modern C++20 headers ===
# The default Anaconda toolchain still points to MacOSX12.1.sdk,
# which does not include full C++20 standard library headers
# (e.g. <concepts>, <ranges>, <bit>, make_unique_for_overwrite, etc.).
#
# V8 (used by Node.js >= 20) requires these newer C++20 features,
# so building against SDK 12.1 fails with "fatal error: 'memory' file not found"
# and "expected concept name" errors.
#
# To fix this, we explicitly override CONDA_BUILD_SYSROOT / SDKROOT
# to use the newer system SDK (MacOSX13+)
#
# This keeps compatibility with the defaults toolchain while allowing
# Node.js to build successfully with modern libc++ headers.

if [[ $target_platform == osx-* ]]; then
  EXTRA_ARGS="--dest-os=mac --dest-cpu=arm64"

  SDK_NEW="$(xcrun --sdk macosx --show-sdk-path || true)"
  if [ -d "$SDK_NEW/usr/include/c++/v1" ]; then
    echo "Using SDKROOT=$SDK_NEW"
    export CONDA_BUILD_SYSROOT="$SDK_NEW"
    export SDKROOT="$SDK_NEW"
  else
    echo "WARNING: only old SDK 12.1 available — modern C++20 headers missing"
  fi

  export MACOSX_DEPLOYMENT_TARGET=13.5
  export CXXFLAGS="$(echo ${CXXFLAGS:-} | sed -E 's@-mmacosx-version-min=[^ ]*@@g') -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -std=gnu++20 -stdlib=libc++ -D_LIBCPP_DISABLE_AVAILABILITY"
  export CPPFLAGS="$(echo ${CPPFLAGS:-} | sed -E 's@-mmacosx-version-min=[^ ]*@@g') -D_DARWIN_C_SOURCE -isysroot $SDK_NEW"
  export LDFLAGS="$LDFLAGS -isysroot $SDK_NEW"
fi

./configure \
    --ninja \
    --prefix=${PREFIX} \
    --without-node-snapshot \
    --shared \
    --shared-openssl \
    --shared-zlib \
    --with-intl=system-icu \
    ${EXTRA_ARGS}

ninja -C out/Release -j"${CPU_COUNT:-2}" -v

if [[ "$target_platform" != osx-* ]]; then
  cp out/Release/lib/libnode.* out/Release/
fi
python tools/install.py install --dest-dir ${PREFIX} --prefix ''
cp out/Release/node $PREFIX/bin

if [[ "$target_platform" != osx-* ]]; then
  # Get rid of OSX specific files that confuse conda-build
  rm -rf $PREFIX/lib/node_modules/npm/node_modules/term-size/vendor/macos/term-size
fi
