#!/bin/bash

export CC="ccache gcc"
export CXX="ccache g++"
export LD="ccache ld"
export AR="ccache ar"
# export CC="ccache clang"
# export CXX="ccache clang++"
# export LD="ccache ld.lld"
# export AR="ccache llvm-ar"
# export STRIP="llvm-strip"
export CCACHE_DIR="$GITHUB_WORKSPACE/.ccache"

WORK_DIR=$HOME/work
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
  local _repo
  _repo=$1
  wget -cO- --header="Authorization: token $GH_TOKEN" "https://api.github.com/repos/${_repo}/releases/latest" |\
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

build_libultrahdr() {
  cd "$WORK_DIR" && \
  git clone --depth 1 https://github.com/google/libultrahdr.git
  mkdir -p libultrahdr/build
  cmake -B libultrahdr/build -S libultrahdr \
    -G "Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR" \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DUHDR_BUILD_EXAMPLES=OFF \
    -Wno-dev
  cmake --build libultrahdr/build --target install -- -j$(nproc) || exit 1
}

# ImageMagick
build_imagemagick() {
  if [[ $APPIMAGE == false ]]; then
    CONFIG_ENV+=( "CPPFLAGS=-I$BUILD_DIR/include LDFLAGS=-L$BUILD_DIR/lib PKG_CONFIG_PATH=$BUILD_DIR/lib/pkgconfig" )
    CONFIG_OPTS+=( "--disable-shared --enable-static" )
  fi
  if [[ $HDRI == OFF ]]; then
    CONFIG_OPTS+=( "--disable-hdri" )
  fi
  local _repo
  _repo='ImageMagick/ImageMagick'
  cd "$WORK_DIR" && \
  # wget -cO- https://imagemagick.org/download/ImageMagick.tar.xz | tar -xJ
  # wget -qO- --header="Authorization: token $GH_TOKEN" "https://api.github.com/repos/${_repo}/releases/latest" |\
  #   jq -r '.tag_name' | xargs -I{} wget -cO- https://github.com/${_repo}/archive/refs/tags/{}.tar.gz | tar -xz
  gh api repos/${_repo}/releases/latest --jq '.tag_name' |\
    xargs -I{} wget -qO- https://github.com/${_repo}/archive/refs/tags/{}.tar.gz | tar -xz
  cd ImageMagick-*/ && \
  autoreconf -fi && \
  ./configure ${CONFIG_ENV[@]} \
    --prefix=/usr \
    --disable-static \
    --disable-dependency-tracking \
    --enable-cipher \
    --enable-opencl \
    --with-djvu \
    --with-fftw \
    --with-fontconfig \
    --with-freetype \
    --with-gvc \
    --with-heic \
    --with-jxl \
    --with-lqr \
    --with-openexr \
    --with-openjp2 \
    --with-pango \
    --with-quantum-depth=$QDEPTH \
    --with-raqm \
    --with-raw \
    --with-rsvg \
    --with-tcmalloc \
    --with-uhdr \
    --with-webp \
    --with-zstd \
    --without-dps \
    --without-gslib \
    --without-magick-plus-plus \
    ${CONFIG_OPTS[@]} \
    --with-dejavu-font-dir='/usr/share/fonts/truetype/dejavu' \
    --with-fontpath='/usr/share/fonts/type1'
  sed -i -e 's/ -shared / -Wl,-O1,--as-needed\0/g' libtool
  make -j$(nproc) install-strip DESTDIR=$WORK_DIR/AppDir || exit 1
}

if [[ $APPIMAGE == false ]]; then
  # build_libultrahdr
  build_jpeg-xl
  build_libfpx
fi

build_imagemagick

cd $WORK_DIR && \
VERSION=$(LD_LIBRARY_PATH=$PWD/AppDir/usr/lib AppDir/usr/bin/magick -version | grep -Po '^Version[\D]+\K.+Q\d+(-HDRI)?' | tr -s ' ' -)
find AppDir/usr/lib -type f -name '*.la' -delete
rm -rf AppDir/usr/include AppDir/usr/share/doc AppDir/usr/bin/*-config

if [[ $APPIMAGE == false ]]; then
  UBUNTU_ID=$(awk -F= '/^VERSION_ID=/ {print $2}' /etc/os-release | tr -d '".')
  tar -C AppDir/usr/bin -cJvf ImageMagick-$VERSION-$PLATFORM-ubuntu$UBUNTU_ID.tar.xz .
elif [[ $APPIMAGE == true ]]; then
  export APPIMAGE_EXTRACT_AND_RUN=1
  mkdir -p AppDir/usr/share/applications AppDir/usr/share/icons/hicolor/128x128/apps
  install -vm644 ImageMagick-*/app-image/imagemagick.desktop AppDir/usr/share/applications/
  install -vm644 ImageMagick-*/app-image/icon.png AppDir/usr/share/icons/hicolor/128x128/apps/imagemagick.png
  install -vm755 $GITHUB_WORKSPACE/AppRun AppDir
  for i in SHAREARCH_PATH CODER_PATH FILTER_PATH ; do
    _value=$(find AppDir -type f -name 'configure.xml' | xargs xmlstarlet sel -t -m "configuremap/configure[@name='$i']" -v @value)
    sed "s|@$i@|$_value|" -i AppDir/AppRun
  done
  # appimagetool with Squashfs zstd compression support and static runtime
  wget -qO linuxdeploy https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage
  wget -qO appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage
  wget -qO runtime https://github.com/probonopd/static-tools/releases/download/2023/runtime-fuse2-$ARCH
  chmod +x linuxdeploy appimagetool
  NO_STRIP=1 DISABLE_COPYRIGHT_FILES_DEPLOYMENT=1 LD_LIBRARY_PATH=$PWD/AppDir/usr/lib ./linuxdeploy --appdir=AppDir && \
  VERSION=$VERSION ./appimagetool -v --runtime-file runtime AppDir
  # tar -cvf ImageMagick-$VERSION-$PLATFORM.AppImage.tar ImageMagick*.AppImage
fi

ccache --max-size=100M --show-stats
