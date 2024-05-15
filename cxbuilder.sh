#!/bin/sh
#
# CXBuilder - build Wine from source with CrossOver patches
#

set -e

reset_ifs() {
    IFS=' 	
'
}

reset_ifs

abspath() {
    if test -d "$1"; then
        (cd "$1" && pwd)
    else
        echo "$(abspath "$(dirname "$1")")/$(basename -- "$1")"
    fi
}

CXB_LOG_FILE="$(abspath "${CXB_LOG_FILE:-/dev/null}")"

verbose=0
is_macos=0; test "$(uname -s)" = "Darwin" && is_macos=1
is_interactive=0; test -t 0 && is_interactive=1
fetch_deps=1
rebuild_wine=0
post_clean="$(test -z "$CXB_TEMP" && echo 1 || echo 0)"
wine_dir=
use_gptk=
use_dxvk=
gptk_dir=
dxvk_dir=
source_dir=
dst_dir=
tmp_build=
tmp_prefix=

err() {
    out="$(fmt_lr "[error] " "\n" "$@"; printf ".")"
    out="${out%?}"
    eprint "$out"
    log_write "$out"
}

exite() {
    err "$@"
    exit 1
}

warn() {
    out="$(fmt_lr "[warn]  " "\n" "$@"; printf ".")"
    out="${out%?}"
    eprint "$out"
    log_write "$out"
}

key_info() {
    out="$(fmt_lr "[info]  " "\n" "$@"; printf ".")"
    out="${out%?}"
    eprint "$out"
    log_write "$out"   
}

info() {
    out="$(fmt_lr "[info]  " "\n" "$@"; printf ".")"
    out="${out%?}"
    if test $verbose = 1; then
        eprint "$out"
    fi
    log_write "$out"   
}

extinfo() {
    if test $verbose = 1; then
        tee -a "$CXB_LOG_FILE" >&2
    else
        tee -a "$CXB_LOG_FILE" > /dev/null
    fi
}

prompt_continue() {
    if test $is_interactive = 1; then
        out="$(fmt_lr "\n" " [y/N] " "$@"; printf ".")"
        out="${out%?}"
        log_write "[info]  prompting: $out\n"

        eprint "$out"
        read -r res

        case $res in
        y*|Y*);;
        *) exit 1;;
        esac
        
        eprintn ""
    fi
}

fmt_lr() {
    fmt="$1$3$2"
    shift 3
    printf "$fmt" "$@"
}

eprint() { printf "%s" "$1" >&2; }
eprintn() { printf "%s\n" "$1" >&2; }
log_write() { printf "%s" "$1" >> "$CXB_LOG_FILE"; }

usage() {
    eprintn "$0 [-v] [-x] [--wine dir] [--gptk dir] [--dxvk dir] [--no-deps] [--rebuild] [--no-clean] [--out dest_dir] [source_dir]"
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
    eprintn "                         Macs. GPTk is disabled by default on all other devices."
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
    eprintn "                         is well-tested and does not install anything globally"
    eprintn "                         into your system (not even Homebrew!)"
    eprintn ""
    eprintn "    -r, --rebuild        Forcibly rebuilds Wine from source, ignoring cached or"
    eprintn "                         partially built results. This option will need to be"
    eprintn "                         specified after updating compiler/linker flags but"
    eprintn "                         should generally be avoided otherwise."
    eprintn ""
    eprintn "    -d, --no-clean       Skips cleaning the build cache from dest_dir after a"
    eprintn "                         build completes. Useful for debugging broken builds"
    eprintn "                         without having to rebuild from source each time, but"
    eprintn "                         should be unnecessary otherwise."
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

while test $# != 0; do
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
    -r|--rebuild) rebuild_wine=1;;
    -d|--no-clean) post_clean=0;;
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
    if test -n "$tmp_build"; then
        rm -rf "$tmp_build"
    fi
    if test -n "$tmp_prefix"; then
        rm "$tmp_prefix"
    fi
    reset_ifs
    trap - EXIT
    exit
}

trap cleanup EXIT INT HUP TERM

echo "-- CXBuilder $(date '+%Y-%m-%d %H:%M:%S') --" > "$CXB_LOG_FILE"

if test $is_interactive = 0; then
    info "running non-interactively"
fi

if test $is_macos = 0; then
    # warn "CXBuilder is only tested on macOS; expect things to break"
    prompt_continue "CXBuilder does not yet work on Linux; this build will break! Continue anyway?"
fi

is_apple_silicon=0
if test $is_macos = 1 && test "$(arch)" = "arm64"; then
    is_apple_silicon=1
    info "running on Apple Silicon"
else
    info "not an Apple Silicon device"
fi

if test -z $use_gptk; then
    if test $is_apple_silicon = 1 && test -n "$source_dir" && test -d "$source_dir/gptk"; then
        info "found gptk subdirectory of source directory %s; enabling GPTk" "$source_dir"
        use_gptk=1
    else
        info "gptk options (i.e. --gptk DIR, --no-gptk) unspecified; disabling by default"
        use_gptk=0
    fi
fi

if test $is_apple_silicon = 0 && test $use_gptk = 1 && test -z "$CXB_FORCE_GPTK"; then
    warn "building with GPTk on a non-Apple Silicon device, but GPTk only supports Apple Silicon devices; things will likely break"
    warn "use --no-gptk or set \$CXB_FORCE_GPTK to silence this warning"
    prompt_continue "Continue anyway?"
fi

if test -z "$use_dxvk"; then
    if test -n "$source_dir" && test -d "$source_dir/dxvk"; then
        info "found dxvk subdirectory of source directory %s; enabling DXVK" "$source_dir"
        use_dxvk=1
    else
        info "dxvk options (i.e. --dxvk DIR, --no-dxvk) unspecified; disabling by default"
        use_dxvk=0
    fi
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

if test -z "$source_dir"; then
    if test -z "$dst_dir"; then
        exite "No destination directory specified; specify a source directory or use -o your/build/directory"
    fi

    if test -z "$wine_dir"; then
        exite "No Wine directory specified; specify a source directory or use -w your/wine/sources/directory"
    fi
else
    source_dir_err="cannot use source directory $source_dir"

    if test ! -e "$source_dir"; then
        exite "%s; does not exist" "$source_dir_err"
    fi

    if test ! -d "$source_dir"; then
        exite "%s; not a directory" "$source_dir_err"
    fi
fi

