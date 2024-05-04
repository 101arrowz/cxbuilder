#!/bin/sh
#
# CXBuilder - build Wine from source with CrossOver patches
#

set -e

CXB_LOG_FILE="${CXB_LOG_FILE:-/dev/null}"
CXB_TEMP="${CXB_TEMP:-.cxbuilder}"

verbose=0
is_macos=0; test "`uname -s`" = "Darwin" && is_macos=1
is_interactive=0; test -t 0 && is_interactive=1
use_gptk=
use_dxvk=
gptk_dir=
dxvk_dir=
source_dir=
dst_dir=
tmp_build=

err() {
    out=`fmt_lr "[error] " "\n" "$@"; printf "."`
    out="${out%?}"
    eprint "$out"
    log_write "$out"
}

warn() {
    out=`fmt_lr "[warn]  " "\n" "$@"; printf "."`
    out="${out%?}"
    eprint "$out"
    log_write "$out"
}

info() {
    out=`fmt_lr "[info]  " "\n" "$@"; printf "."`
    out="${out%?}"
    if test $verbose = 1; then
        eprint "$out"
    fi
    log_write "$out"   
}

prompt_continue() {
    if test $is_interactive = 1; then
        out=`fmt_lr "\n" " [y/N] " "$@"; printf "."`
        out="${out%?}"
        log_write "[info]  prompting: $out\n"

        eprint "$out"
        read res

        case $res in
        y*|Y*);;
        *) exit 1;;
        esac
        
        eprint "\n"
    fi
}

fmt_lr() {
    fmt="$1$3$2"
    shift 3
    printf "$fmt" "$@"
}

eprint() { printf "$1" >&2; }
eprintn() { printf "$1\n" >&2; }
log_write() { printf "$1" >> $CXB_LOG_FILE; }

usage() {
    eprintn "$0 [-v] [-x] [--gptk DIR] [--dxvk DIR] [-o DEST_DIR] [SOURCE_DIR]"
    eprintn ""
    eprintn "Arguments:"
    eprintn "    -h, --help           Prints this help message and exits"
    eprintn "    -v, --verbose        Enables verbose logging of build commands and results"
    eprintn "    -x, --no-prompt      Run non-interactively"
    eprintn ""
    eprintn "    --no-gptk            Disable use of Direct3D DLLs from Apple's Game Porting"
    eprintn "                         Toolkit (GPTk). GPTk is supported only on Apple Silicon"
    eprintn "                         Macs. GPTk disabled by default on all other devices."
    eprintn ""
    eprintn "    --gptk DIR           Uses the Game Porting Toolkit from the specified"
    eprintn "                         directory. This should have a redist/ subdirectory with"
    eprintn "                         Apple's proprietary Direct3D -> Metal translation"
    eprintn "                         layer libraries inside. Defaults to SOURCE_DIR/gptk."
    eprintn ""
    eprintn "    --no-dxvk            Disables the use of Direct3D DLLs from DXVK. Note that"
    eprintn "                         if GPTk is enabled, DXVK will only be used for 32-bit"
    eprintn "                         software (as GPTk does not support 32-bit Direct3D)."
    eprintn ""
    eprintn "    --dxvk DIR           Uses the DXVK build from the specified directory. This"
    eprintn "                         should have x32/ and x64/ subdirectories with Direct3D"
    eprintn "                         DLLs. Note that if both GPTk and DXVK are enabled, GPTk"
    eprintn "                         will take priority (i.e. only the x32/ DLLs from DXVK"
    eprintn "                         will be used). Defaults to SOURCE_DIR/dxvk."
    eprintn ""
    eprintn "    -o, --out DEST_DIR   Where to generate the final Wine build. This directory"
    eprintn "                         will contain a similar structure to /usr/local (and"
    eprintn "                         that is indeed a valid value for this argument) after"
    eprintn "                         the build completes. However, the build can be placed"
    eprintn "                         anywhere on your system and may be moved around freely"
    eprintn "                         afterwards, so long as relative symlinks are preserved."
    eprintn "                         Defaults to SOURCE_DIR/build."
    eprintn ""
    eprintn "    SOURCE_DIR           The directory in which the source files are present."
    eprintn "                         It is not necessary to use this directory, but it can"
    eprintn "                         be used to create a build with only one argument."
    eprintn ""
}

while test $# != 0
do
    case "$1" in
    -h|--help) usage; exit 0;;
    -v|--verbose) verbose=1;;
    -x|--no-prompt) is_interactive=0;;
    --no-gptk) use_gptk=0;;
    --no-dxvk) use_dxvk=0;;
    --gptk) shift; use_gptk=1; gptk_dir="$1";;
    --dxvk) shift; use_dxvk=1; dxvk_dir="$1";;
    -o|--out) shift; dst_dir="$1";;
    -*) eprintn "unknown argument $1"; usage; exit 1;;
    *)
        if test -z "$source_dir"; then
            source_dir="$1"
        else
            eprintn "unknown argument $1"
            usage
            exit 1
        fi;
    esac
    shift
done

cleanup() {
    if test ! -z "$tmp_build"; then
        rm -rf "$tmp_build"
    fi
    trap - EXIT
    exit
}

trap cleanup EXIT INT HUP TERM

echo "-- CXBuilder `date '+%Y-%m-%d %H:%M:%S'` --" > $CXB_LOG_FILE

if test $is_interactive = 0; then
    info "running non-interactively"
fi

if test $is_macos = 0; then
    warn "CXBuilder is only tested on macOS; expect things to break"
fi

