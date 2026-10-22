// r68k.js in the web page (tools/mkweb.py --pre-js): the SD card.
// r68k reads and writes the card as the file rosco_sd.bin (opened when the
// program starts, so it is made in preRun).  With Module.sdFormat (bare
// BBC BASIC) it is a FAT16 file system (an MBR with one partition from
// sector 2048, as the rosco card tools make it) that bare BASIC and the
// page's fat.js share; otherwise it is blank and grows as r68kSdWrite
// writes to it (the Minix page copies uploads off it with dd).
var SD_SIZE = 32 << 20;
var SD_PART = 2048;

function sdFormat(img) {
  var total = img.length / 512 - SD_PART, b = SD_PART * 512, spc = 1;
  while (total / spc > 65524) spc *= 2;
  var rsv = 1, nfats = 2, rootents = 512, rootsecs = rootents * 32 / 512;
  var fatsz = Math.ceil(((total - rsv - rootsecs) / spc + 2) * 2 / 512);
  function p16(o, v) { img[o] = v & 0xFF; img[o + 1] = (v >> 8) & 0xFF; }
  function p32(o, v) { p16(o, v & 0xFFFF); p16(o + 2, Math.floor(v / 65536) & 0xFFFF); }
  // MBR: one FAT16 partition
  img[446 + 4] = 0x06;
  p32(446 + 8, SD_PART);
  p32(446 + 12, total);
  img[510] = 0x55; img[511] = 0xAA;
  // boot sector
  img.set([0xEB, 0x3C, 0x90], b);
  img.set(Array.from('BBC68K  ', function (c) { return c.charCodeAt(0); }), b + 3);
  p16(b + 11, 512); img[b + 13] = spc; p16(b + 14, rsv); img[b + 16] = nfats;
  p16(b + 17, rootents);
  if (total < 65536) p16(b + 19, total); else p32(b + 32, total);
  img[b + 21] = 0xF8; p16(b + 22, fatsz); p16(b + 24, 63); p16(b + 26, 255);
  p32(b + 28, SD_PART);
  img[b + 36] = 0x80; img[b + 38] = 0x29; p32(b + 39, 0x6802B5C);
  img.set(Array.from('BBC BASIC  FAT16   ', function (c) { return c.charCodeAt(0); }), b + 43);
  img[b + 510] = 0x55; img[b + 511] = 0xAA;
  // the FATs: media byte, end of chain
  for (var k = 0; k < nfats; k++) img.set([0xF8, 0xFF, 0xFF, 0xFF], b + (rsv + k * fatsz) * 512);
}

Module.preRun = [].concat(Module.preRun || [], function () {
  var img = new Uint8Array(Module.sdFormat ? SD_SIZE : 4 << 20);
  if (Module.sdFormat) sdFormat(img);
  FS.writeFile('/rosco_sd.bin', img);
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
