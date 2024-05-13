# cxbuilder
Build Wine from source with CrossOver patches. This allows you to run game launchers (e.g. Steam) and productivity software that do not work properly on mainline Wine.

CXBuilder is tested on CrossOver 24 (which is based on Wine 9.0), and it is optimized for use with Apple Silicon-based Macs. However, it works on Intel Macs too, and support for Linux is in progress. It essentially compiles the Wine from the open-source [CrossOver source distributions](https://www.codeweavers.com/crossover/source), with various patches applied to improve graphics performance.

If you're looking for an easier setup experience and are okay with running an older version of Wine, consider [Whisky](https://getwhisky.app). Alternatively, [purchase a CrossOver license](https://www.codeweavers.com/crossover/) for the best, most user-friendly experience and to support the developers of Wine.

## Releases
Instead of running CXBuilder yourself, you can download a prebuilt image from the "Releases" tab. These builds are available for Intel and Apple Silicon macOS devices.

## Usage
The entirety of CXBuilder is included within `cxbuilder.sh`; you can clone this repository to download the script, or download CXBuilder directly with:
```sh
curl -O "https://raw.githubusercontent.com/101arrowz/cxbuilder/master/cxbuilder.sh" && chmod +x cxbuilder.sh
```

Use `./cxbuilder.sh -h` to see the options. Here is an example of the output:

```sh
$ ./cxbuilder.sh -h
./cxbuilder.sh [-v] [-x] [--wine dir] [--gptk dir] [--dxvk dir] [--no-deps]
               [--rebuild] [--no-clean] [--out dest_dir] [source_dir]

Arguments:
    -h, --help           Prints this help message and exits
    -v, --verbose        Enables verbose logging of build commands and results
    -x, --no-prompt      Run non-interactively

    -w, --wine           Uses the Wine sources from the specified directory.
                         CXBuilder is designed specifically to work with the
                         Wine sources provided with the open-source distribution
                         of CrossOver, which include various "hacks" to make
                         software that breaks with mainline Wine work anyway.
                         However, CXBuilder should work the original Wine too,
                         or any fork. Defaults to [source_dir]/wine.

    --no-gptk            Disable use of Direct3D DLLs from Apple's Game Porting
                         Toolkit (GPTk). GPTk is supported only on Apple Silicon
                         Macs. GPTk is disabled by default on all other devices.

    --gptk dir           Uses the Game Porting Toolkit from the specified
                         directory. This should have a redist/ subdirectory with
                         Apple's proprietary Direct3D -> Metal translation
                         layer libraries inside. Defaults to [source_dir]/gptk.

    --no-dxvk            Disables the use of Direct3D DLLs from DXVK. Note that
                         if GPTk is enabled, DXVK will only be used for 32-bit
                         software (as GPTk does not support 32-bit Direct3D).

    --dxvk dir           Uses the DXVK build from the specified directory. This
                         should have x32/ and x64/ subdirectories with Direct3D
                         DLLs. Note that if both GPTk and DXVK are enabled, GPTk
                         will take priority (i.e. only the x32/ DLLs from DXVK
                         will be used). Defaults to [source_dir]/dxvk.

    --no-deps            Disables the built-in dependency fetcher. Setting this
                         flag makes it possible to use custom builds of Wine
                         dependencies, rather than pre-built versions from the
                         Homebrew project; however, you will need to configure
                         the static and dynamic linker flags manually to point
                         to the correct locations of your dependencies. This
                         is not necessary for most builds and can lead to many
                         headaches if misused; the built-in dependency fetcher
                         is well-tested and does not install anything globally
                         into your system (not even Homebrew!)

    -r, --rebuild        Forcibly rebuilds Wine from source, ignoring cached or
                         partially built results. This option will need to be
                         specified after updating compiler/linker flags but
                         should generally be avoided otherwise.

    -d, --no-clean       Skips cleaning the build cache from dest_dir after a
                         build completes. Useful for debugging broken builds
                         without having to rebuild from source each time, but
                         should be unnecessary otherwise.

    -o, --out dest_dir   Where to generate the final Wine build. This directory
                         will contain a similar structure to /usr/local (and
                         that is indeed a valid value for this argument) after
                         the build completes. However, the build can be placed
                         anywhere on your system and may be moved around freely
                         afterwards, so long as relative symlinks are preserved.
                         Defaults to [source_dir]/build.

    source_dir           The directory in which the source files are present.
                         It is not necessary to use this directory, but it can
                         be used to create a build with only one argument.
```

If you are unfamiliar with building C programs, consider using the pre-built releases rather than building from source using the script directly.

## Post-install

### DXVK
Game Porting Toolkit, and specifically its D3DMetal framework, does not provide 32-bit Direct3D DLLs; therefore, to run most 32-bit games, you would need to use [DXVK](https://github.com/doitsujin/dxvk). By default, CXBuilder bakes the DXVK you provide into your Wine build itself, meaning you won't need to install it into each `$WINEPREFIX` separately. If you use both `--gptk` and `--dxvk`, CXBuilder will bake DXVK for 32-bit Direct3D and D3DMetal for 64-bit Direct3D.

Note that there are limitations on the builds of DXVK you can use on different platforms. Linux is relatively unrestricted, but macOS is much trickier; there are some notes about it further down. The TL;DR is, you should most likely use the latest release of [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS).

### Retina
If you're using a Mac with a Retina display, you will likely want to configure Wine to recognize that. To do this, navigate to `HKEY_CURRENT_USER\Software\Wine\Mac Driver` in the registry (you may need to create the `Mac Driver` key if it does not exist). Add the key `RetinaMode` into `Mac Driver`; set its value to be the string `Y`. After restarting Wine, you'll want to double your DPI scaling; typically, you'd do this by running `winecfg.exe`, navigating to the `Graphics` pane, and changing your DPI from 96 to 192. Note that Retina mode may break certain games.

## Notes

### Custom LLVM
Past versions of CrossOver used a custom build of Clang with a special `wine32` target to support both 32-bit and 64-bit Windows software in the same `WINEPREFIX`. As of Wine 9.0, it is no longer necessary to use a custom build of Clang for this, thanks to the new experimental WOW64 runtime within Wine. Thus CodeWeavers have removed their modified LLVM sources from their open-source releases.

### macOS DXVK notes
Wine's Vulkan support on macOS goes through [MoltenVK](https://github.com/KhronosGroup/MoltenVK), a library that translates Vulkan calls into Metal. Unfortunately, MoltenVK supports only a subset of the Vulkan 1.2 standard, while modern versions of DXVK require Vulkan 1.3 or later. DXVK has also never officially supported macOS, and as a result mainline DXVK crashes immediately on most Macs. Altogether this means you will need to install a patched, old version of DXVK in order to run 32-bit Direct3D games.

Your best bet is using [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS); if you choose to install it yourself, you should only copy `x32/d3d10core.dll` and `x32/d3d11.dll` into your `windows/syswow64` folder, and apply the corresponding DLL overrides. If you prefer DXVK to D3DMetal (the Direct3D translation layer supplied by Apple's Game Porting Toolkit), or would like to compare the two, you can also copy `x64/d3d10core.dll` and `x64/d3d11.dll` into `windows/system32`. **However, this would break by default if you built Wine with GPTk due to Wine's DLL override behavior.**

The fix is to re-sign a version of the `dxgi.dll` built by Wine for `wined3d` (NOT the version supplied by D3DMetal) to make it appear as though it were not built by Wine, and copy that into your `WINEPREFIX` under `C:\Windows\System32`. (Essentially the bytes 0x40-0x60 must be changed from their initial value of `"Wine builtin DLL"` to something else). CXBuilder has support planned for simultaneous DXVK and D3DMetal integration into a single Wine build, with the backend configurable at runtime, by applying such a patch to `wined3d`'s `dxgi.dll`. However, if you'd like to use both at the same time in your personal Wine build, or if you'd prefer to build things by hand, make sure to follow these steps.

## License
CXBuilder is licensed under the LGPL v3.0, as it is a derivative work of the LGPL-licensed CrossOver Wine subproject (which itself is a derivative work of Wine).

Please note that the `game-porting-toolkit` subdirectory contains proprietary software from Apple, and is not covered under this license. Apple's Game Porting Toolkit is an optional plugin for this software.