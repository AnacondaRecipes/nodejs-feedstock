#!/usr/bin/env bash

# scrub -std=... flag which conflicts with builds
export CXXFLAGS=$(echo ${CXXFLAGS:-} | sed -E 's@\-std=[^ ]*@@g')

if [ "$(uname)" = "Darwin" ]; then
    # unset macosx-version-min hardcoded in clang CPPFLAGS
    export CPPFLAGS="$(echo ${CPPFLAGS:-} | sed -E 's@\-mmacosx\-version\-min=[^ ]*@@g')"
    export CPPFLAGS="${CPPFLAGS} -D_DARWIN_C_SOURCE"
    echo "CPPFLAGS=$CPPFLAGS"
else
    # need librt for clock_gettime with nodejs >= 12.12
    export LDFLAGS="$LDFLAGS -lrt"
    echo "LDFLAGS=$LDFLAGS"

    # https://github.com/nodejs/node/issues/52223
    sed -i 's/define HAVE_SYS_RANDOM_H 1/undef HAVE_SYS_RANDOM_H/g' deps/cares/config/linux/ares_config.h
    sed -i 's/define HAVE_GETRANDOM 1/undef HAVE_GETRANDOM/g' deps/cares/config/linux/ares_config.h
fi

EXTRA_ARGS=

if [[ $target_platform == osx-arm64 ]]; then
  EXTRA_ARGS="--dest-os=mac --dest-cpu=arm64"
fi

echo "sysroot: ${CONDA_BUILD_SYSROOT:-unset}"

export CC_host=$CC_FOR_BUILD
export CXX_host=$CXX_FOR_BUILD
export AR_host=$($CC_FOR_BUILD -print-prog-name=ar)
export LDFLAGS_host="$(echo $LDFLAGS | sed s@${PREFIX}@${BUILD_PREFIX}@g)"

"${SRC_DIR}"/configure \
    ${EXTRA_ARGS} \
    --ninja \
    --prefix=${PREFIX} \
    --shared \
    --shared-libuv \
    --shared-openssl \
    --shared-zlib \
    --with-intl=system-icu

if [ "$(uname -m)" = "ppc64le" ]; then
    for ninja_build in `find out/Release/obj.host/ -name '*.ninja'`; do
      sed -ie 's/-mminimal-toc//g' ${ninja_build}
    done

    # Decrease parallelism a bit as we will otherwise get out-of-memory problems
    echo "Using $(grep -c ^processor /proc/cpuinfo) CPUs"
    CPU_COUNT=$(grep -c ^processor /proc/cpuinfo)
    CPU_COUNT=$((CPU_COUNT / 4))
    ninja -C out/Release -j${CPU_COUNT}
else
    ninja -C out/Release -j${CPU_COUNT}
fi

if [[ "${target_platform}" != osx-* ]]; then
  cp out/Release/lib/libnode.* out/Release/
fi
$PYTHON tools/install.py install --dest-dir ${PREFIX} --prefix ''
cp out/Release/node $PREFIX/bin

node -v
npm version

if [ "$(uname)" != "Darwin" ]; then
  # Get rid of OSX specific files that confuse conda-build
  rm -rf $PREFIX/lib/node_modules/npm/node_modules/term-size/vendor/macos/term-size
fi
