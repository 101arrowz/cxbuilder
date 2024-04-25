#!/bin/sh
#
# CXBuilder - build Wine from source with CrossOver patches
#

set -e

CXB_LOG_FILE="${CXB_LOG_FILE:-cxbuilder.log}"

err() { echo "$@" 1>&2; }
log() { echo "$@" >> $CXB_LOG_FILE; }
usage() {
    err "$0 [--no-gptk] [-o dest_dir] [source_dir]"
    err ""
    err "Arguments:"
    err "    --no-gptk      Disable use of DirectX DLLs from Apple's Game Porting Toolkit"
    err "                   (GPTk). GPTk is unsupported on Intel-based Macs. This flag is"
    err "                   disabled by default (i.e. GPTk is included)."
    err "    -o dest_dir    Where to write the built result to."
    err "    source_dir     The directory in which the source files are present. Defaults"
    err "                   to the current working directory.                            "
}

IS_MACOS=0; [ "`uname -s`" = "Darwin" ] && IS_MACOS=1
USE_GPTK=1
SOURCE_DIR=

while test $# != 0
do
    case "$1" in
    -h|--help) usage; exit 0;;
    --no-gptk) USE_GPTK=0;;
    *)
        if [ -z $SOURCE_DIR ]; then
            SOURCE_DIR="$1"
        else
            err "[error] unknown argument $1\n";
            usage;
            exit 1;
        fi;
    esac
    shift
done

echo "-- CXBuilder `date '+%Y-%m-%d %H:%M:%S'` --" > $CXB_LOG_FILE

if [ $IS_MACOS = 0 ]; then
    err "[warn] CXBuilder is only tested on macOS. Expect things to break."
fi

if ([ $IS_MACOS = 0 ] || [ `arch` != "arm64" ]) && [ $USE_GPTK = 1 ]; then
    err "[warn] building with GPTk on a non-Apple Silicon device, but GPTk only supports Apple Silicon"
    if [ -z "$CXB_FORCE_GPTK" ]; then
        err "[error] exiting; either use --no-gptk, or set \$CXB_FORCE_GPTK build with GPTk anyway"
        exit 1
    fi
fi

if [ $IS_MACOS != 0 ]; then
    export CC="${CC:-/usr/bin/clang}";
    export CXX="${CXX:-/usr/bin/clang++}";
fi

# TODO: which file?
# configure
#     --disable-option-checking \
#     --disable-tests \         
#     --enable-archs=i386,x86_64 \
#     --without-alsa \
#     --without-capi \
#     --with-coreaudio \
#     --with-cups \
#     --without-dbus \
#     --without-fontconfig \
#     --with-freetype \
#     --with-gettext \
#     --without-gettextpo \
#     --without-gphoto \
#     --with-gnutls \
#     --without-gssapi \
#     --with-gstreamer \
#     --with-inotify \
#     --without-krb5 \
#     --with-mingw \
#     --without-netapi \
#     --with-opencl \
#     --with-opengl \
#     --without-oss \
#     --with-pcap \
#     --with-pcsclite \
#     --with-pthread \
#     --without-pulse \
#     --without-sane \
#     --with-sdl \
#     --without-udev \
#     --with-unwind \
#     --without-usb \
#     --without-v4l2 \
#     --with-vulkan \
#     --without-wayland \
#     --without-x