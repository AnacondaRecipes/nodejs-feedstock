#!/usr/bin/env bash

# export CC=${CC:-clang}
# export CXX=${CXX:-clang++}
# export LINK="${CXX}"

# export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig:$PREFIX/share/pkgconfig:${PKG_CONFIG_PATH:-}"
# export PKG_CONFIG="${PKG_CONFIG:-pkg-config}"

# scrub -std=... flag which conflicts with builds
export CXXFLAGS=$(echo ${CXXFLAGS:-} | sed -E 's@\-std=[^ ]*@@g')

# if [[ "$target_platform" == linux-* ]]; then
#   # подчистить любые следы macOS-специфичных флагов, вдруг пришли из внешней среды
#   export CXXFLAGS="$(echo "${CXXFLAGS:-}" | sed -E 's@-stdlib=libc\+\+@@g')"
#   export LDFLAGS="$(echo "${LDFLAGS:-}" | sed -E 's@-stdlib=libc\+\+@@g' \
#                                        | sed -E 's@-lc\+\+abi@@g' \
#                                        | sed -E 's@-lc\+\+@@g')"
#   export LDFLAGS="${LDFLAGS} -L${PREFIX}/lib -Wl,-rpath,${PREFIX}/lib -lrt"
# fi

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
  # export LDFLAGS="$LDFLAGS -lrt"
  # fixes for cares on some Linux
  # https://github.com/nodejs/node/issues/52223
  sed -i 's/define HAVE_SYS_RANDOM_H 1/undef HAVE_SYS_RANDOM_H/g' deps/cares/config/linux/ares_config.h
  sed -i 's/define HAVE_GETRANDOM 1/undef HAVE_GETRANDOM/g' deps/cares/config/linux/ares_config.h
fi

# if [[ "$target_platform" == linux-* ]]; then
#   # export CC=clang
#   # export CXX=clang++
#   export CFLAGS="${CFLAGS} -std=gnu17"
#   export CXXFLAGS="$(echo "${CXXFLAGS}" | sed -E 's@\-stdlib=libc\+\+@@g') -std=gnu++20"
#   export LDFLAGS="$(echo "${LDFLAGS}" | sed -E 's@\-stdlib=libc\+\+@@g')"

#   # EXTRA_ARGS+="--dest-os=linux --dest-cpu=arm64"
# fi

if [[ $target_platform == linux-* ]]; then
  export CC=clang
  export CXX=clang++
  export LD=ld.lld
  export AR=llvm-ar
  export RANLIB=llvm-ranlib
  export NM=llvm-nm
  export STRIP=llvm-strip

  if [[ -n "${CONDA_BUILD_SYSROOT:-}" ]]; then
    export CFLAGS="${CFLAGS} --sysroot=${CONDA_BUILD_SYSROOT}"
    export CXXFLAGS="${CXXFLAGS} --sysroot=${CONDA_BUILD_SYSROOT}"
    export LDFLAGS="${LDFLAGS} --sysroot=${CONDA_BUILD_SYSROOT}"
  fi

  export CXXFLAGS="$(echo ${CXXFLAGS:-} | sed -E 's@-std=[^ ]*@@g;s@-stdlib=[^ ]*@@g') -std=gnu++20 -stdlib=libc++ -fPIC"
  export CFLAGS="${CFLAGS} -fPIC"
  export LDFLAGS="$(echo ${LDFLAGS:-} | sed -E 's@-stdlib=[^ ]*@@g') -stdlib=libc++ -fuse-ld=lld -Wl,-rpath,${PREFIX}/lib"

  export CXXFLAGS="$(echo ${CXXFLAGS} | sed -E 's@-D_GLIBCXX_USE_CXX11_ABI=[01]@@g')"
  export CFLAGS="$(echo ${CFLAGS} | sed -E 's@-D_GLIBCXX_USE_CXX11_ABI=[01]@@g')"
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

ninja -C out/Release -j"${CPU_COUNT:-2}"

if [[ "$target_platform" != osx-* ]]; then
  cp out/Release/lib/libnode.* out/Release/
fi
python tools/install.py install --dest-dir ${PREFIX} --prefix ''
cp out/Release/node $PREFIX/bin

if [[ "$target_platform" != osx-* ]]; then
  # Get rid of OSX specific files that confuse conda-build
  rm -rf $PREFIX/lib/node_modules/npm/node_modules/term-size/vendor/macos/term-size
fi
