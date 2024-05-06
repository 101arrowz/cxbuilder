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
fetch_deps=1
wine_dir=
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

exite() {
    err "$@"
    exit 1
}

warn() {
    out=`fmt_lr "[warn]  " "\n" "$@"; printf "."`
    out="${out%?}"
    eprint "$out"
    log_write "$out"
}

key_info() {
    out=`fmt_lr "[info]  " "\n" "$@"; printf "."`
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
    eprintn "$0 [-v] [-x] [--wine dir] [--gptk dir] [--dxvk dir] [--no-deps] [--out dest_dir] [source_dir]"
    eprintn ""
    eprintn "Arguments:"
    eprintn "    -h, --help           Prints this help message and exits"
    eprintn "    -v, --verbose        Enables verbose logging of build commands and results"
    eprintn "    -x, --no-prompt      Run non-interactively"
    eprintn ""
    eprintn "    -w, --wine           Uses the Wine sources from the specified directory."
    eprintn "                         CXBuilder is designed specifically to work with the"
    eprintn "                         Wine sources provided with the open-source distribution"
    eprintn "                         of CrossOver, which include various \"hacks\" to make"
    eprintn "                         software that breaks with mainline Wine work anyway."
    eprintn "                         However, CXBuilder should work the original Wine too,"
    eprintn "                         or any fork. Defaults to [source_dir]/wine."
    eprintn ""
    eprintn "    --no-gptk            Disable use of Direct3D DLLs from Apple's Game Porting"
    eprintn "                         Toolkit (GPTk). GPTk is supported only on Apple Silicon"
    eprintn "                         Macs. GPTk disabled by default on all other devices."
    eprintn ""
    eprintn "    --gptk dir           Uses the Game Porting Toolkit from the specified"
    eprintn "                         directory. This should have a redist/ subdirectory with"
    eprintn "                         Apple's proprietary Direct3D -> Metal translation"
    eprintn "                         layer libraries inside. Defaults to [source_dir]/gptk."
    eprintn ""
    eprintn "    --no-dxvk            Disables the use of Direct3D DLLs from DXVK. Note that"
    eprintn "                         if GPTk is enabled, DXVK will only be used for 32-bit"
    eprintn "                         software (as GPTk does not support 32-bit Direct3D)."
    eprintn ""
    eprintn "    --dxvk dir           Uses the DXVK build from the specified directory. This"
    eprintn "                         should have x32/ and x64/ subdirectories with Direct3D"
    eprintn "                         DLLs. Note that if both GPTk and DXVK are enabled, GPTk"
    eprintn "                         will take priority (i.e. only the x32/ DLLs from DXVK"
    eprintn "                         will be used). Defaults to [source_dir]/dxvk."
    eprintn ""
    eprintn "    --no-deps            Disables the built-in dependency fetcher. Setting this"
    eprintn "                         flag makes it possible to use custom builds of Wine"
    eprintn "                         dependencies, rather than pre-built versions from the"
    eprintn "                         Homebrew project; however, you will need to configure"
    eprintn "                         the static and dynamic linker flags manually to point"
    eprintn "                         to the correct locations of your dependencies. This"
    eprintn "                         is not necessary for most builds and can lead to many"
    eprintn "                         headaches if misused; the built-in dependency fetcher"
    eprintn "                         is very fast and does not install anything globally"
    eprintn "                         into your system (not even Homebrew!)"
    eprintn ""
    eprintn "    -o, --out dest_dir   Where to generate the final Wine build. This directory"
    eprintn "                         will contain a similar structure to /usr/local (and"
    eprintn "                         that is indeed a valid value for this argument) after"
    eprintn "                         the build completes. However, the build can be placed"
    eprintn "                         anywhere on your system and may be moved around freely"
    eprintn "                         afterwards, so long as relative symlinks are preserved."
    eprintn "                         Defaults to [source_dir]/build."
    eprintn ""
    eprintn "    source_dir           The directory in which the source files are present."
    eprintn "                         It is not necessary to use this directory, but it can"
    eprintn "                         be used to create a build with only one argument."
}

while test $# != 0
do
    case "$1" in
    -h|--help) usage; exit 0;;
    -v|--verbose) verbose=1;;
    -x|--no-prompt) is_interactive=0;;
    -w|--wine) shift; wine_dir="$1";;
    --no-gptk) use_gptk=0;;
    --no-dxvk) use_dxvk=0;;
    --gptk) shift; use_gptk=1; gptk_dir="$1";;
    --dxvk) shift; use_dxvk=1; dxvk_dir="$1";;
    --no-deps) fetch_deps=0;;
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
        exite "No destination directory specified; specify a source directory or use -o your/build/directory"
    fi

    if test -z "$wine_dir"; then
        exite "No Wine directory specified; specify a source directory or use -w your/wine/sources/directory"
    fi

    if test $use_gptk = 1 && test -z "$gptk_dir"; then
        exite "GPTk is enabled but no GPTk directory was provided; specify a source directory, use --no-gptk, or use --gptk your/gptk/directory"
    fi

    if test $use_dxvk = 1 && test -z "$dxvk_dir"; then
        exite "DXVK is enabled but no DXVK directory was provided; specify a source directory, use --no-dxvk, or use --dxvk your/dxvk/directory"
    fi
