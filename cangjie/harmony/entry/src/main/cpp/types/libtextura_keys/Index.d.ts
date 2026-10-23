/*
 * The ArkTS-facing surface of libtextura_keys.so (TEXTURA-CUI-P05).
 *
 * Only the keys ArkUI consumes before the XComponent sees them are forwarded through it — today that
 * is Tab (focus traversal). See entry/src/main/cpp/textura_keys.c.
 */
export const sendKey: (scancode: number, down: boolean, mods: number) => boolean;
