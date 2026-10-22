// SDL3 hands control to native code through this single entry point. The C side monkey-patches the
// UIAbility instance with the callbacks it needs (TakeOverUIAbility), so the ArkTS surface stays
// this small on purpose.
//
// ONLY EVER ADD PARAMETERS, NEVER REMOVE OR REORDER: SDL's SDL_JS_ProvideArkTSObjects() expects
// exactly 5 arguments and calls exit(1) when the count differs
// (third_party/cangjie-sdl -> SDL src/core/openharmony/SDL_openharmony.c). Every argument is
// therefore required here.
export const provideArkTSObjects: (
  ability: ESObject,
  atManager: ESObject,
  locale: ESObject,
  setPointerVisible: ESObject,
  inputMethod: ESObject
) => void;
