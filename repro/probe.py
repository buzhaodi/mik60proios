import struct, sys
sys.path.insert(0, "/home/yang/unixnu-work/UniXNU/out/socrates/tree/kits/XnuPrelink")
from native_prelink import macho, backed_offset
data = open("/home/yang/unixnu-work/UniXNU/out/ipsw/21H461/kernelcache.decompressed","rb").read()
meta = macho(data)
print("kernelcache segments:")
for s in meta["segments"]:
    print(" ", s["name"], hex(s["va"]), hex(s["size"]))
def read(va, size):
    at = backed_offset(meta["segments"], va, size, len(data))
    return data[at:at+size]
for delta in (0x1000000, -0x1000000, 0x2000000):
    va = 0xfffffff004a24adc + delta
    try:
        got = struct.unpack("<4I", read(va, 16))
        match = got == (0xf9404400, 0xb4000080, 0xf9400008, 0xf9450101)
        print("delta %+#x: %s  %s" % (delta, tuple(hex(x) for x in got), "MATCH" if match else ""))
    except ValueError:
        print("delta %+#x: unbacked" % delta)
