# cxbuilder
Build Wine from source with CrossOver patches. This allows you to run game launchers (e.g. Steam) and productivity software that do not work properly on mainline Wine.

CXBuilder is tested on Wine 9.0 with CrossOver 24. It essentially compiles the open-source [CrossOver source distributions](https://www.codeweavers.com/crossover/source) with some minor patches.

If you're looking for an easier setup experience and are okay with running an older version of Wine, consider [Whisky](https://getwhisky.app). Alternatively, [purchase a CrossOver license](https://www.codeweavers.com/crossover/) for the best experience and to support the developers of Wine.

## Releases
Instead of running CXBuilder yourself, you can download a prebuilt image from the "Releases" tab. These builds are available for Intel and Apple Silicon macOS devices.

## Usage
Clone this repository

## Post-install
Game Porting Toolkit does not provide 32-bit Direct3D DLLs; therefore, to run 32-bit games, you will need to install DXVK, potentially patched for macOS. (TODO: elaborate)

### Notes
Past versions of CrossOver used a custom build of Clang with a special `wine32` target to support both 32-bit and 64-bit Windows software in the same `WINEPREFIX`. As of Wine 9.0, it is no longer necessary to use a custom build of Clang for this, thanks to the new experimental WOW64 runtime within Wine. Thus CodeWeavers have removed their modified LLVM sources from their open-source releases.

## License
CXBuilder is licensed under the LGPL v3.0, as it is a derivative work of the LGPL-licensed CrossOver project (which itself is a derivative work of Wine).

Please note that the `game-porting-toolkit` subdirectory contains proprietary software from Apple, and is not covered under this license.