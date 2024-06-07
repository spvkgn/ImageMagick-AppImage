#!/bin/bash

##############################################################
# Title          : build-imagemagick7.sh                     #
# Description    : ImageMagick® 7 for Debian/Ubuntu,         #
#                  including (nearly) full delegate support. #
##############################################################

export CC="ccache gcc"
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

# ImageMagick
build_imagemagick() {
  cd "$WORK_DIR" && \
  wget -cO- https://imagemagick.org/download/ImageMagick.tar.gz | tar -xz
  cd ImageMagick-*/ && \
  # wget -qO- "https://aur.archlinux.org/cgit/aur.git/plain/imagemagick-inkscape-1.0.patch?h=imagemagick-full" | patch -Np1 -i - && \
  autoreconf -fi && \
  CPPFLAGS=-I$BUILD_DIR/include \
  LDFLAGS=-L$BUILD_DIR/lib \
  PKG_CONFIG_PATH=$BUILD_DIR/lib/pkgconfig \
  ./configure \
    --prefix="$BUILD_DIR" \
    --disable-shared \
    --disable-static \
    --disable-dependency-tracking \
    --disable-docs \
    --enable-openmp \
    --enable-opencl \
    --enable-cipher \
    --enable-hdri \
    --without-threads \
    --without-modules \
    --with-jemalloc \
    --with-tcmalloc \
    --with-umem \
    --with-bzlib \
    --with-x \
    --with-zlib \
    --with-zstd \
    --with-autotrace \
    --without-dps \
    --with-fftw \
    --with-fpx \
    --with-djvu \
    --with-fontconfig \
    --with-freetype \
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
    --with-fontpath=/usr/share/fonts/truetype \
    --with-dejavu-font-dir=/usr/share/fonts/truetype/ttf-dejavu \
    --with-gs-font-dir=/usr/share/fonts/type1/gsfonts && \
  make -j$(nproc) install || exit 1
}

build_libfpx
build_imagemagick

cd $GITHUB_WORKSPACE && \
if [ -x $BUILD_DIR/bin/magick ]; then
  cp $BUILD_DIR/bin/magick . && \
  strip magick
  ./magick -version
  tar -cJvf magick-$PLATFORM.tar.xz magick
fi

ccache --show-stats || true

exit 0
