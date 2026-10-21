// r68k.js in the web page (tools/mkweb.py --pre-js): the SD card.
// r68k reads and writes the card as the file rosco_sd.bin (opened when the
// program starts, so it is made in preRun).  It starts with SD_SIZE zero
// bytes and grows as r68kSdWrite writes to it: the page puts uploaded
// files there for Minix to copy with dd from /dev/c0d0 (loader.js).
var SD_SIZE = 4 << 20;
Module.preRun = [].concat(Module.preRun || [], function () {
  FS.writeFile('/rosco_sd.bin', new Uint8Array(SD_SIZE));
});
// write bytes (Uint8Array) at offset; the card grows to cover them, in
// whole megabytes (Minix reads ahead)
Module.r68kSdWrite = function (offset, bytes) {
  var s = FS.open('/rosco_sd.bin', 'r+');
  var end = offset + bytes.length, size = s.node.usedBytes;
  if (end + (1 << 20) > size) {
    var grow = new Uint8Array(Math.ceil((end + (1 << 20) - size) / (1 << 20)) << 20);
    FS.write(s, grow, 0, grow.length, size);
  }
  FS.write(s, bytes, 0, bytes.length, offset);
  FS.close(s);
};
// read len bytes at offset (a Uint8Array): what Minix wrote to the card
Module.r68kSdRead = function (offset, len) {
  var s = FS.open('/rosco_sd.bin', 'r'), b = new Uint8Array(len);
  var n = FS.read(s, b, 0, len, offset);
  FS.close(s);
  return n === len ? b : b.subarray(0, n);
};
