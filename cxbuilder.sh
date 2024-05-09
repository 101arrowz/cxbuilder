#!/bin/sh
#
# CXBuilder - build Wine from source with CrossOver patches
#

set -e

CXB_LOG_FILE="${CXB_LOG_FILE:-/dev/null}"
CXB_TEMP="${CXB_TEMP:-.cxbuilder}"

verbose=0
is_macos=0; test "$(uname -s)" = "Darwin" && is_macos=1
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
        
        eprint "\n"
    fi
}

fmt_lr() {
    fmt="$1$3$2"
    shift 3
    printf "$fmt" "$@"
}

eprint() { printf "%s" "$1" >&2; }
eprintn() { printf "%s" "$1" >&2; }
log_write() { printf "%s" "$1" >> "$CXB_LOG_FILE"; }

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
    eprintn "                         is well-tested and does not install anything globally"
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
    if test ! -z "$tmp_prefix"; then
        rm "$tmp_prefix"
    fi
    trap - EXIT
    exit
}

trap cleanup EXIT INT HUP TERM

echo "-- CXBuilder $(date '+%Y-%m-%d %H:%M:%S') --" > "$CXB_LOG_FILE"

if test $is_interactive = 0; then
    info "running non-interactively"
fi

if test $is_macos = 0; then
    warn "CXBuilder is only tested on macOS; expect things to break"
fi

is_apple_silicon=0
if test $is_macos = 1 && test "$(arch)" = "arm64"; then
    is_apple_silicon=1
    info "running on Apple Silicon"
else
    info "not an Apple Silicon device"
fi

if test -z $use_gptk; then
    info "gptk options unspecified; $(test $is_apple_silicon = 1 && echo "enabling by default on Apple Silicon" || echo "disabling by default (not on Applle Silicon)")"
    use_gptk=$is_apple_silicon
fi

if test $is_apple_silicon = 0 && test $use_gptk = 1 && test -z "$CXB_FORCE_GPTK"; then
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

if test -z "$use_dxvk"; then
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
            err "%s; could not locate $gptk_dir$p" "$gptk_err"
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
fi

if ! test -d "$scratch_dir"; then
    mkdir "$scratch_dir" 2> /dev/null || if tmp_build="$(mktemp -d 2> /dev/null)"; then
        scratch_dir="$tmp_build"
    else
        exite "failed to create CXBuilder tempdir $scratch_dir"
    fi
    info "successfully created $scratch_dir"
else
    info "located previous CXBuilder run in $scratch_dir"
fi

info "validation complete; starting build"

mvk_dir="$scratch_dir/molten-vk"
wine_build_dir="$scratch_dir/wine-build"

abspath() {
    if test -d "$1"; then
        echo "$(cd "$1" && pwd)"
    else
        echo "$(cd "$(dirname -- "$1")" && pwd)/$(basename "$1")"
    fi
}

get_inode() {
    ls -ldi -- "$1" | cut -d ' ' -f 1
}

to_prec() {
    out="$(printf "%.${2}x" "$1")"
    out_oversize="$((${#out} - $2 + 1))"
    echo "$out" | cut -c "$out_oversize-"
}

