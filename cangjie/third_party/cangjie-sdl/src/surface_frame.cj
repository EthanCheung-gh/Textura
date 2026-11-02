/*
 * PixCap host patch (SDL-P01-rgba-frame-surface): bulk straight-RGBA8888
 * surface loading for captured frames. The stock Surface API only offers
 * per-pixel writes (SDL_WriteSurfacePixel), which is an FFI round-trip per
 * byte — unusable for multi-megabyte screen frames. This loader keeps the
 * whole path native: SDL_LoadFile reads the staged frame into native memory,
 * SDL_CreateSurface allocates the owning surface, and one SDL_memcpy stages
 * the bytes; the Cangjie array never materializes.
 *
 * Registered in docs/scope/scope-baseline.json :: cuiHostPatches.patches.
 */
package sdl

import std.fs.exists

foreign {
    func SDL_LoadFile(file: CString, dataSize: CPointer<UIntNative>): CPointer<UInt8>
    func SDL_memcpy(dst: CPointer<Unit>, src: CPointer<Unit>, len: UIntNative): CPointer<Unit>
    func SDL_free(mem: CPointer<UInt8>): Unit
}

/*
 * The stock SdlSurfaceHeader stops before pitch/pixels; this mirror adds the
 * tail fields (C layout: the pointer lands at offset 24 via natural padding,
 * which @C structs reproduce).
 */
@C
internal struct SdlSurfaceTailHeader {
    var flags: UInt32 = UInt32(0)
    var format: Int32 = 0
    var width: Int32 = 0
    var height: Int32 = 0
    var pitch: Int32 = 0
    var pixels: CPointer<UInt8> = CPointer<UInt8>()
}

extend Surface {
    /**
     * Loads a straight-RGBA8888 frame file (w*h*4 bytes, optional row padding)
     * into a new owning surface with one native bulk copy. Throws
     * `SdlException` when the file is missing, has the wrong byte count, or
     * SDL cannot allocate the surface.
     */
    public static func loadRgba8888(path: String, width: Int32, height: Int32,
        strideBytes!: Int32 = -1): Surface {
        if (width <= 0 || height <= 0 || !exists(path)) {
            throw SdlException("loadRgba8888: unusable geometry or missing file: ${path}")
        }
        let pitch = if (strideBytes >= width * 4) {
            strideBytes
        } else {
            width * 4
        }
        let expected = UIntNative(pitch) * UIntNative(height)
        let pathC = unsafe { LibC.mallocCString(path) }
        var loaded = UIntNative(0)
        var data = CPointer<UInt8>()
        var surface = Option<Surface>.None
        try {
            data = unsafe { SDL_LoadFile(pathC, inout loaded) }
            if (data.isNull()) {
                throw SdlException("SDL_LoadFile failed: ${lastSdlError()}")
            }
            if (loaded != expected) {
                throw SdlException("loadRgba8888: ${path} has ${loaded} bytes, expected ${expected}")
            }
            let created = Surface.create(width, height)
            try {
                let header = unsafe { CPointer<SdlSurfaceTailHeader>(created.ptr).read() }
                unsafe {
                    let _ = SDL_memcpy(CPointer<Unit>(header.pixels), CPointer<Unit>(data), expected)
                }
                surface = Option<Surface>.Some(created)
            } catch (e: Exception) {
                created.close()
                throw e
            }
        } finally {
            if (data.isNotNull()) {
                unsafe { SDL_free(data) }
            }
            unsafe { SDL_free(pathC.getChars()) }
        }
        match (surface) {
            case Some(value) => value
            case None => throw SdlException("loadRgba8888: unreachable")
        }
    }
}