dst_dir="$(abspath "${dst_dir:-$source_dir/build}")"
scratch_dir="$(abspath "${CXB_TEMP:-$dst_dir/.cxbuilder}")"
wine_dir="$(abspath "${wine_dir:-$source_dir/wine}")"
dxvk_dir="$(abspath "${dxvk_dir:-$source_dir/dxvk}")"
gptk_dir="$(abspath "${gptk_dir:-$source_dir/gptk}")"

info "using wine from %s" "$wine_dir"

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

info "%s has valid Wine sources" "$wine_dir"

if test $use_gptk = 1; then
    info "using gptk from %s" "$gptk_dir"

    gptk_err="cannot load GPTk from $gptk_dir"

    if test ! -e "$gptk_dir"; then
        exite "%s; does not exist" "$gptk_err"
    fi

    if test ! -d "$gptk_dir"; then
        exite "%s; not a directory" "$gptk_err"
    fi

    gptk_paths="/redist/lib/external/D3DMetal.framework /redist/lib/external/libd3dshared.dylib /redist/lib/wine/x86_64-windows/d3d9.dll /redist/lib/wine/x86_64-windows/d3d10.dll \
                /redist/lib/wine/x86_64-windows/d3d11.dll /redist/lib/wine/x86_64-windows/d3d12.dll /redist/lib/wine/x86_64-windows/dxgi.dll"

    for p in $gptk_paths; do
        if test ! -e "$gptk_dir$p"; then
            err "%s; could not locate %s" "$gptk_err" "$gptk_dir$p"
            exit 1
        fi
    done

    info "%s has a valid GPTk redistributable" "$gptk_dir"
else
    info "not using gptk"
fi

if test $use_dxvk = 1; then
    info "using dxvk from %s" "$dxvk_dir"

    dxvk_err="cannot load DXVK from $dxvk_dir"

    if test ! -e "$dxvk_dir"; then
        exite "%s; does not exist" "$dxvk_err"
    fi

    if test ! -d "$dxvk_dir"; then
        exite "%s; not a directory" "$dxvk_err"
    fi

    dxvk_paths="/x32/d3d9.dll /x32/d3d10core.dll /x32/d3d11.dll /x32/dxgi.dll /x64/d3d9.dll /x64/d3d10core.dll /x64/d3d11.dll /x64/dxgi.dll"

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
        warn "missing the following DXVK DLLs: %s" "$missing_dxvk_paths"
        if test $any_dxvk_path = 0; then
            exite "%s; no DXVK DLLs found" "$dxvk_err"
        fi
        prompt_continue "The provided DVXK build seems incomplete. Continue?"
    fi

    info "%s has a valid DXVK build" "$dxvk_dir"
else
    info "not using dxvk"
fi

if test ! -d "$dst_dir"; then
    info "creating build directory %s" "$dst_dir"

    if test -e "$dst_dir"; then
        exite "failed to create %s; path exists" "$dst_dir"
    fi

    if mkdir "$dst_dir" 2> /dev/null; then
        info "successfully created %s" "$dst_dir"
    else
        exite "failed to create %s" "$dst_dir"
    fi
fi

if test ! -d "$scratch_dir"; then
    if mkdir "$scratch_dir" 2> /dev/null; then
        info "successfully created %s" "$scratch_dir"
    elif tmp_build="$(mktemp -d 2> /dev/null)"; then
        warn "failed to create %s; creating a temporary build directory instead" "$scratch_dir"
        scratch_dir="$tmp_build"
    else
        exite "failed to create CXBuilder tempdir %s" "$scratch_dir"
    fi
else
    info "located previous CXBuilder run in %s" "$scratch_dir"
fi

info "validation complete; searching for dependencies"

get_inode() {
    ls -ldi -- "$1" | cut -d ' ' -f 1
}

get_link() {
    # TODO: breaks if you have -> in username
    # at that point you had it coming though
    ls -l -- "$1" | awk -F " -> " '{print $2}'
}

to_prec() {
    out="$(printf "%.${2}x" "$1")"
    out_oversize="$((${#out} - $2 + 1))"
    echo "$out" | cut -c "$out_oversize-"
}

build_ncpu="$(if test "$is_macos" = 1; then
    sysctl -n hw.logicalcpu
else
    if command -v nproc > /dev/null; then
        nproc
    fi
fi)"
scratch_dir_inode="$(get_inode "$scratch_dir")"

