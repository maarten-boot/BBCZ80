// The SD card's FAT16 file system, from the page's side (src68k/web): bare
// BBC BASIC reads and writes the same card through the firmware (bare/
// fat.c), the page puts uploaded files on it and takes downloads off it.
//
// BBCFat.card(read, write): read(offset, length) -> Uint8Array and
// write(offset, bytes) on the card image (pre.js r68kSdRead/r68kSdWrite).
// The card has an MBR whose first partition is FAT16 (pre.js formats it).
// Names are 8.3, upper case, as bare/fat.c makes them; a path may go into
// directories that exist ("SUB/PROG.BBC").  The page writes only when
// BASIC is at its prompt, between its file calls (fat.c reads the card
// afresh in each call).

var BBCFat = (function () {
  'use strict';

  function le16(b, o) { return b[o] | (b[o + 1] << 8); }
  function le32(b, o) { return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16)) + b[o + 3] * 16777216; }
  function put16(b, o, v) { b[o] = v & 0xFF; b[o + 1] = (v >> 8) & 0xFF; }
  function put32(b, o, v) { put16(b, o, v & 0xFFFF); put16(b, o + 2, Math.floor(v / 65536) & 0xFFFF); }

  // "name.ext" -> the 11 characters of an 8.3 entry, or null
  function name83(s) {
    if (s === '.' || s === '..') return (s + '          ').slice(0, 11);
    var m = /^([^.]{1,8})(?:\.([^.]{0,3}))?$/.exec(s);
    if (!m) return null;
    var n = (m[1].toUpperCase() + '        ').slice(0, 8) + ((m[2] || '').toUpperCase() + '   ').slice(0, 3);
    for (var i = 0; i < 11; i++) {
      var c = n.charCodeAt(i);
      if (c < 0x20 || c > 0x7E || '"*+,/:;<=>?[\\]|'.indexOf(n[i]) >= 0) return null;
    }
    return n;
  }

  // a file name made 8.3: letters, digits and _ - ... kept, the rest _
  function make83(name) {
    name = name.replace(/^.*[\\/]/, '').toUpperCase();
    var dot = name.lastIndexOf('.');
    var base = (dot > 0 ? name.slice(0, dot) : name).replace(/[^A-Z0-9_\-!#$%&'(){}~^@`]/g, '_');
    var ext = (dot > 0 ? name.slice(dot + 1) : '').replace(/[^A-Z0-9_\-!#$%&'(){}~^@`]/g, '_');
    return (base || 'FILE').slice(0, 8) + (ext ? '.' + ext.slice(0, 3) : '');
  }

  function card(read, write) {
    var mbr = read(0, 512), part = -1, i;
    for (i = 0; i < 4; i++) {
      var t = mbr[446 + 16 * i + 4];
      if (t === 0x04 || t === 0x06 || t === 0x0E) { part = le32(mbr, 446 + 16 * i + 8); break; }
    }
    if (part < 0) throw new Error('no FAT16 partition on the card');
    var b = read(part * 512, 512);
    var spc = b[13], rsv = le16(b, 14), nfats = b[16], rootents = le16(b, 17);
    var fatsz = le16(b, 22), tot = le16(b, 19) || le32(b, 32);
    var fat = (part + rsv) * 512, root = fat + nfats * fatsz * 512;
    var data = root + rootents * 32, csize = spc * 512;
    var nclusters = Math.floor((tot - rsv - nfats * fatsz - rootents * 32 / 512) / spc);

    function getfat(cl) { return le16(read(fat + cl * 2, 2), 0); }
    function setfat(cl, v) {
      var e = new Uint8Array(2);
      put16(e, 0, v);
      for (var k = 0; k < nfats; k++) write(fat + k * fatsz * 512 + cl * 2, e);
    }
    function clOff(cl) { return data + (cl - 2) * csize; }
    function chain(cl) {
      var out = [];
      while (cl >= 2 && cl < 0xFFF8 && out.length <= nclusters) { out.push(cl); cl = getfat(cl); }
      return out;
    }
    // the entries of a directory (cl 0: the root): {off, raw}
    function entries(cl) {
      var out = [], k, offs = [];
      if (cl === 0) {
        for (k = 0; k < rootents; k++) offs.push(root + 32 * k);
      } else {
        chain(cl).forEach(function (c) {
          for (k = 0; k < csize / 32; k++) offs.push(clOff(c) + 32 * k);
        });
      }
      for (k = 0; k < offs.length; k++) {
        var e = read(offs[k], 32);
        if (e[0] === 0) break;
        out.push({ off: offs[k], e: e });
      }
      out.free = offs.slice(out.length);	// (never used entries)
      return out;
    }
    function nameOf(e) { return String.fromCharCode.apply(null, e.subarray(0, 11)); }
    function live(e) { return e[0] !== 0xE5 && e[11] !== 0x0F && !(e[11] & 0x08); }
    // path -> {dir: cluster, n: 8.3 name, found: entry or null}
    function walk(path) {
      var parts = path.replace(/^\/+/, '').split('/'), dir = 0;
      for (var k = 0; k < parts.length; k++) {
        var n = name83(parts[k]);
        if (!n) return null;
        var f = null;
        entries(dir).forEach(function (x) { if (live(x.e) && nameOf(x.e) === n) f = x; });
        if (k === parts.length - 1) return { dir: dir, n: n, found: f };
        if (!f || !(f.e[11] & 0x10)) return null;
        dir = le16(f.e, 26);
      }
      return null;
    }
    function newcluster() {
      for (var c = 2; c < nclusters + 2; c++) {
        if (getfat(c) === 0) { setfat(c, 0xFFFF); return c; }
      }
      throw new Error('the SD card is full');
    }

    return {
      // the bytes of a file, or null
      readFile: function (path) {
        var w = walk(path);
        if (!w || !w.found || (w.found.e[11] & 0x10)) return null;
        var size = le32(w.found.e, 28), out = new Uint8Array(size), pos = 0;
        chain(le16(w.found.e, 26)).forEach(function (c) {
          if (pos < size) {
            var k = Math.min(csize, size - pos);
            out.set(read(clOff(c), k), pos);
            pos += k;
          }
        });
        return out;
      },
      // write a file (replacing one of that name); its 8.3 path
      writeFile: function (path, bytes) {
        var w = walk(path);
        if (!w) throw new Error(path + ': not an 8.3 name, or no such directory');
        var ent;
        if (w.found) {
          if (w.found.e[11] & 0x10) throw new Error(path + ' is a directory');
          chain(le16(w.found.e, 26)).forEach(function (c) { setfat(c, 0); });
          ent = w.found.off;
        } else {
          var list = entries(w.dir), slot = null;
          list.forEach(function (x) { if (!slot && x.e[0] === 0xE5) slot = x.off; });
          if (!slot) slot = list.free[0];
          if (!slot) throw new Error('the directory is full');
          ent = slot;
        }
        var first = 0, prev = 0, pos = 0;
        while (pos < bytes.length) {
          var c = newcluster();
          if (prev) setfat(prev, c); else first = c;
          var k = Math.min(csize, bytes.length - pos);
          var blk = new Uint8Array(csize);
          blk.set(bytes.subarray(pos, pos + k));
          write(clOff(c), blk);
          pos += k;
          prev = c;
        }
        var e = new Uint8Array(32);
        for (var j = 0; j < 11; j++) e[j] = w.n.charCodeAt(j);
        e[11] = 0x20;
        put16(e, 18, 0x0021);
        put16(e, 24, 0x0021);
        put16(e, 26, first);
        put32(e, 28, bytes.length);
        write(ent, e);
        var p = path.replace(/^\/+/, '').split('/');
        p[p.length - 1] = w.n.slice(0, 8).trim() + (w.n.slice(8).trim() ? '.' + w.n.slice(8).trim() : '');
        return p.join('/');
      },
      // the root directory: [{name, size, dir}]
      list: function () {
        return entries(0).filter(function (x) { return live(x.e); }).map(function (x) {
          var n = nameOf(x.e);
          return { name: n.slice(0, 8).trim() + (n.slice(8).trim() ? '.' + n.slice(8).trim() : ''),
                   size: le32(x.e, 28), dir: !!(x.e[11] & 0x10) };
        });
      }
    };
  }

  return { card: card, make83: make83, name83: name83 };
})();

if (typeof module !== 'undefined') module.exports = BBCFat;
