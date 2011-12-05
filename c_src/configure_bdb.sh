#!/bin/sh -

cd $1/build_unix && \
    ../dist/configure --disable-shared --enable-static --with-pic \
        --disable-heap --disable-queue --disable-replication \
        --enable-o_direct --enable-o_direct \
        --enable-debug --enable-diagnostics \
        --enable-dtrace \
        --prefix=$2