if test $fetch_deps = 1; then
    for cmd in curl tar; do
        command -v $cmd > /dev/null || exite "cannot locate %s; please install %s to use the built-in dependency fetcher, or use --no-deps and install the Wine dependencies yourself" "$cmd" "$cmd"
    done

    if test $is_macos = 0; then
        exite "The dependency fetcher is incomplete for non-macOS systems. Please use --no-deps and install the dependencies manually."
    fi

    deps_dir="$scratch_dir/deps"
    deps_dl_dir="$deps_dir/.dl"
    deps_scratch_dir="$deps_dir/.scratch"
    # name length must exactly equal 6 (same as "Cellar")
    brew_dir_name="cxbrew"
    brew_dir="$deps_dir/$brew_dir_name"
    ext_dir="$deps_dir/ext"

    for d in "$deps_dir" "$deps_dir/bin" "$deps_dir/lib" "$deps_dir/include" "$deps_dir/opt" "$deps_dir/share" "$deps_dl_dir" "$deps_scratch_dir" "$brew_dir" "$ext_dir"; do
        test -d "$d" || mkdir "$d" 2> /dev/null || exite "failed to create %s" "$d"
    done

    export PATH="$deps_dir/bin${PATH:+:$PATH}"
    export CPATH="$deps_dir/include${CPATH:+:$CPATH}"
    export LIBRARY_PATH="$deps_dir/lib${LIBRARY_PATH:+:$LIBRARY_PATH}"

    brew_default_prefix=
    if test $is_macos = 1; then
        # note: we only care about x86-64 here
        brew_default_prefix="/usr/local"
    else
        brew_default_prefix="/home/linuxbrew/.linuxbrew"
    fi

    # length must exactly match length of default platform prefix!
    tmp_prefix="/tmp/cx$(to_prec "$scratch_dir_inode" "$((${#brew_default_prefix} - 7))")"

    rm -f "$tmp_prefix" && ln -s "$deps_dir" "$tmp_prefix" || exite "failed to symlink %s to %s" "$tmp_prefix" "$deps_dir"
 
    tmp_prefix_file="$deps_dir/.tmp-prefix"
    if test ! -e "$tmp_prefix_file" || test "$tmp_prefix" != "$(cat "$tmp_prefix_file" 2> /dev/null || echo)"; then
        # re-link the files
        if test -e "$tmp_prefix_file"; then
            info "microbrew has been moved; re-patching binaries"
            for d in "$brew_dir"/*; do
                test "$d" != "$brew_dir/*" || test -e "$d" || continue

                LC_ALL=C find "$d" -type f -exec sh -e -c '
                    brew_default_prefix="$1"
                    tmp_prefix="$2"
                    tmp_write="$3"
                    shift 3
                    for f; do
                        sed -e "s%/tmp/cx[a-zA-Z0-9]\{$((${#brew_default_prefix} - 7))\}%$tmp_prefix%g" -- "$f" > "$tmp_write"
                        mv -f -- "$tmp_write" "$f"
                        if install_name_tool -id "$f" "$f" 2> /dev/null; then
                            codesign -f -s - "$f" 2> /dev/null
                        fi
                    done
                ' sh "$brew_default_prefix" "$tmp_prefix" "$deps_scratch_dir/.cxb-relink" {} +
            done
        fi
        echo "$tmp_prefix" > "$tmp_prefix_file"
    fi

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

    # shell json
    sh_json() {
        if test $is_macos = 1; then
            osj_da='Object.defineProperty(Array.prototype, "sh", { get: function() { return this.join(" "); } });'
            osj_parse='var data = JSON.parse($.NSProcessInfo.processInfo.environment.objectForKey("json").js);'
            json="$2" /usr/bin/osascript -l 'JavaScript' -e "$osj_da" -e "$osj_parse" \
                -e "var res = data$1; typeof res == 'string' ? res : res == null ? undefined : JSON.stringify(res)" 2> /dev/null
        else
            builtin_py="$(command -v python)" || builtin_py="$(command -v python3)" || \
                exite "cannot locate Python; please install Python to use the built-in dependency fetcher, or use --no-deps and install the Wine dependencies yourself"
            pyjd_dd='class dd(dict): __getattr__ = dict.get; __setattr__ = dict.__setitem__; __delattr__ = dict.__delitem__'
            pyjd_da="$(printf "class da(list):\n @property\n def length(self):\n  return len(self)\n @property\n def sh(self):\n  return ' '.join(str(v) for v in self)")"
            pyjd_conv='cv = lambda v: da([cv(a) for a in v]) if isinstance(v, list) else (dd({k:cv(a) for k, a in v.items()}) if isinstance(v, dict) else v)'
            pyj_decoder="$(printf "import os, json\n%s\n%s\n%s\ndata = cv(json.load(os.environ[\"json\"]))" "$pyjd_dd" "$pyjd_da" "$pyjd_conv")"
            json="$2" PYTHONIOENCODING=utf8 $builtin_py -c "$pyj_decoder; res = data$1; print(res if isinstance(res, str) else json.dumps(res)) if res is not None else None" 2> /dev/null
        fi
    }

    sys_info="x86_64_linux"
    build_sys_info="$sys_info"

    if test $is_macos = 1; then
        case "$(sw_vers -productVersion)" in
            14.*) sys_info="sonoma";;
            13.*) sys_info-"ventura";;
            12.*) sys_info="monterey";;
            *) sys_info="unknown";;
        esac

        if test $is_apple_silicon = 1; then
            build_sys_info="arm64_$sys_info"
        else
            build_sys_info="$sys_info"
        fi
    fi

    linkmerge() {
        for f in "$1"/*; do
            test "$f" != "$1/*" || test -e "$f" || continue

            tgt_name="${f#"$1/"}"
            prev_name="$2/$tgt_name"
            if test -d "$prev_name"; then
                test -d "$f" || exite "%s is not a directory" "$f"
                if test -L "$prev_name"; then
                    if test -d "$deps_scratch_dir/.cxb-link"; then
                        rm -f "$deps_scratch_dir/.cxb-link"/*
                    else
                        mkdir "$deps_scratch_dir/.cxb-link"
                    fi
                    old_link="$(get_link "$prev_name")"
                    new_link=
                    case "$old_link" in
                    /*) new_link="$old_link";;
                    *) new_link="../$old_link";;
                    esac

                    for f2 in "$prev_name"/*; do
                        test "$f2" != "$prev_name/*" || test -e "$f2" || continue

                        ln -s "$new_link${f2#"$prev_name"}" "$deps_scratch_dir/.cxb-link"
                    done

                    rm "$prev_name"
                    # TODO: things could break if interrupted between the rm and mv
                    mv "$deps_scratch_dir/.cxb-link" "$prev_name"
                fi
                new_dst_link=
                case "$3" in
                /*) new_dst_link="$3";;
                *) new_dst_link="../$3";;
                esac
                linkmerge "$f" "$prev_name" "$new_dst_link/$tgt_name"
            else
                rm -f "$prev_name" && ln -s "$3/$tgt_name" "$prev_name" || exite "could not symlink %s to %s" "$3/$tgt_name" "$prev_name"
            fi
        done
    }

    # microbrew - uses the Homebrew API to fetch prebuilt bottles
    # TODO: support multiple architectures (i.e. consider $build_sys_info for build-time dependencies)
    microbrew() {
        if test -d "$brew_dir/$1"; then
            info "package %s already installed; skipping" "$1"
            return
        fi

        info "downloading info for %s..." "$1"
        info_url="https://formulae.brew.sh/api/formula/$1.json"
        info_json="$(curl -s "$info_url")"

        info_bottle="$(sh_json .bottle.stable "$info_json")"
        test -z "$info_bottle" && exite "failed to load bottle info for %s" "$1"
        
        info_bottle_arch="$(sh_json ".files.$sys_info" "$info_bottle")"
        if test -z "$info_bottle_arch"; then
            info_bottle_arch="$(sh_json ".files.all" "$info_bottle")"
        fi
        test -z "$info_bottle_arch" && exite "failed to load bottle info for %s, system type %s" "$1" "$sys_info"

        info_bottle_url="$(sh_json ".url" "$info_bottle_arch")"
        info_bottle_sha="$(sh_json ".sha256" "$info_bottle_arch")"

        info "fetching %s from %s (sha = %s)" "$1" "$info_bottle_url" "$info_bottle_sha"
        key_info "downloading %s..." "$1"

        curl_extra_opts="-s"
        if test $verbose = 1; then
            curl_extra_opts="-#"
        fi

        if curl $curl_extra_opts -g -H "Authorization: Bearer QQ==" -L  -o "$deps_dl_dir/$info_bottle_sha" -C - "$info_bottle_url"; then
            info "download %s successful; extracting" "$1"
        else
            exite "failed to download %s from %s" "$1" "$info_bottle_url"
        fi

        if tar -zxf "$deps_dl_dir/$info_bottle_sha" -C "$deps_scratch_dir"; then
            info "extracting %s successful" "$1"
        else
            exite "failed to extract %s from %s to %s" "$1" "$deps_dl_dir/$info_bottle_sha" "$deps_scratch_dir"
        fi
        
        key_info "patching %s..." "$1"
        progress_file="$deps_scratch_dir/.patch-progress"
        LC_ALL=C find "$deps_scratch_dir/$1" -type f -exec sh -e -c '
            brew_default_prefix="$1"
            tmp_prefix="$2"
            tmp_write="$3"
            brew_dir_name="$4"
            deps_scratch_dir="$5"
            progress_file="$6"
            shift 6

            num_f="$(cat "$progress_file" 2> /dev/null || echo 0)"

            # thanks posix
            get_perm() {
                base_perm="$(ls -ld -- "$1" | cut -d " " -f 1)"
                base_perm="${base_perm#?}"
                perm_s=""

                for p in o g e; do
                    perm_c=
                    case "$(printf %.3s "$base_perm")" in
                        ---) perm_c=0;;
                        --?) perm_c=1;;
                        -w-) perm_c=2;;
                        -w?) perm_c=3;;
                        r--) perm_c=4;;
                        r-?) perm_c=5;;
                        rw-) perm_c=6;;
                        rw?) perm_c=7;;
                    esac
                    perm_s="$perm_s$perm_c"
                    base_perm="${base_perm#???}"
                done

                echo "$perm_s"
            }

            for f; do
                num_f="$(($num_f + 1))"
                case "$num_f" in
                *000) printf "%i files... " "$num_f" 1>&2;;
                esac

                # common case: no processing needed
                f_patch=0
                if grep -q -F -e "@@HOMEBREW" -e "$brew_default_prefix" "$f"; then
                    f_patch=1
                fi
                f_rel="${f#"$deps_scratch_dir"}"

                if test $f_patch = 0; then
                    if file "$f" | grep -q -F "Mach-O"; then
                        if install_name_tool -id "$tmp_prefix/$brew_dir_name$f_rel" "$f" 2> /dev/null; then
                            f_perm=$(get_perm "$f")
                            chmod 644 "$f"
                            codesign -f -s - "$f" 2> /dev/null
                            chmod "$f_perm" "$f"
                        fi
                    fi
                else
                    f_perm=$(get_perm "$f")
                    sed -e "s%$brew_default_prefix/Cellar%$tmp_prefix/$brew_dir_name%g" -e "s%$brew_default_prefix%$tmp_prefix%g" -- "$f" > "$tmp_write"

                    # TODO: support linux
                    need_sign=0
                    if install_name_tool -id "$tmp_prefix/$brew_dir_name$f_rel" "$tmp_write" 2> /dev/null; then
                        need_sign=1
                        f_names=$(otool -L "$f" | grep -F "@@HOMEBREW" | awk '\''
                            /@@HOMEBREW_CELLAR@@/ || /@@HOMEBREW_PREFIX@@/ {
                                ORS=" "
                                a=$1
                                gsub("@@HOMEBREW_CELLAR@@", "'\''"$tmp_prefix/$brew_dir_name"'\''", $1)
                                gsub("@@HOMEBREW_PREFIX@@", "'\''"$tmp_prefix"'\''", $1)
                                print "-change", a, $1
                            }
                        '\'')
                        if test -n "$f_names"; then
                            install_name_tool $f_names "$tmp_write"
                        fi
                    fi
                    # todo: what if directory is not writable?
                    case "$(file "$tmp_write")" in
                    *text*)
                        rm -f "$f"
                        sed -e "s%@@HOMEBREW_CELLAR@@%$tmp_prefix/$brew_dir_name%g" -e "s%@@HOMEBREW_PREFIX@@%$tmp_prefix%g" -e "s%@@HOMEBREW_PERL@@%/usr/bin/perl%g" "$tmp_write" > "$f"
                        rm "$tmp_write"
                        chmod "$f_perm" "$f";;
                    *) mv -f "$tmp_write" "$f"; chmod "$f_perm" "$f";;
                    esac

                    if test $need_sign = 1; then
                        codesign -f -s - "$f" 2> /dev/null
                    fi
                fi
            done
            echo "$num_f" > "$progress_file"
        ' sh "$brew_default_prefix" "$tmp_prefix" "$deps_scratch_dir/.cxb-relink" "$brew_dir_name" "$deps_scratch_dir" "$progress_file" {} +
        
        num_f="$(cat "$progress_file" 2> /dev/null || echo 0)"
        rm -f "$progress_file"
        if test "$num_f" -ge 1000; then
            echo "patched $num_f files"
        fi

        info "successfully patched %s: %i files" "$1" "$num_f"

        info_deps="$(sh_json .dependencies.sh "$info_json")"
        
        if test -n "$info_deps"; then
            info "%s depends on: %s" "$1" "$info_deps"
        fi

        for d in $info_deps; do
            microbrew "$d"
        done
        
        dep_ver="$(ls "$deps_scratch_dir/$1")"

        info "linking %s into %s" "$1" "$deps_dir"
        # TODO: use the metadata from Homebrew for this
        for td in bin lib include share; do
            if test -d "$deps_scratch_dir/$1/$dep_ver/$td"; then
                linkmerge "$deps_scratch_dir/$1/$dep_ver/$td" "$deps_dir/$td" "../$brew_dir_name/$1/$dep_ver/$td"
            fi
        done

        rm -f "$deps_dir/opt/$1" && ln -s "../$brew_dir_name/$1/$dep_ver" "$deps_dir/opt/$1"

        mv "$deps_scratch_dir/$1" "$brew_dir/$1"
    }
    
    if test -n "$missing_brew_deps"; then
        key_info "missing Wine dependencies; installing with built-in dependency fetcher"

        for d in $missing_brew_deps; do
            microbrew "$d"
        done
    fi

    libinkq_dir="$ext_dir/libinotify-kqueue"

    if test $is_macos = 1 && test ! -d "$libinkq_dir"; then
        key_info "missing libinotify-kqueue; building from source"

        microbrew "automake"
        microbrew "libtool"

        key_info "downloading libinotify-kqueue sources..."
        libinkq_url="https://api.github.com/repos/libinotify-kqueue/libinotify-kqueue/tarball/master"

        libinkq_build_dir="$deps_scratch_dir/libinotify-kqueue"
        test -d "$libinkq_build_dir" || mkdir "$libinkq_build_dir" || exite "failed to create %s" "$libinkq_build_dir"

        if curl -s -L "$libinkq_url" | tar -zx --strip-components=1 -C "$libinkq_build_dir"; then
            info "download + extract libinotify-kqueue sources successful"
            key_info "building libinotify-kqueue..."

            rm -f "$libinkq_build_dir/.cxb-success"
            info "libinotify-kqueue build log:"
            (
                cd "$libinkq_build_dir" && autoreconf -fvi 2>&1 && \
                CFLAGS="${CFLAGS:+$CFLAGS }-target x86_64-apple-macos -arch x86_64" ./configure --prefix="$tmp_prefix" 2>&1 && make clean 2>&1 && \
                make -j$build_ncpu 2>&1 && make install prefix="/" DESTDIR="$libinkq_dir" 2>&1 && touch "$libinkq_build_dir/.cxb-success"
            ) | extinfo
            if test -f "$libinkq_build_dir/.cxb-success"; then
                rm -rf "$libinkq_build_dir"
            else
                exite "failed to build libinotify-kqueue"
            fi

            for td in lib include share; do
                linkmerge "$libinkq_dir/$td" "$deps_dir/$td" "../ext/libinotify-kqueue/$td"
            done
            key_info "libinotify-kqueue built successfully"
        else
            exite "failed to download and extract libinotify-kqueue sources from %s" "$libinkq_url"
        fi
    fi

    macos_pkgconfig_dir="$ext_dir/macos-pkgconfig"
    if test $is_macos = 1; then
        if test ! -d "$macos_pkgconfig_dir"; then
            key_info "missing pkgconfig files for macOS builtins; downloading from Homebrew"

            macos_pkgconfig_fetch_dir="$deps_scratch_dir/macos-pkgconfig"

            test -d "$macos_pkgconfig_fetch_dir" || mkdir "$macos_pkgconfig_fetch_dir" || exite "failed to create %s" "$macos_pkgconfig_fetch_dir"
            macos_pkgconfig_url="https://github.com/Homebrew/brew/tarball/master"

            curl -s -L "$macos_pkgconfig_url" | tar -zx --strip-components=6 -C "$macos_pkgconfig_fetch_dir" '*/Library/Homebrew/os/mac/pkgconfig' 2> /dev/null || \
                exite "failed to download pkgcconfig files for macOS builtins"

            mv "$macos_pkgconfig_fetch_dir" "$macos_pkgconfig_dir"
        fi

        macos_ver="$(sw_vers -productVersion)"
        case "$macos_ver" in
            10.*)macos_subver="${macos_ver#*.}"; macos_ver="${macos_ver%%.*}.${macos_subver%%.*}";;
            *) macos_ver="${macos_ver%%.*}";;
        esac

        export PKG_CONFIG_PATH="$tmp_prefix/lib/pkgconfig:$tmp_prefix/share/pkgconfig:$macos_pkgconfig_dir/$macos_ver${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    fi
else
    info "--no-deps specified; assuming dependencies are already available"
fi

key_info "dependencies located; starting build"

ld_rel_name=
if test $is_macos = 1; then
    ld_rel_name='@loader_path'
else
    ld_rel_name='$ORIGIN'
fi

wine_conf_dir="$scratch_dir/wine"
wine_link_dir="$wine_conf_dir/src"
wine_build_dir="$wine_conf_dir/build"
wine_dist_dir="$wine_conf_dir/dist"
wine_include_dir="$wine_build_dir/include"

build_wine() {
    # TODO: make non-macOS specific
    wineconf_args="--disable-option-checking --disable-tests --enable-archs=i386,x86_64 --without-alsa \
    --without-capi --with-coreaudio --with-cups --without-dbus --without-fontconfig --with-freetype \
    --with-gettext --without-gettextpo --without-gphoto --with-gnutls --without-gssapi --with-gstreamer \
    --with-inotify --without-krb5 --with-mingw  --without-netapi --with-opencl --with-opengl --without-oss \
    --with-pcap --with-pcsclite --with-pthread --without-pulse --without-sane --with-sdl --without-udev \
    --with-unwind --without-usb --without-v4l2 --with-vulkan --without-wayland --without-x $CXB_CONF_ARGS"

    for d in "$wine_conf_dir" "$wine_build_dir" "$wine_include_dir"; do
        if test ! -d "$d"; then
            mkdir "$d" || exite "failed to create %s" "$d"
        fi
    done

    rm -f "$wine_link_dir" && ln -s "$wine_dir" "$wine_link_dir" || exite "failed to symlink %s to %s" "$wine_dir" "$wine_link_dir"

    if test ! -f "$wine_include_dir/distversion.h"; then
        printf '%s%s\n%s%s%s\n' \
            '#define WINDEBUG_WHAT_HAPPENED_MESSAGE "This can be caused by a problem in the program or a deficiency in Wine. ' \
            'You may want to check <a href=\"http://www.codeweavers.com/compatibility/\">http://www.codeweavers.com/compatibility/</a> for tips about running this application."' \
            '#define WINDEBUG_USER_SUGGESTION_MESSAGE "If this problem is not present under Windows and has not been reported yet, ' \
            'you can save the detailed information to a file using the \"Save As\" button, then <a href=\"http://www.codeweavers.com/support/tickets/enter/\">file a bug report</a> ' \
            'and attach that file to the report."' \
        > "$wine_include_dir/distversion.h"
    fi

    cd "$wine_build_dir"

    export CFLAGS="-Wno-deprecated-declarations -Wno-incompatible-pointer-types${CFLAGS:+ $CFLAGS}"
    export LDFLAGS="-Wl,-ld_classic -Wl,-headerpad_max_install_names -Wl,-rpath,$ld_rel_name/../..${LDFLAGS:+ $LDFLAGS}"

    key_info "configuring Wine..."
    if test -f "Makefile" && test $rebuild_wine = 0; then
        info "found previous build; reusing configured results"
    else
        if test -f "Makefile"; then
            info "found previous build; cleaning"
            if test $is_interactive = 1; then
                prompt_continue "Found existing Wine build. Clean and continue?"
            fi
            (make clean && touch ".cxb-success") | extinfo
            if test -f ".cxb-success"; then
                info "successfully cleaned previous build"
                rm ".cxb-success"
            else
                exite "failed to clean previous build"
            fi
            
            rm "Makefile"
        fi
        
        # makedep expects distversion.h in parent directory for some reason
        rm -f "$wine_conf_dir/distversion.h" && ln -s "build/include/distversion.h" "$wine_conf_dir/distversion.h" || exite "failed to symlink distversion.h"

        if test $is_apple_silicon = 1; then
            (arch -x86_64 ../src/configure $wineconf_args --prefix="$tmp_prefix" --verbose 2>&1 && touch ".cxb-success") | extinfo
        else
            (../src/configure $wineconf_args --prefix="$tmp_prefix" 2>&1 && touch ".cxb-success") | extinfo
        fi
        
        test -f ".cxb-success" && rm ".cxb-success" || exite "failed to configure Wine"
    fi

    key_info "building Wine... (this can take a while)"
    if test $is_apple_silicon = 1; then
        (arch -x86_64 make -j$build_ncpu 2>&1 && touch ".cxb-success") | tee ".cxb-build-debug" | extinfo
    else
        (make -j$build_ncpu 2>&1 && touch ".cxb-success") | tee ".cxb-build-debug" | extinfo
    fi
    test -f ".cxb-success" && rm ".cxb-success" || exite "failed to build Wine"

    if test ! -d "$wine_dist_dir" || test "$(tail -n 2 ".cxb-build-debug")" != "Wine build complete."; then
        info "installing Wine to %s" "$wine_dist_dir"

        rm -rf "$wine_dist_dir"
        if test $is_apple_silicon = 1; then
            (arch -x86_64 make -j$build_ncpu install-lib prefix="/" DESTDIR="$wine_dist_dir" 2>&1 && touch ".cxb-success") | extinfo
        else
            (make -j$build_ncpu install-lib prefix="/" DESTDIR="$wine_dist_dir" 2>&1 && touch ".cxb-success") | extinfo
        fi
        test -f ".cxb-success" && rm ".cxb-success" || exite "failed to build Wine"
    else
        info "no updates to Wine; no need to reinstall"
    fi
    rm ".cxb-build-debug"

    key_info "Wine built successfully"
}

(build_wine)

key_info "packaging..."

info "copying Wine distribution"
test -d "$dst_dir" || mkdir -p "$dst_dir" || exite "failed to create %s" "$dst_dir"
for d in bin lib share; do
    test -d "$dst_dir/$d" || mkdir "$dst_dir/$d" || exite "failed to create %s" "$dst_dir/$d"
    cp -R -p -P -f "$wine_dist_dir/$d"/* "$dst_dir/$d" || exite "failed to write to %s" "$dst_dir/$d"
done

char_nl='
'
echo "int main(){}" > "$scratch_dir/.cxb-conf.c"
# TODO: is there a built-in way to do this?
# this has issues with newlines in filepaths, etc.
ld_search_paths=
if ld_verbose_out="$("$CC" -Xlinker --verbose -o /dev/null "$scratch_dir/.cxb-conf.c" 2> /dev/null)" && echo "$ld_verbose_out" | grep -q -F "SEARCH_DIR"; then
    # gnu linker
    esc_ld_search_paths="$(echo "$ld_verbose_out" | sed -n 's/SEARCH_DIR("=\?\([^"]\+\)"); */\1\n/gp')"
    IFS="$char_nl"
    for f in $esc_ld_search_paths; do
        ld_search_paths="${ld_search_paths:+$ld_search_paths:}$(printf "%b" "$f")"
    done
    reset_ifs
elif test $is_macos = 1 && ld_verbose_out="$("$CC" -Xlinker -v -o /dev/null "$scratch_dir/.cxb-conf.c" 2>&1)" && echo "$ld_verbose_out" | grep -q -F "Library search paths:"; then
    # clang linker on macOS
    ld_verbose_out="${ld_verbose_out##?*Library search paths:?}"
    ld_verbose_out="${ld_verbose_out%%?Framework search paths?*}"
    esc_ld_search_paths="$(echo "$ld_verbose_out" | sed -e 's/^	//g')"
    IFS="$char_nl"
    # TODO: not sure if this is right
    for f in $esc_ld_search_paths; do
        ld_search_paths="${ld_search_paths:+$ld_search_paths:}$(printf "%b" "$f")"
    done
    reset_ifs
else
    # best effort based on LIBRARY_PATH and LDFLAGS
    load_ldflags() {
        while test $# != 0; do
            case "$1" in
            -L) shift; ld_search_paths="${ld_search_paths:+$ld_search_paths:}$1";;
            -L*) ld_search_paths="${ld_search_paths:+$ld_search_paths:}${1#??}";;
            esac
            shift
        done
    }
    load_ldflags $LDFLAGS
    if test -n "$LIBRARY_PATH"; then
        ld_search_paths="${ld_search_paths:+$ld_search_paths:}$LIBRARY_PATH"
    fi
