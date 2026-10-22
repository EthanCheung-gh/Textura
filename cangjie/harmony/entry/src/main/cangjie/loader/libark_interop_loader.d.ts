// libark_interop_loader.so is the official ArkTS-side entry point for loading a Cangjie shared
// library. requireCJLib(name) must be called from a thread bound to the ArkTS runtime (here:
// UIAbility.onCreate): the loader registers the host ArkVM with the Cangjie runtime, starts the
// runtime, and only then dlopen()s `name`. That ordering is why the native shim must not call
// CJ_MRT_CjRuntimeInit / CJ_MRT_CjRuntimeStart itself — doing so raised SIGBUS in
// CJ_MRT_CjRuntimeStart on the reference project.
//
// The .so ships in the HarmonyOS Cangjie SDK (cangjie/build/linux_ohos_aarch64_llvm/ohos/) and is
// staged into entry/libs/arm64-v8a by scripts/harmony/stage_libs.sh.
export declare function requireCJLib(name: string): Object;
