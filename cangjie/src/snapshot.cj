package textura

import std.fs.*

/** CUI writes BMP (`--snapshot`); the parity contract asks for PNG. This module
 * converts the BMP in-place deterministically with an uncompressed (stored)
 * zlib stream, so no external tool or timestamp enters the artifact. */
public func convertBmpToPng(bmpPath: String, pngPath: String): Unit {
    let bmp = File.readFrom(bmpPath)
    if (bmp.size < 54 || bmp[0] != UInt8(0x42) || bmp[1] != UInt8(0x4D)) {
        throw Exception("not a BMP file: ${bmpPath}")
    }
    let pixelOffset = Int64(readU32(bmp, 10))
    let width = Int64(readU32(bmp, 18))
    let height = Int64(readU32(bmp, 22))
    let bitsPerPixel = Int64(readU16(bmp, 28))
    let compression = readU32(bmp, 30)
    if (width <= 0 || height <= 0) {
        throw Exception("unsupported BMP dimensions: ${width}x${height}")
    }
    if (compression != 0 && compression != 3) {
        throw Exception("unsupported BMP compression: ${compression}")
    }
    if (bitsPerPixel != 24 && bitsPerPixel != 32) {
        throw Exception("unsupported BMP bit depth: ${bitsPerPixel}")
    }
    let bytesPerPixel = bitsPerPixel / 8
    let rowBytes = ((width * bitsPerPixel + 31) / 32) * 4
    let stride = width * 3 + 1
    let raw = Array<UInt8>(stride * height, repeat: UInt8(0))
    for (y in 0..height) {
        // SDL_SaveBMP writes bottom-up rows.
        let sourceRow = height - 1 - y
        let sourceBase = pixelOffset + sourceRow * rowBytes
        let rowBase = y * stride
        raw[rowBase] = UInt8(0) // PNG filter: None
        for (x in 0..width) {
            let p = sourceBase + x * bytesPerPixel
            let out = rowBase + 1 + x * 3
            raw[out] = bmp[p + 2] // R
            raw[out + 1] = bmp[p + 1] // G
            raw[out + 2] = bmp[p] // B
        }
    }
    File.writeTo(pngPath, encodePng(width, height, raw))
}

private func readU16(bytes: Array<UInt8>, pos: Int64): UInt16 {
    UInt16(bytes[pos]) | (UInt16(bytes[pos + 1]) << 8)
}

private func readU32(bytes: Array<UInt8>, pos: Int64): UInt32 {
    UInt32(bytes[pos]) |
        (UInt32(bytes[pos + 1]) << 8) |
        (UInt32(bytes[pos + 2]) << 16) |
        (UInt32(bytes[pos + 3]) << 24)
}

private func encodePng(width: Int64, height: Int64, raw: Array<UInt8>): Array<UInt8> {
    // zlib: 0x78 0x01, stored deflate blocks, then Adler-32.
    let blockSize: Int64 = 65535
    let blockCount = (raw.size + blockSize - 1) / blockSize
    let zlibSize = 2 + blockCount * 5 + raw.size + 4
    let pngSize = 8 + 25 + (12 + zlibSize) + 12
    let out = Array<UInt8>(pngSize, repeat: UInt8(0))
    var cursor: Int64 = 0
    let signature: Array<UInt8> = [UInt8(0x89), UInt8(0x50), UInt8(0x4E), UInt8(0x47), UInt8(0x0D), UInt8(0x0A), UInt8(0x1A), UInt8(0x0A)]
    for (b in signature) {
        out[cursor] = b
        cursor += 1
    }
    // IHDR
    let ihdr = Array<UInt8>(13, repeat: UInt8(0))
    writeBe32(ihdr, 0, UInt32(width))
    writeBe32(ihdr, 4, UInt32(height))
    ihdr[8] = UInt8(8) // bit depth
    ihdr[9] = UInt8(2) // colour type: truecolour RGB
    ihdr[10] = UInt8(0)
    ihdr[11] = UInt8(0)
    ihdr[12] = UInt8(0)
    cursor = writeChunk(out, cursor, "IHDR", ihdr)
    // IDAT
    let idat = Array<UInt8>(zlibSize, repeat: UInt8(0))
    var z: Int64 = 0
    idat[z] = UInt8(0x78)
    z += 1
    idat[z] = UInt8(0x01)
    z += 1
    var offset: Int64 = 0
    var block: Int64 = 0
    while (offset < raw.size) {
        let length = min(blockSize, raw.size - offset)
        let finalBlock = offset + length >= raw.size
        idat[z] = if (finalBlock) {UInt8(0x01)} else {UInt8(0x00)}
        z += 1
        writeU16(idat, z, UInt16(length))
        writeU16(idat, z + 2, UInt16(0xFFFF - (length & 0xFFFF)))
        z += 4
        for (i in 0..length) {
            idat[z + i] = raw[offset + i]
        }
        z += length
        offset += length
        block += 1
    }
    let adler = adler32(raw)
    writeBe32(idat, z, adler)
    z += 4
    cursor = writeChunk(out, cursor, "IDAT", idat)
    // IEND
    cursor = writeChunk(out, cursor, "IEND", [])
    out
}

private func writeChunk(out: Array<UInt8>, start: Int64, kind: String, data: Array<UInt8>): Int64 {
    var cursor = start
    writeBe32(out, cursor, UInt32(data.size))
    cursor += 4
    let kindBytes = kind.toArray()
    for (b in kindBytes) {
        out[cursor] = b
        cursor += 1
    }
    for (b in data) {
        out[cursor] = b
        cursor += 1
    }
    var crc: UInt32 = 0xFFFFFFFF
    for (b in kindBytes) {
        crc = updateCrc(crc, b)
    }
    for (b in data) {
        crc = updateCrc(crc, b)
    }
    writeBe32(out, cursor, crc ^ 0xFFFFFFFF)
    cursor + 4
}

private func updateCrc(crc: UInt32, value: Byte): UInt32 {
    var current = crc ^ UInt32(value)
    for (_ in 0..8) {
        if ((current & 1) != 0) {
            current = (current >> 1) ^ 0xEDB88320
        } else {
            current = current >> 1
        }
    }
    current
}

private func adler32(data: Array<UInt8>): UInt32 {
    var a: UInt32 = 1
    var b: UInt32 = 0
    for (index in 0..data.size) {
        a = (a + UInt32(data[index])) % 65521
        b = (b + a) % 65521
    }
    (b << 16) | a
}

private func writeBe32(out: Array<UInt8>, pos: Int64, value: UInt32): Unit {
    out[pos] = UInt8((value >> 24) & 0xFF)
    out[pos + 1] = UInt8((value >> 16) & 0xFF)
    out[pos + 2] = UInt8((value >> 8) & 0xFF)
    out[pos + 3] = UInt8(value & 0xFF)
}

private func writeU16(out: Array<UInt8>, pos: Int64, value: UInt16): Unit {
    out[pos] = UInt8(value & 0xFF)
    out[pos + 1] = UInt8((value >> 8) & 0xFF)
}

