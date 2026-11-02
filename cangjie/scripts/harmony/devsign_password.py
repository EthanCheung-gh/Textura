#!/usr/bin/env python3
"""DevEco signing-password cipher: encrypt a keystore password for hvigor.

hvigor never sees a plaintext keystore password. build-profile.json5 carries the password already
encrypted, and @ohos/hvigor-ohos-plugin re-derives the work key from a *machine-local* material
directory (``<dirname(storeFile)>/material``, DevEco keeps it in ``~/.ohos/config/material``):

    material/fd/{0,1,2}   three 16-byte components
    material/ac/          one file, the PBKDF2 salt
    material/ce/          one 48-byte blob, the work key, itself AES-GCM encrypted

    rootKey = PBKDF2-HMAC-SHA256(xor(fd0, fd1, fd2, HARDCODED), salt, 10000, 16)
    workKey = AES-128-GCM-open(rootKey, ce)
    plain   = AES-128-GCM-open(workKey, hex(storePassword|keyPassword))

    blob layout: | len(4, BE) | iv(12) | ciphertext | tag(16) |,  len = len(ciphertext) + 16

The two constants (the hardcoded component and the fd/ac/ce layout) are copied from
``hvigor-ohos-plugin/src/utils/decipher-util.js``. They are the *scheme*, not a secret: the secret is
material/, which never leaves the machine — which is exactly why an encrypted password can sit in a
tracked file while a plaintext one cannot.

Subcommands:
  encrypt <material-dir>            plaintext on stdin  ->  hex cipher on stdout
  decrypt <material-dir> <hex>      hex cipher          ->  plaintext on stdout
  check   <material-dir>            verify the material dir derives a work key (exit 1 if not)

Plaintext is read from stdin, never from argv, so it cannot show up in ``ps`` output.
"""
import hashlib
import os
import struct
import sys

try:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
except ImportError:  # pragma: no cover - environment problem, not a logic branch
    sys.exit("error: python3 module 'cryptography' is required (apt install python3-cryptography)")

# src/utils/decipher-util.js: DecipherUtil.component
HARDCODED_COMPONENT = bytes([49, 243, 9, 115, 214, 175, 91, 184,
                             211, 190, 177, 88, 101, 131, 192, 119])
IV_LEN = 12
TAG_LEN = 16
KEY_LEN = 16
PBKDF2_ROUNDS = 10000


def _one_file(path):
    """decipher-util.js readDirBytes: a directory holding exactly one file."""
    if not os.path.isdir(path):
        raise SystemExit("error: %s is not a directory" % path)
    names = [n for n in os.listdir(path) if n != ".DS_Store"]
    if len(names) != 1:
        raise SystemExit("error: %s must hold exactly one file, found %d" % (path, len(names)))
    with open(os.path.join(path, names[0]), "rb") as fh:
        return fh.read()


def _as_node_string(buf):
    """`Buffer.toString()` in decipher-util.js: UTF-8, lossy on invalid sequences."""
    return buf.decode("utf-8", "replace").encode("utf-8")


def gcm_open(key, blob):
    if len(blob) < 4 + IV_LEN + TAG_LEN:
        raise ValueError("blob is %d bytes, shorter than the header+iv+tag minimum" % len(blob))
    (content_len,) = struct.unpack(">I", blob[:4])
    iv_len = len(blob) - 4 - content_len
    if iv_len != IV_LEN:
        raise ValueError("iv is %d bytes, expected %d" % (iv_len, IV_LEN))
    iv = blob[4:4 + iv_len]
    ciphertext_and_tag = blob[4 + iv_len:]
    return AESGCM(key).decrypt(iv, ciphertext_and_tag, None)


def gcm_seal(key, plain):
    iv = os.urandom(IV_LEN)
    sealed = AESGCM(key).encrypt(iv, plain, None)  # ciphertext || tag
    return struct.pack(">I", len(sealed)) + iv + sealed


def work_key(material_dir):
    """Re-derive the 16-byte work key exactly as DecipherUtil.getKey() does."""
    for name in ("fd", "ac", "ce"):
        if not os.path.isdir(os.path.join(material_dir, name)):
            raise SystemExit("error: %s is missing (expected fd/, ac/, ce/)" % os.path.join(material_dir, name))
    fd_root = os.path.join(material_dir, "fd")
    components = [n for n in os.listdir(fd_root) if n != ".DS_Store"]
    if len(components) != 3:
        raise SystemExit("error: %s must hold exactly 3 component directories, found %d"
                         % (fd_root, len(components)))
    merged = _one_file(os.path.join(fd_root, components[0]))
    for name in components[1:]:
        other = _one_file(os.path.join(fd_root, name))
        if len(other) != len(merged):
            raise SystemExit("error: fd components differ in length")
        merged = bytes(a ^ b for a, b in zip(merged, other))
    merged = bytes(a ^ b for a, b in zip(merged, HARDCODED_COMPONENT))
    if len(merged) != KEY_LEN:
        raise SystemExit("error: xor-ed fd components are %d bytes, expected %d" % (len(merged), KEY_LEN))
    salt = _one_file(os.path.join(material_dir, "ac"))
    root = hashlib.pbkdf2_hmac("sha256", _as_node_string(merged), salt, PBKDF2_ROUNDS, KEY_LEN)
    try:
        key = gcm_open(root, _one_file(os.path.join(material_dir, "ce")))
    except Exception as exc:
        raise SystemExit("error: cannot open the work key with the derived root key (%s);"
                         " %s does not belong to this machine" % (exc, material_dir))
    if len(key) != KEY_LEN:
        raise SystemExit("error: work key is %d bytes, expected %d" % (len(key), KEY_LEN))
    return key


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    command, material_dir = argv[1], os.path.abspath(argv[2]) if len(argv) > 2 else ""
    if command == "check":
        work_key(material_dir)
        return 0
    if command == "encrypt":
        plain = sys.stdin.buffer.read().rstrip(b"\n")
        if not plain:
            raise SystemExit("error: no plaintext on stdin")
        sys.stdout.write(gcm_seal(work_key(material_dir), plain).hex())
    elif command == "decrypt":
        if len(argv) < 4:
            raise SystemExit(__doc__)
        try:
            plain = gcm_open(work_key(material_dir), bytes.fromhex(argv[3]))
        except Exception as exc:
            raise SystemExit("error: not a cipher this material dir can open (%s)" % exc)
        sys.stdout.write(plain.decode("utf-8"))
    else:
        raise SystemExit(__doc__)
    return 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    sys.exit(main(sys.argv))