else
    source_dir_err="cannot use source directory $source_dir"

    if ! test -e "$source_dir"; then
        exite "%s; does not exist" "$source_dir_err"
    fi

    if ! test -d "$source_dir"; then
        exite "%s; not a directory" "$source_dir_err"
    fi
fi

dst_dir="${dst_dir:-$source_dir/build}"
scratch_dir="$dst_dir/$CXB_TEMP"
wine_dir="${wine_dir:-$source_dir/wine}"
dxvk_dir="${dxvk_dir:-$source_dir/dxvk}"
gptk_dir="${gptk_dir:-$source_dir/gptk}"

info "using wine from $wine_dir"

wine_err="cannot load wine from $wine_dir"

if test ! -e "$wine_dir"; then
    exite "%s; does not exist" "$wine_err"
fi

if test ! -d "$wine_dir"; then
    exite "%s; not a directory" "$wine_err"
fi

if test ! -f "$wine_dir/configure"; then
    exite "%s; could not locate configure script"
fi

info "$wine_dir has valid Wine sources"

if test $use_gptk = 1; then
    info "using gptk from $gptk_dir"

    gptk_err="cannot load GPTk from $gptk_dir"

    if test ! -e "$gptk_dir"; then
        exite "%s; does not exist" "$gptk_err"
    fi

    if test ! -d "$gptk_dir"; then
        exite "%s; not a directory" "$gptk_err"
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
        exite "%s; does not exist" "$dxvk_err"
    fi

    if test ! -d "$dxvk_dir"; then
        exite "%s; not a directory" "$dxvk_err"
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
            exite "%s; no DXVK DLLs found" "$dxvk_err"
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
        exite "failed to create $dst_dir; path exists"
    fi

    if mkdir "$dst_dir" 2> /dev/null; then
        info "successfully created $dst_dir"
    else
        exite "failed to create $dst_dir"
    fi
else
    if test -d "$scratch_dir"; then
        info "found prior CXBuilder tempdir in $dst_dir"
    fi
fi

if ! test -d "$scratch_dir"; then
    mkdir "$scratch_dir" 2> /dev/null || if tmp_dir="`mktemp -d 2> /dev/null`"; then
        scratch_dir="$tmp_dir"
    else
        exite "failed to create CXBuilder tempdir $scratch_dir"
    fi
    info "successfully created $scratch_dir"

fi

info "validation complete; starting build"

mvk_dir="$scratch_dir/molten-vk"
wine_build_dir="$scratch_dir/wine-build"

