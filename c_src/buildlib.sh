#!/bin/bash

if [ `basename $PWD` != "c_src" ]; then
    pushd c_src
fi

BASEDIR="$PWD"

WORKDIR=$BASEDIR/system
TARGETDIR=$BASEDIR/../priv

## Check for necessary tarball
if [ ! -f "db-${BDB_VERSION}.tar.gz" ]; then
    echo "Could not find db tarball. Aborting..."
    exit 1
fi

## Make sure target directory exists
mkdir -p $TARGETDIR

## Remove existing directories
rm -rf system db-${BDB_VERSION}

## Untar and build everything
tar -xzf db-${BDB_VERSION}.tar.gz && \
##(cd db-${BDB_VERSION} && patch -p0 < ../bdb-align.patch )  && \
(cd db-${BDB_VERSION}/build_unix && \
    ../dist/configure --prefix=$WORKDIR --disable-shared && make && ranlib libdb-*.a && make install) && \
    rm -rf db-${BDB_VERSION}

