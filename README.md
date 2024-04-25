# cxbuilder
Build Wine from source with CrossOver patches. This allows you to run game launchers (e.g. Steam) and productivity software that do not work properly on mainline Wine.

CXBuilder is tested on Wine 9.0 with CrossOver 24, and it is optimized for use with Apple Silicon-based Macs. It essentially compiles the Wine from open-source [CrossOver source distributions](https://www.codeweavers.com/crossover/source), with some minor patches.

If you're looking for an easier setup experience and are okay with running an older version of Wine, consider [Whisky](https://getwhisky.app). Alternatively, [purchase a CrossOver license](https://www.codeweavers.com/crossover/) for the best, most user-friendly experience and to support the developers of Wine.

## Releases
Instead of running CXBuilder yourself, you can download a prebuilt image from the "Releases" tab. These builds are available for Intel and Apple Silicon macOS devices.

## Usage
Clone this repository

## Post-install

### DXVK
Game Porting Toolkit does not provide 32-bit Direct3D DLLs; therefore, to run most 32-bit games, you will need to install [DXVK](https://github.com/doitsujin/dxvk) into your `$WINEPREFIX`. CXBuilder always produces a script `install-dxvk.sh` that you can use to install DXVK into your current `$WINEPREFIX`, without it affecting with your D3DMetal (i.e. Game Porting Toolkit) install. If you use `--dxvk`, CXBuilder bakes the DXVK you provide into your Wine build itself, meaning you won't need to install it into each `$WINEPREFIX` separately.

Note that there are limitations on the builds of DXVK you can use on different platforms. Linux is relatively unrestricted, but macOS is much trickier; there are some notes about it further down. The TL;DR is, you should most likely use the latest release of [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS).

### Retina
If you're using a Mac with a Retina display, you will likely want to configure Wine to recognize that. To do this, navigate to `HKEY_CURRENT_USER\Software\Wine\Mac Driver` in the registry (you may need to create the `Mac Driver` key if it does not exist). Add the key `RetinaMode` into `Mac Driver`; set its value to be the string `Y`. After restarting Wine, you'll want to double your DPI scaling; typically, you'd do this by running `winecfg.exe`, navigating to the `Graphics` pane, and changing your DPI from 96 to 192.

## Notes

### Custom LLVM
Past versions of CrossOver used a custom build of Clang with a special `wine32` target to support both 32-bit and 64-bit Windows software in the same `WINEPREFIX`. As of Wine 9.0, it is no longer necessary to use a custom build of Clang for this, thanks to the new experimental WOW64 runtime within Wine. Thus CodeWeavers have removed their modified LLVM sources from their open-source releases.

### macOS DXVK notes
Wine's Vulkan support on macOS goes through [MoltenVK](https://github.com/KhronosGroup/MoltenVK), a library that translates Vulkan calls into Metal. Unfortunately, MoltenVK supports only a subset of the Vulkan 1.2 standard, while modern versions of DXVK require Vulkan 1.3 or later. DXVK has also never officially supported macOS, and as a result mainline DXVK crashes immediately on most Macs. Altogether this means you will need to install a patched, old version of DXVK in order to run 32-bit Direct3D games.

Your best bet is using [DXVK-macOS](https://github.com/Gcenx/DXVK-macOS); if you choose to install it yourself, you should only copy `x32/d3d10core.dll` and `x32/d3d11.dll` into your `windows/syswow64` folder, and apply the corresponding DLL overrides. If you prefer DXVK to D3DMetal (the Direct3D translation layer supplied by Apple's Game Porting Toolkit), or would like to compare the two, you can also copy `x64/d3d10core.dll` and `x64/d3d11.dll` into `windows/system32`. **However, this will break by default if you built Wine with GPTk.** The fix is to use a version of the `dxgi.dll` built by Wine (NOT the version supplied by D3DMetal) after "re-signing" it to make it appear like a DLL not built by Wine. (Essentially the bytes 0x40-0x60 must be changed from their initial value of `"Wine builtin DLL"`). CXBuilder will do all of this for you, but if you'd like to build things by hand, have a look through the source code to see what you'll need to change.

## License
CXBuilder is licensed under the LGPL v3.0, as it is a derivative work of the LGPL-licensed CrossOver project (which itself is a derivative work of Wine).

Please note that the `game-porting-toolkit` subdirectory contains proprietary software from Apple, and is not covered under this license.