fi
rm "$scratch_dir/.cxb-conf.c"

# TODO: is this correct?
if test $is_macos = 1; then
    ld_search_paths="${ld_search_paths:+$ld_search_paths:}/usr/local/lib:/usr/lib"
fi

rtdeps_dir="$scratch_dir/rtdeps"
test -d "$rtdeps_dir" || mkdir "$rtdeps_dir" || exite "failed to create %s" "$rtdeps_dir"

info "finding required libraries..."
needed_libs_esc="$("$CC" -dM -E "$wine_include_dir/config.h" 2> /dev/null | sed -n -e 's/^#define SONAME_[^ ]* "\(.*\)"$/\1/gp')"
needed_libs=
IFS="$char_nl"
for f in $needed_libs_esc; do
    needed_libs="${needed_libs:+$needed_libs:}$(printf "%b" "$f")"
done

IFS=":"
wine_dyn_dir="$wine_dist_dir/lib/wine/x86_64-unix:$wine_dist_dir/bin"

load_dynamic_deps() {
    # TODO: handle rpaths properly
    if test $is_macos = 1; then
        dynamic_libs="$(otool -L "$1" | grep -v -F "$(basename "$1")" | sed -n -e 's/^\t\([^ ]*\) (compatibility.*$/\1/gp')"
    else
        readelf_bin="$(command -v readelf)" || exite "cannot locate readelf; please install readelf to build the final package"

        dynamic_libs="$("$readelf_bin" -d "$1" | sed -n -e 's/^.*(NEEDED).*\[\(.*\)\]\s*$/\1/p')"
    fi
    printf '%s' "$dynamic_libs" | tr '\n' ':'
}

