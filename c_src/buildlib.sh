#!/bin/sh

if [ `basename $PWD` != "c_src" ]; then
    pushd c_src
fi

BASEDIR="$PWD"

WORKDIR=$BASEDIR/system
TARGETDIR=$BASEDIR/../priv

DB_VER="5.1.25"

## Check for necessary tarball
if [ ! -f "db-${DB_VER}.tar.gz" ]; then
    echo "Could not find db tarball. Aborting..."
    exit 1
fi

## Make sure target directory exists
mkdir -p $TARGETDIR

## Remove existing directories
rm -rf system db-${DB_VER}

## Untar and build everything
tar -xzf db-${DB_VER}.tar.gz && \
##(cd db-${DB_VER} && patch -p0 < ../bdb-align.patch )  && \
(cd db-${DB_VER}/build_unix && \
    ../dist/configure --prefix=$WORKDIR --enable-diagnostic --enable-debug --disable-replication --disable-shared --with-pic && make && ranlib libdb-*.a && make install) && \
    rm -rf db-${DB_VER}




