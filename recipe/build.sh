#!/usr/bin/env bash

# The without snapshot comes from the error in
# https://github.com/nodejs/node/issues/4212.
./configure --prefix=$PREFIX --cross-compiling --without-snapshot
make -j${CPU_COUNT} ${VERBOSE_AT}
make install

node -v
npm version