ld_find() {
    for dir in $ld_search_paths; do
        if test -n "$dir" && test -f "$dir/$1"; then
            echo "$dir/$1"
            return
        fi
    done
}

locate_lib() {
    lib_name="$(basename "$1")"

    for d in "$rtdeps_dir" $wine_dyn_dir; do
        if test -f "$d/$lib_name"; then
            return
        fi
    done

    # detect system libraries
    # probably unnecessary to copy these
    case "$1" in
    /System/*|/usr/lib/*|*/MacOSX*.sdk/*) return;;
    esac

    # special-case libraries
    case "$lib_name" in
    libc.*|libc++.*|libstdc++.*|libcups.*|libodbc.*) return;;
    esac

    found_lib=

    if test -f "$1"; then
        found_lib="$1"
    else
        found_lib="$(ld_find "$lib_name")"
    fi

    test -n "$found_lib" || exite "failed to locate %s; please add the directory in which it is contained to your \$LIBRARY_PATH" "$lib_name"

    # need to store in positional parameters; other variables will be overwritten
    set -- "$found_lib"

    for f in $(load_dynamic_deps "$found_lib"); do
        locate_lib "$f"
    done

    while test -L "$1"; do
        rel_name="$(basename "$1")"
        link_target="$(get_link "$1")"
        link_target_name="$(basename "$link_target")"

        if test -f "$rtdeps_dir/$rel_name"; then
            return
        fi

        if test "$link_target_name" != "$rel_name"; then
            ln -s "$(basename "$link_target")" "$rtdeps_dir/$rel_name"
        fi
        set -- "$(cd "$(dirname "$1")" && echo "$(abspath "$link_target")")"
    done
    
    rel_name="$(basename "$1")"
    if test ! -f "$rtdeps_dir/$rel_name"; then
        cp "$1" "$rtdeps_dir/$rel_name"
    fi
}

info "locating dependencies..."

# locate all dynamically linked libraries loaded directly
for d in $wine_dyn_dir; do
    for f in "$d"/*; do
        for l in $(load_dynamic_deps "$f"); do
            locate_lib "$l"
        done
    done
done

# locate all dynamically linked libraries loaded indirectly
for l in $needed_libs; do
    locate_lib "$l"
done

# any libraries that cannot easily be found statically (mostly gstreamer related) here

# gstreamer finds these plugins by finding its own location and entering the gstreamer-1.0 subdirectory
# gstreamer finds its own location using dladdr()
# ref: https://github.com/GStreamer/gstreamer/blob/d68ac0db571f44cae42b57c876436b3b09df616b/subprojects/gstreamer/gst/gstregistry.c#L1599-L1638
gstreamer_libs="libgstasf:libgstaudioconvert:libgstaudioparsers:libgstaudioresample:libgstavi:libgstcoreelements:libgstdebug:libgstdeinterlace:libgstid3demux:libgstisomp4:libgstopengl:libgstplayback:libgsttypefindfunctions:libgstvideoconvertscale:libgstvideofilter:libgstvideoparsersbad:libgstwavparse"
if test $is_macos = 1; then
    # we can avoid pulling in ffmpeg on mac
    gstreamer_libs="${gstreamer_libs:+$gstreamer_libs:}libgstapplemedia"
else
    gstreamer_libs="${gstreamer_libs:+$gstreamer_libs:}libgstlibav"
fi

dl_ext=
if test $is_macos = 1; then
    dl_ext=".dylib"
else
    dl_ext=".so"
fi

test -d "$rtdeps_dir/gstreamer-1.0" || mkdir "$rtdeps_dir/gstreamer-1.0" || exite "failed to create %s" "$rtdeps_dir/gstreamer-1.0"

for gst_lib_name in $gstreamer_libs; do
    gst_lib="$(ld_find "gstreamer-1.0/$gst_lib_name$dl_ext")"
    test -n "$gst_lib" || exite "could not locate gstreamer plugin %s" "$gst_lib_name"

    for f in $(load_dynamic_deps "$gst_lib"); do
        locate_lib "$f"
    done
    
    if test ! -f "$rtdeps_dir/gstreamer-1.0/$gst_lib_name$dl_ext"; then
        cp "$gst_lib" "$rtdeps_dir/gstreamer-1.0/$gst_lib_name$dl_ext"
    fi
done

find_rpaths() {
    all_rpaths="$(otool -l "$1" | awk '
        $1 == "Load" && $2 == "command" { r = 0 }
        $1 == "cmd" && $2 == "LC_RPATH" { r = 1 }
        r && $1 == "path" { print $2 }
    ')"
    printf '%s' "$all_rpaths" | tr '\n' ':'
}

patch_lib() {
    l="$1"
    rel="$2"
    brel="$3"
    l_name="$(basename "$l")"

    if test $is_macos = 1; then
        install_name_tool -id "@rpath/$rel$l_name" "$l" 2> /dev/null || exite "failed to update id for %s" "$l"
        find_rpaths "$l" | tr ':' '\n' | grep -q -e "^@loader_path/$" || \
            install_name_tool -add_rpath "@loader_path/" "$l" 2> /dev/null || exite "failed to update rpath for %s" "$l"

        name_changes=
        for dep in $(load_dynamic_deps "$l"); do
            dep_base="$(basename "$dep")"
            if test -f "$rtdeps_dir/$dep_base"; then
                name_changes="${name_changes:+$name_changes:}-change:$dep:@rpath/$brel$dep_base"
            elif test -f "$rtdeps_dir/$rel$dep_base"; then
                name_changes="${name_changes:+$name_changes:}-change:$dep:@rpath/$dep_base"
            fi
        done

        if test -n "$name_changes"; then
            install_name_tool $name_changes "$l" 2> /dev/null || exite "failed to patch libraries for %s" "$l"
        fi
        codesign -f -s - "$l" 2> /dev/null || exite "failed to codesign %s" "$l"
    else
        # TODO: figure out how to patch the rpath
        warn "could not patch rpath for %s; ELF patching on linux is unimplemented" "$l"
    fi
}

info "patching runtime dependencies..."
for l in "$rtdeps_dir"/*; do
    if test ! -f "$l"; then
        continue
    fi

    if test -L "$l"; then
        cp -P -f "$l" "$dst_dir/lib"
        continue
    fi

    patch_lib "$l"
    
    # note: $l is technically clobbered by patch_lib but it's the same value, so OK
    cp -f "$l" "$dst_dir/lib"
done

test -d "$dst_dir/lib/gstreamer-1.0" || mkdir "$dst_dir/lib/gstreamer-1.0" || exite "failed to create %s" "$dst_dir/lib/gstreamer-1.0"

info "patching gstreamer plugins..."
for l in "$rtdeps_dir/gstreamer-1.0"/*; do
    patch_lib "$l" "gstreamer-1.0/" "../"

    cp -f "$l" "$dst_dir/lib/gstreamer-1.0"
done

info "patching Wine libraries..."
for l in "$dst_dir/lib/wine/x86_64-unix"/*; do
    patch_lib "$l" "wine/x86_64-unix/" "../../"
done

for l in "$dst_dir/bin"/*; do
    patch_lib "$l" "../bin/" "../lib/"

    if test $is_macos = 1; then
        name_changes=
        for rpath in $(find_rpaths "$l"); do
            if test "$rpath" = "@loader_path/../.."; then
                name_changes="${name_changes:+$name_changes:}-delete_rpath:$rpath"
            fi
        done

        if test -n "$name_changes"; then
            install_name_tool $name_changes "$l" 2> /dev/null || exite "could not clear bad rpaths from %s" "$l"
        fi
        codesign -f -s - "$l" 2> /dev/null || exite "failed to codesign %s" "$l"
    else
        warn "could not patch rpath for %s; ELF patching on linux is unimplemented" "$l"
    fi
done

reset_ifs
info "base Wine built successfully"

if test $use_dxvk = 1; then
    info "patching in DXVK"
    for d in "dxvk" "dxvk/i386-windows" "dxvk/x86_64-windows"; do
        test -d "$dst_dir/lib/$d" || mkdir "$dst_dir/lib/$d" || exite "failed to create %s" "$dst_dir/lib/$d"
    done
    test -z "$(ls "$dxvk_dir/x32")" || cp -p -f "$dxvk_dir/x32"/* "$dst_dir/lib/dxvk/i386-windows"
    test -z "$(ls "$dxvk_dir/x64")" || cp -p -f "$dxvk_dir/x64"/* "$dst_dir/lib/dxvk/x86_64-windows"

    # Patch signatures to prevent Wine from ignoring these DLLs
    for d in i386-windows x86_64-windows; do
        for f in "$dst_dir/lib/dxvk/$d"/*; do
            if test ! -f "$f"; then
                continue
            fi
            (dd if="$f" ibs=32 count=2 2> /dev/null && printf 'Wine builtin DLL\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0' && \
                dd if="$f" ibs=32 skip=3 2> /dev/null) > "$scratch_dir/.cxb-resig"
            mv -f "$scratch_dir/.cxb-resig" "$f"
        done
    done

    dxvk_targets="i386-windows"
    if test $use_gptk != 1; then
        dxvk_targets="$dxvk_targets x86_64-windows"
    fi

    for d in $dxvk_targets; do
        for f in "$dst_dir/lib/dxvk/$d"/*; do
            test "$f" != "$dst_dir/lib/dxvk/$d/*" || test -e "$f" || continue
            f_name="$(basename "$f")"

            # TODO: correctness on Linux
            if test $is_macos = 1 && test "$f_name" = "dxgi.dll" || test "$f_name" = "dx9.dll"; then
                continue
            fi

            if test -e "$dst_dir/lib/wine/$d/$f_name"; then
                mv -f "$dst_dir/lib/wine/$d/$f_name" "$dst_dir/lib/wine/$d/$f_name.wined3d"
            fi
            ln -s "../../dxvk/$d/$f_name" "$dst_dir/lib/wine/$d/$f_name" || exite "failed to symlink DXVK DLLs into Wine"
        done
    done
fi

if test $use_gptk = 1; then
    info "patching in GPTk"
    for d in "gptk" "gptk/x86_64-unix" "gptk/x86_64-windows"; do
        test -d "$dst_dir/lib/$d" || mkdir "$dst_dir/lib/$d" || exite "failed to create %s" "$dst_dir/lib/$d"
    done

    cp -R -p -P -f "$gptk_dir/redist/lib/external"/* "$dst_dir/lib/gptk/x86_64-unix"
    cp -p -f "$gptk_dir/redist/lib/wine/x86_64-windows"/* "$dst_dir/lib/gptk/x86_64-windows"
    
    for f in "$dst_dir/lib/gptk/x86_64-windows"/*; do
        f_name="$(basename "$f")"

        if test "$f_name" = "d3d9.dll"; then
            continue
        fi

        if test -e "$dst_dir/lib/wine/x86_64-windows/$f_name"; then
            mv -f "$dst_dir/lib/wine/x86_64-windows/$f_name" "$dst_dir/lib/wine/x86_64-windows/$f_name.wined3d"
        fi

        ln -s "../../gptk/x86_64-windows/$f_name" "$dst_dir/lib/wine/x86_64-windows/$f_name" || exite "failed to symlink GPTk DLLs into Wine"
    done

    for f in "$gptk_dir/redist/lib/wine/x86_64-unix"/*; do
        f_name="$(basename "$f")"

        if test "$f_name" = "d3d9.so"; then
            continue
        fi

        if test -e "$dst_dir/lib/wine/x86_64-unix/$f_name"; then
            mv -f "$dst_dir/lib/wine/x86_64-unix/$f_name" "$dst_dir/lib/wine/x86_64-unix/$f_name.wined3d"
        fi
        
        ln -s "../../gptk/x86_64-unix/libd3dshared.dylib" "$dst_dir/lib/wine/x86_64-unix/$f_name" || exite "failed to symlink GPTk dylibs into Wine"
    done
fi

key_info "Build complete in %s" "$dst_dir"

if test $post_clean = 1; then
    if post_cache_dir="$(mktemp -d 2> /dev/null)"; then
        info "created temp dir at %s" "$post_cache_dir"
        rmdir "$post_cache_dir"
    else
        post_cache_dir="/tmp/cxbsc$(to_prec "$(awk 'BEGIN {srand(); print srand()}')" 8)"
        info "could not use mktemp -d; trying cache dir at %s instead" "$post_cache_dir"
    fi

    # preserve inode if possible
    mv "$scratch_dir" "$post_cache_dir" || exite "failed to move CXBuilder cache to %s" "$post_cache_dir"

    info "Saved CXBuilder cache to %s" "$post_cache_dir"
    info "to reuse cache for future runs, run CXB_TEMP='%s' %s ..." "$post_cache_dir" "$0"
    info "alternatively: mv %s %s/.cxbuilder" "$post_cache_dir" "$dst_dir"
fi
