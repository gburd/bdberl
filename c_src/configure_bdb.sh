#!/bin/sh -

cd $1/build_unix && \
    ../dist/configure --disable-shared --enable-static --with-pic \
        --disable-hash --disable-heap --disable-queue \
        --disable-partition --disable-replication \
        --enable-o_direct \
        --prefix=$2