is_apple_silicon=0
if ( test $is_macos = 1 && test `arch` = "arm64" ); then
    is_apple_silicon=1
    info "running on Apple Silicon"
else
    info "not an Apple Silicon device"
fi

if test -z $use_gptk; then
    info "gptk options unspecified; `test $is_apple_silicon = 1 && echo "enabling by default on Apple Silicon" || echo "disabling by default (not on Applle Silicon)"`"
    use_gptk=$is_apple_silicon
fi

if test $is_apple_silicon = 0 && test $use_gptk = 1 && test -z $CXB_FORCE_GPTK; then
    warn "building with GPTk on a non-Apple Silicon device, but GPTk only supports Apple Silicon devices; things will likely break"
    warn "use --no-gptk or set \$CXB_FORCE_GPTK to silence this warning"
    prompt_continue "Continue?"
fi

if test $is_macos = 1; then
    if test -z "$CC"; then
        info "running macOS and \$CC not set; defaulting to clang"
    fi
    if test -z "$CXX"; then
        info "running macOS and \$CXX not set; defaulting to clang++"
    fi

    # prevent Wine from thinking it has GCC
    export CC="${CC:-/usr/bin/clang}";
    export CXX="${CXX:-/usr/bin/clang++}";
fi

info "CC=${CC:-\(unset\)}; CXX: ${CXX:-\(unset\)}"

if test -z $use_dxvk; then
    info "dxvk options unspecified; enabling by default"
fi

use_dxvk="${use_dxvk:-1}"

if test -z "$source_dir"; then
    if test -z "$dst_dir"; then
        err "No destination directory specified; specify a source directory or use -o your/build/directory"
        exit 1
    fi

    if test $use_gptk = 1 && test -z "$gptk_dir"; then
        err "GPTk is enabled but no GPTk directory was provided; specify a source directory, use --no-gptk, or use --gptk your/gptk/directory"
        exit 1
    fi

    if test $use_dxvk = 1 && test -z "$dxvk_dir"; then
        err "DXVK is enabled but no DXVK directory was provided; specify a source directory, use --no-dxvk, or use --dxvk your/dxvk/directory"
        exit 1
    fi
else
    source_dir_err="cannot use source directory $source_dir"

    if ! test -e "$source_dir"; then
        err "%s; does not exist" "$source_dir_err"
        exit 1
    fi

    if ! test -d "$source_dir"; then
        err "%s; not a directory" "$source_dir_err"
        exit 1
    fi
fi

dxvk_dir="${dxvk_dir:-$source_dir/dxvk}"
gptk_dir="${gptk_dir:-$source_dir/gptk}"

if test $use_gptk = 1; then
    info "using gptk from $gptk_dir"

    gptk_err="cannot load GPTk from $gptk_dir"

    if test ! -e "$gptk_dir"; then
        err "%s; does not exist" "$gptk_err"
        exit 1
    fi

    if test ! -d "$gptk_dir"; then
        err "%s; not a directory" "$gptk_err"
        exit 1
    fi

    gptk_paths="/redist/lib/external/D3DMetal.framework /redist/lib/external/libd3dshared.dylib \
                /redist/lib/wine/x86_64-windows/d3d9.dll /redist/lib/wine/x86_64-windows/d3d10.dll \
                /redist/lib/wine/x86_64-windows/d3d11.dll /redist/lib/wine/x86_64-windows/d3d12.dll \
                /redist/lib/wine/x86_64-windows/dxgi.dll"

    for p in $gptk_paths; do
        if test ! -e "$gptk_dir$p"; then
            err "%s; could not find $gptk_dir$p" "$gptk_err"
            exit 1
        fi
    done

    info "$gptk_dir has a valid GPTk redistributable"
else
    info "not using gptk"
fi

if test $use_dxvk = 1; then
    info "using dxvk from $dxvk_dir"

    dxvk_err="cannot load DXVK from $dxvk_dir"

    if test ! -e "$dxvk_dir"; then
        err "%s; does not exist" "$dxvk_err"
        exit 1
    fi

    if test ! -d "$dxvk_dir"; then
        err "%s; not a directory" "$dxvk_err"
        exit 1
    fi

    dxvk_paths="/x32/d3d9.dll /x32/d3d10core.dll /x32/d3d11.dll /x32/dxgi.dll \
                /x64/d3d9.dll /x64/d3d10core.dll /x64/d3d11.dll /x64/dxgi.dll"

    missing_dxvk_paths=
    any_dxvk_path=0
    for p in $dxvk_paths; do
        if test ! -e "$dxvk_dir$p"; then
            missing_dxvk_paths="${missing_dxvk_paths:+$missing_dxvk_paths, }$p"
        else
            any_dxvk_path=1
        fi
    done

    if test -n "$missing_dxvk_paths"; then
        warn "missing the following DXVK DLLs: $missing_dxvk_paths"
        if test $any_dxvk_path = 0; then
            err "%s; no DXVK DLLs found" "$dxvk_err"
            exit 1
        fi
        prompt_continue "The provided DVXK build seems incomplete. Continue?"
    fi

    info "$dxvk_dir has a valid DXVK build"
else
    info "not using dxvk"
fi

if ! test -d "$dst_dir"; then
    info "creating build directory $dst_dir"

    if test -e "$dst_dir"; then
        err "failed to create $dst_dir; path exists"
        exit 1
    fi

    if mkdir "$dst_dir"; then
        info "successfully created $dst_dir"
    else
        err "failed to create $dst_dir"
        exit 1
    fi
else
    if test -d "$dst_dir/$CXB_TEMP"; then
        info "found prior CXBuilder run in $dst_dir"
    fi
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