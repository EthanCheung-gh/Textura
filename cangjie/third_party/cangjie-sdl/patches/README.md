# cangjie-sdl / SDL 补丁（复现用）

这里的补丁作用于 **PixCap-Cangjie 的 `third_party/SDL` 源码**（不是本仓的绑定源码），
产出 `.sdl3-ohos/libSDL3.so`；在本仓只作为可复现记录，不在本仓应用。

| 补丁 | 目标文件 | 一句话 |
|---|---|---|
| `sdl-openharmony-clipboard-double-free.patch` | `src/video/openharmony/SDL_openharmonyclipboard.c` | SDL-P02：`OPENHARMONY_GetClipboardText` 里 `OH_UdmfData_GetRecord` 返回的 record 归 data 所有，删掉两处多余的 `OH_UdmfRecord_Destroy`，修 OHOS 粘贴/注入文本的 double free（SIGTRAP）。 |

应用方式（在 PixCap-Cangjie 内，注意 `third_party/SDL` 还有 4 个既有补丁）：

```bash
cd /home/ethan/CodeRepo/sandbox/PixCap-Cangjie/third_party/SDL
git apply /path/to/textura/cangjie/third_party/cangjie-sdl/patches/sdl-openharmony-clipboard-double-free.patch
cd ../.. && ./scripts/build_ohos_deps.sh sdl
cp third_party/SDL/build/libSDL3.so \
   ../../Textura/cangjie/third_party/cangjie-sdl/.sdl3-ohos/libSDL3.so
```
