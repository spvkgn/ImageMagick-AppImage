#!/bin/bash

##############################################################
# Title          : build-imagemagick7.sh                     #
# Description    : ImageMagick® 7 for Debian/Ubuntu,         #
#                  including (nearly) full delegate support. #
##############################################################

export CC="ccache gcc"
export CXX="ccache g++"
export LD="ccache ld"
export AR="ccache ar"
export CCACHE_DIR="$GITHUB_WORKSPACE/.ccache"

WORK_DIR=$GITHUB_WORKSPACE/work
BUILD_DIR=$WORK_DIR/build
mkdir -p "$BUILD_DIR"

ARCH=$(uname -m)

case $ARCH in
  x86_64)  PLATFORM=x64 ;;
  x86)     PLATFORM=x86 ;;
  aarch64) PLATFORM=arm64 ;;
  armhf)   PLATFORM=arm ;;
  *)       PLATFORM=$ARCH ;;
esac

get_sources_github() {
  REPO=$1
  wget -cO- --header="Authorization: token $GH_TOKEN" "https://api.github.com/repos/$REPO/releases/latest" |\
    jq -r '.assets[] | select(.name | match("tar.(gz|xz)")) | .browser_download_url' |\
    xargs wget -cO- | bsdtar -x
}

# libheif
build_libheif() {
  cd "$WORK_DIR" && get_sources_github 'strukturag/libheif'
  cd libheif-*/ && \
  autoreconf -fi && \
  ./configure --prefix="$BUILD_DIR" --disable-shared --disable-dependency-tracking --disable-examples && \
  make -j$(nproc) install || exit 1
}

# libfpx
build_libfpx() {
  cd "$WORK_DIR" && \
  wget -qO- https://imagemagick.org/download/delegates |\
    grep -Po "href=\"\Klibfpx-(\d+\.)+\d+.*\.tar\.(gz|xz)(?=\")" | sort -V | tail -1 |\
    xargs -I{} wget -cO- https://imagemagick.org/download/delegates/{} | bsdtar -x
  cd libfpx-*/ && \
  wget -qO- https://github.com/ImageMagick/libfpx/commit/c32b340.patch | patch -p1 -i - && \
  autoreconf -fi && \
  ./configure --prefix="$BUILD_DIR" --disable-shared --disable-dependency-tracking && \
  make -j$(nproc) install || exit 1
}

# libraqm
build_libraqm() {
  cd "$WORK_DIR" && get_sources_github 'HOST-Oman/libraqm'
  cd raqm-$VER && \
  autoreconf -fi && \
  ./configure --prefix="$BUILD_DIR" --disable-shared --disable-dependency-tracking && \
  make -j$(nproc) install || exit 1
}

# brunsli
build_brunsli() {
  cd "$WORK_DIR" && \
  git clone --depth=1 https://github.com/google/brunsli.git
  cd brunsli && \
  git submodule update --init --recursive
  cmake -Bout -H. -DCMAKE_BUILD_TYPE='Release' -DCMAKE_INSTALL_PREFIX='/usr' -DCMAKE_INSTALL_LIBDIR='lib' && \
  make -C out DESTDIR="$BUILD_DIR" -j$(nproc) install || exit 1
  cp -va out/artifacts/*.a $BUILD_DIR/usr/lib
}

build_jpeg-xl() {
  cd "$WORK_DIR" && \
  git clone https://github.com/libjxl/libjxl.git --recursive --shallow-submodules
  mkdir -p libjxl/build
  cmake -B libjxl/build -S libjxl \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DBUILD_TESTING=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_COVERAGE=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_ENABLE_FUZZERS=OFF \
    -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF \
    -DJPEGXL_WARNINGS_AS_ERRORS=OFF \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
    -DJPEGXL_FORCE_SYSTEM_GTEST=ON \
    -DJPEGXL_FORCE_SYSTEM_LCMS2=ON \
    -DJPEGXL_BUNDLE_LIBPNG=OFF \
    -Wno-dev
  cmake --build libjxl/build --target install -- -j$(nproc) || exit 1
}

# ImageMagick
build_imagemagick() {
  if [[ "$HDRI" == "OFF" ]]; then
    EXTRA_CONFIG_OPTS+=( "--disable-hdri" )
  fi
  cd "$WORK_DIR" && \
  wget -cO- https://imagemagick.org/download/ImageMagick.tar.xz | tar -xJ
  cd ImageMagick-*/ && \
  autoreconf -fi && \
  CPPFLAGS=-I$BUILD_DIR/include \
  LDFLAGS=-L$BUILD_DIR/lib \
  PKG_CONFIG_PATH=$BUILD_DIR/lib/pkgconfig \
  ./configure \
    --prefix=/usr \
    --disable-shared \
    --disable-static \
    --disable-dependency-tracking \
    --disable-docs \
    --enable-openmp \
    --enable-opencl \
    --enable-cipher \
    --with-threads \
    --without-modules \
    --with-tcmalloc \
    --with-bzlib \
    --with-x \
    --with-zlib \
    --with-zstd \
    --without-dps \
    --with-fftw \
    --with-fpx \
    --with-djvu \
    --with-fontconfig \
    --with-freetype \
    --with-quantum-depth=$QDEPTH \
    --with-raqm \
    --without-gslib \
    --with-gvc \
    --with-heic \
    --with-jbig \
    --with-jpeg \
    --with-jxl \
    --with-lcms \
    --with-openjp2 \
    --with-lqr \
    --with-lzma \
    --with-openexr \
    --with-pango \
    --with-png \
    --with-raw \
    --with-rsvg \
    --with-tiff \
    --with-webp \
    --with-wmf \
    --with-xml \
    ${EXTRA_CONFIG_OPTS[@]} \
    --with-fontpath=/usr/share/fonts/truetype \
    --with-dejavu-font-dir=/usr/share/fonts/truetype/dejavu \
    --with-gs-font-dir=/usr/share/fonts/type1/gsfonts \
    PSDelegate='/usr/bin/gs'
  sed -i -e 's/ -shared / -Wl,-O1,--as-needed\0/g' libtool
  make -j$(nproc) install DESTDIR=$GITHUB_WORKSPACE/AppDir || exit 1
}

build_jpeg-xl
build_libfpx
build_imagemagick

cd $GITHUB_WORKSPACE && \
cp -va AppDir/usr/bin/magick . && \
strip magick
VERSION=$(./magick -version | grep -Po '^Version[\D]+\K.+Q\d+(-HDRI)?' | tr -s ' ' -)
tar -cJvf magick-$VERSION-$PLATFORM.tar.xz magick

ccache --show-stats