if test $fetch_deps = 1; then
    brew_dir="$scratch_dir/brew"
    brew_dl_dir="$brew_dir/.dl"
    ext_dir="$scratch_dir/ext"
    ext_scratch_dir="$ext_dir/.scratch"
    
    test -d "$brew_dir" || mkdir "$brew_dir" 2> /dev/null || exite "failed to create $brew_dir"
    test -d "$ext_dir" || mkdir "$ext_dir" 2> /dev/null || exite "failed to create $ext_dir"

    brew_deps="bison pkg-config mingw-w64 freetype gettext gnutls gstreamer sdl2"
    if test $is_macos = 1; then
        brew_deps="$brew_deps molten-vk"
    fi

    missing_brew_deps=""

    for d in $brew_deps; do
        if test ! -d "$brew_dir/$d"; then
            missing_brew_deps="${missing_brew_deps:+$missing_brew_deps }$d"
        fi
    done

    pre_brew() {
        for cmd in curl tar; do
            command -v $cmd > /dev/null || exite "cannot locate $cmd; please install $cmd to use the built-in dependency fetcher, or use --no-deps and install the Wine dependencies yourself"
        done
        test -d "$brew_dl_dir" || mkdir "$brew_dl_dir" 2> /dev/null || exite "failed to create $brew_dl_dir"
    }

    pre_ext() {
        test -d "$ext_scratch_dir" || mkdir "$ext_scratch_dir" 2> /dev/null || exite "failed to create $ext_scratch_dir"
    }

    # extract json
    ext_json() {
        if test $is_macos = 1; then
            osj_da='Object.defineProperty(Array.prototype, "sh", { get: function() { return this.join(" "); } });'
            osj_parse='var data = JSON.parse($.NSString.alloc.initWithDataEncoding($.NSFileHandle.fileHandleWithStandardInput.readDataToEndOfFileAndReturnError(null), 4).js);'
            /usr/bin/osascript -l 'JavaScript' -e "$osj_da" -e "$osj_parse" -e "var res = data$1; typeof res == 'string' ? res : res == null ? undefined : JSON.stringify(res)" 2> /dev/null
        else
            builtin_py=`command -v python` || builtin_py=`command -v python3` || \
                exite "cannot locate Python; please install Python to use the built-in dependency fetcher, or use --no-deps and install the Wine dependencies yourself"
            pyjd_dd='class dd(dict): __getattr__ = dict.get; __setattr__ = dict.__setitem__; __delattr__ = dict.__delitem__'
            pyjd_da=`printf "class da(list):\n @property\n def length(self):\n  return len(self)\n @property\n def sh(self):\n  return ' '.join(str(v) for v in self)"`
            pyjd_conv='cv = lambda v: da([cv(a) for a in v]) if isinstance(v, list) else (dd({k:cv(a) for k, a in v.items()}) if isinstance(v, dict) else v)'
            pyj_decoder=`printf "import sys, json\n$pyjd_dd\n$pyjd_da\n$pyjd_conv\ndata = cv(json.load(sys.stdin))"`
            PYTHONIOENCODING=utf8 $builtin_py -c "$pyj_decoder; res = data$1; print(res if isinstance(res, str) else json.dumps(res)) if res is not None else None" 2> /dev/null
        fi
    }

    sys_info=x86_64_linux
    if test $is_macos = 1; then
        case `/usr/bin/sw_vers -productVersion` in
            14.*) sys_info="sonoma";;
            13.*) sys_info-"ventura";;
            12.*) sys_info="monterey";;
            *) sys_info="unknown";;
        esac
    fi

    # minibrew - uses the Homebrew API to fetch prebuilt bottles
    minibrew() {
        if test -d "$brew_dl_dir/$1"; then
            info "package $1 already installed; skipping"
            return
        fi

        info_url="https://formulae.brew.sh/api/formula/$1.json"
        info_json=`curl -s "$info_url"`

        info_bottle=`ext_json .bottle.stable <<< "$info_json"`
        test -z "$info_bottle" && exite "failed to load bottle info for $1"
        
        info_bottle_arch=`ext_json ".files.$sys_info" <<< "$info_bottle"`
        if test -z "$info_bottle_arch"; then
            info_bottle_arch=`ext_json ".files.all" <<< "$info_bottle"`
        fi
        test -z "$info_bottle_arch" && exite "failed to load bottle info for $1, system type $sys_info"

        info_bottle_url=`ext_json ".url" <<< "$info_bottle_arch"`
        info_bottle_sha=`ext_json ".sha256" <<< "$info_bottle_arch"`

        info "fetching $1 from $info_bottle_url (sha = $info_bottle_sha)"
        key_info "downloading $1..."

        curl_extra_opts="-s"
        if test $verbose = 1; then
            curl_extra_opts="-#"
        fi

        if curl $curl_extra_opts -g -H "Authorization: Bearer QQ==" -L  -o "$brew_dl_dir/$info_bottle_sha" -C - "$info_bottle_url"; then
            info "download $1 successful; extracting"
        else
            exite "failed to download $1 from $info_bottle_url"
        fi

        if tar -zxf "$brew_dl_dir/$info_bottle_sha" -C "$brew_dl_dir"; then
            info "extracting $1 successful"
        else
            exite "failed to extract $1 from $brew_dl_dir/$info_bottle_sha to $brew_dl_dir"
        fi

        info_deps=`ext_json .dependencies.sh <<< "$info_json"`

        for d in $info_deps; do
            minibrew "$d"
        done
    }
    
    if test -n "$missing_brew_deps"; then
        key_info "missing Wine dependencies; installing with built-in dependency fetcher"
        pre_brew

        for d in $missing_brew_deps; do
            minibrew "$d"
        done
    fi

    libinkq_dir="$ext_dir/libinotify-kqueue"

    if test ! -d "$libinkq_dir"; then
        key_info "missing libinotify-kqueue; building from source"
        pre_ext
        pre_brew

        minibrew "automake"

        key_info "downloading libinotify-kqueue sources..."
        libinkq_url="https://api.github.com/repos/libinotify-kqueue/libinotify-kqueue/tarball/master"

        libinkq_build_dir="$ext_scratch_dir/libinotify-kqueue"
        test -d "$libinkq_build_dir" || mkdir "$libinkq_build_dir" || exite "failed to create $libinkq_build_dir"

        if curl -s -L "$libinkq_url" | tar -zx --strip-components=1 -C "$libinkq_build_dir"; then
            info "download + extract libinotify-kqueue sources successful"
        else
            exite "failed to download and extract libinotify-kqueue sources from $libinkq_url"
        fi
    fi
else
    info "--no-deps specified; assuming dependencies are already available"
fi

wineconf_args="--disable-option-checking --disable-tests --enable-archs=i386,x86_64 --without-alsa \
--without-capi --with-coreaudio --with-cups --without-dbus --without-fontconfig --with-freetype \
--with-gettext --without-gettextpo --without-gphoto --with-gnutls --without-gssapi --with-gstreamer \
--with-inotify --without-krb5 --with-mingw  --without-netapi --with-opencl --with-opengl --without-oss \
--with-pcap --with-pcsclite --with-pthread --without-pulse --without-sane --with-sdl --without-udev \
--with-unwind --without-usb --without-v4l2 --with-vulkan --without-wayland --without-x $CXB_CONF_ARGS"


# "$wine_dir"/configure $wineconf_args --prefix="$wine_build_dir"

# TODO: which file?