if test $fetch_deps = 1; then
    for cmd in curl tar; do
        command -v $cmd > /dev/null || exite "cannot locate $cmd; please install $cmd to use the built-in dependency fetcher, or use --no-deps and install the Wine dependencies yourself"
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
        test -d "$d" || mkdir "$d" 2> /dev/null || exite "failed to create $d"
    done

    abs_deps_dir="$(abspath "$deps_dir")"

    export PATH="$abs_deps_dir/bin:${PATH:+:$PATH}"
    export CPATH="$abs_deps_dir/include${CPATH:+:$CPATH}"
    export LIBRARY_PATH="$abs_deps_dir/lib:${LIBRARY_PATH:+:$LIBRARY_PATH}"

    scratch_dir_inode="$(get_inode "$scratch_dir")"
    brew_default_prefix=
    if test $is_macos = 1; then
        # note: we only care about x86-64 here
        brew_default_prefix="/usr/local"
    else
        brew_default_prefix="/home/linuxbrew/.linuxbrew"
    fi

    # length must exactly match length of default platform prefix!
    tmp_prefix="/tmp/cx$(to_prec "$scratch_dir_inode" "$((${#brew_default_prefix} - 7))")"

    rm -f "$tmp_prefix" && ln -s "$abs_deps_dir" "$tmp_prefix" || exite "failed to symlink $tmp_prefix to $abs_deps_dir"
 
    tmp_prefix_file="$deps_dir/.tmp-prefix"
    if test ! -e "$tmp_prefix_file" || test "$tmp_prefix" != "$(cat "$tmp_prefix_file" 2> /dev/null || echo)"; then
        # re-link the files
        info "microbrew has been moved; re-patching binaries"
        for d in "$brew_dir"*; do
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
        echo "$tmp_prefix" > "$tmp_prefix_file"
    fi

    brew_build_deps="bison:pkg-config:mingw-w64"
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
            json="$2" /usr/bin/osascript -l 'JavaScript' -e "$osj_da" -e "$osj_parse" -e "var res = data$1; typeof res == 'string' ? res : res == null ? undefined : JSON.stringify(res)" 2> /dev/null
        else
            builtin_py="$(command -v python)" || builtin_py="$(command -v python3)" || \
                exite "cannot locate Python; please install Python to use the built-in dependency fetcher, or use --no-deps and install the Wine dependencies yourself"
            pyjd_dd='class dd(dict): __getattr__ = dict.get; __setattr__ = dict.__setitem__; __delattr__ = dict.__delitem__'
            pyjd_da="$(printf "class da(list):\n @property\n def length(self):\n  return len(self)\n @property\n def sh(self):\n  return ' '.join(str(v) for v in self)")"
            pyjd_conv='cv = lambda v: da([cv(a) for a in v]) if isinstance(v, list) else (dd({k:cv(a) for k, a in v.items()}) if isinstance(v, dict) else v)'
            pyj_decoder="$(printf "import os, json\n$pyjd_dd\n$pyjd_da\n$pyjd_conv\ndata = cv(json.load(os.environ[\"json\"]))")"
            json="$2" PYTHONIOENCODING=utf8 $builtin_py -c "$pyj_decoder; res = data$1; print(res if isinstance(res, str) else json.dumps(res)) if res is not None else None" 2> /dev/null
        fi
    }

    sys_info="x86_64_linux"
    build_sys_info="$sys_info"

    if test $is_macos = 1; then
        case "$(/usr/bin/sw_vers -productVersion)" in
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

    get_link() {
        # TODO: breaks if you have -> in username
        # at that point you had it coming though
        ls -l -- "$1" | awk -F " -> " '{print $2}'
    }

    linkmerge() {
        for f in "$1"/*; do
            tgt_name="${f#"$1/"}"
            prev_name="$2/$tgt_name"
            if test -d "$prev_name"; then
                test -d "$f" || exite "$f is not a directory"
                if test -L "$prev_name"; then
                    if test -d "$deps_scratch_dir/.cxb-link"; then
                        rm "$deps_scratch_dir/.cxb-link"/*
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
                rm -f "$prev_name" && ln -s "$3/$tgt_name" "$prev_name" || exite "could not symlink $3/$tgt_name to $prev_name"
            fi
        done
    }

    # microbrew - uses the Homebrew API to fetch prebuilt bottles
    # TODO: support multiple architectures (i.e. consider $build_sys_info for build-time dependencies)
    microbrew() {
        if test -d "$brew_dir/$1"; then
            info "package $1 already installed; skipping"
            return
        fi

        info_url="https://formulae.brew.sh/api/formula/$1.json"
        info_json="$(curl -s "$info_url")"

        info_bottle="$(sh_json .bottle.stable "$info_json")"
        test -z "$info_bottle" && exite "failed to load bottle info for $1"
        
        info_bottle_arch="$(sh_json ".files.$sys_info" "$info_bottle")"
        if test -z "$info_bottle_arch"; then
            info_bottle_arch="$(sh_json ".files.all" "$info_bottle")"
        fi
        test -z "$info_bottle_arch" && exite "failed to load bottle info for $1, system type $sys_info"

        info_bottle_url="$(sh_json ".url" "$info_bottle_arch")"
        info_bottle_sha="$(sh_json ".sha256" "$info_bottle_arch")"

        info "fetching $1 from $info_bottle_url (sha = $info_bottle_sha)"
        key_info "downloading $1..."

        curl_extra_opts="-s"
        if test $verbose = 1; then
            curl_extra_opts="-#"
        fi

        if curl $curl_extra_opts -g -H "Authorization: Bearer QQ==" -L  -o "$deps_dl_dir/$info_bottle_sha" -C - "$info_bottle_url"; then
            info "download $1 successful; extracting"
        else
            exite "failed to download $1 from $info_bottle_url"
        fi

        if tar -zxf "$deps_dl_dir/$info_bottle_sha" -C "$deps_scratch_dir"; then
            info "extracting $1 successful"
        else
            exite "failed to extract $1 from $deps_dl_dir/$info_bottle_sha to $deps_scratch_dir"
        fi
        
        key_info "patching $1..."
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
                if grep -q -e "@@HOMEBREW" "$f"; then
                    f_patch=1
                fi
                f_rel="${f#"$deps_scratch_dir"}"

                if test $f_patch = 0; then
                    if file "$f" | grep -q "Mach-O"; then
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
                        f_names=$(otool -L "$f" | grep -e "@@HOMEBREW" | awk '\''
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
                    *text*) rm -f "$f"; sed -e "s%@@HOMEBREW_CELLAR@@%$tmp_prefix/$brew_dir_name%g" -e "s%@@HOMEBREW_PREFIX@@%$tmp_prefix%g" -e "s%@@HOMEBREW_PERL@@%/usr/bin/perl%g" "$tmp_write" > "$f"; rm "$tmp_write"; chmod "$f_perm" "$f";;
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

        info "successfully patched $1: $num_f files"

        info_deps="$(sh_json .dependencies.sh "$info_json")"
        
        if test -n "$info_deps"; then
            info "$1 depends on: $info_deps"
        fi

        for d in $info_deps; do
            microbrew "$d"
        done
        
        dep_ver="$(ls "$deps_scratch_dir/$1")"

        info "linking $1 into $deps_dir"
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

    libinkq_dir="$(abspath "$ext_dir/libinotify-kqueue")"

    if test ! -d "$libinkq_dir"; then
        key_info "missing libinotify-kqueue; building from source"

        microbrew "automake"
        microbrew "libtool"

        key_info "downloading libinotify-kqueue sources..."
        libinkq_url="https://api.github.com/repos/libinotify-kqueue/libinotify-kqueue/tarball/master"

        libinkq_build_dir="$(abspath "$deps_scratch_dir/libinotify-kqueue")"
        test -d "$libinkq_build_dir" || mkdir "$libinkq_build_dir" || exite "failed to create $libinkq_build_dir"

        if curl -s -L "$libinkq_url" | tar -zx --strip-components=1 -C "$libinkq_build_dir"; then
            info "download + extract libinotify-kqueue sources successful"
            key_info "building libinotify-kqueue..."

            build_ncpu="$(if test "$is_macos" = 1; then
                sysctl -n hw.logicalcpu
            else
                if command -v nproc > /dev/null; then
                    nproc
                fi
            fi)"

            if libinkq_log="$(cd "$libinkq_build_dir" && autoreconf -fvi 2>&1 && \
                CFLAGS="${CFLAGS:+$CFLAGS }-target x86_64-apple-macos -arch x86_64" ./configure --prefix="$tmp_prefix" 2>&1 && \
                make clean 2>&1 && make -j$build_ncpu 2>&1 && make install prefix="$tmp_prefix" DESTDIR="$libinkq_build_dir/build" 2>&1)"; then
                info "libinotify-kqueue build log:\n\n%s\n\nlibinotify-kqueue build log end" "$libinkq_log"
                key_info "libinotify-kqueue built successfully"
            else
                info "libinotify-kqueue build log:\n\n%s\n\nlibinotify-kqueue build log end" "$libinkq_log"
                exite "failed to build libinotify-kqueue"
            fi

            mv "$libinkq_build_dir/build/$tmp_prefix" "$libinkq_dir"

            for td in lib include share; do
                linkmerge "$libinkq_dir/$td" "$deps_dir/$td" "../ext/libinotify-kqueue/$td"
            done
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

# TODO: set LDFLAGS=-Wl,ld_classic -Wl,-rpath,/some/path/here (/usr/local/lib)