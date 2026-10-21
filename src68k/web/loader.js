// BBC BASIC programs for the emulated BBC BASIC (src68k/web).
//
// A program file is either tokenised (SAVE of BBC BASIC Z80, CP/M, 68000,
// Windows or SDL: lines of [length][number lo][number hi] text CR, ending
// with a 0 length) or a text listing.  A listing without line numbers (as
// BBC BASIC for Windows saves it as text) is numbered 10, 20, ...
//
// upload() puts a file into Minix by way of the emulated SD card: the page
// writes the bytes to the card image, and the lines it returns copy them
// into a file with dd and, for a program, load it (a listing through
// *EXEC, so BASIC reads it at full speed).  Downloads go the other way:
// sizeLine()/fileSize() find the file, copyOut() copies it to the card
// with dd, and the page reads it from the card image.  They are typed one at a time, each after the
// > prompt is back: keys typed while a *command runs reach the terminal
// in cooked mode, where Return becomes LF, which BASIC's editor takes as
// cursor left.  programLines() and keys() turn a program into
// lines typed at the > prompt instead.
//
// The keyword table (token byte, then the keyword, as BBC BASIC's LIST
// prints it) is made from the interpreter's own table by tools/mkweb.py.

var BBCLoad = (function () {
  'use strict';

  // tokens: {byte: keyword} from the table bytes, first entry of a token
  // wins (as in LIST: COLOUR, not COLOR)
  function tokenTable(table) {
    var t = {}, i = 0;
    while (i < table.length) {
      var tok = table[i++], kw = '';
      // a token is < &20 or >= &80; tokens &11-&1F keep their spaces
      var low = tok >= 0x11 && tok < 0x20 ? 0x20 : 0x21;
      var j = i;
      while (j < table.length && table[j] >= 0x20 && table[j] < 0x80) j++;
      for (var k = i; k < j && table[k] >= low; k++) kw += String.fromCharCode(table[k]);
      if (!(tok in t)) t[tok] = kw;
      i = j;
    }
    return t;
  }

  function isTokenised(b) {
    var p = 0;
    if (b.length < 4) return false;
    while (p < b.length && b[p] !== 0) {
      var len = b[p];
      if (len < 4 || p + len > b.length || b[p + len - 1] !== 13) return false;
      p += len;
    }
    return p < b.length && p > 0;
  }

  // the line number after GOTO etc.: &8D and three bytes
  function lineNumber(b1, b2, b3) {
    var lo = b2 ^ ((b1 << 2) & 0xC0), hi = b3 ^ ((b1 << 4) & 0xC0);
    return lo + 256 * hi;
  }

  function detokenise(b, tokens) {
    var rem = null, data = null, lines = [], p = 0;
    for (var k in tokens) {
      if (tokens[k] === 'REM') rem = +k;
      if (tokens[k] === 'DATA') data = +k;
    }
    while (b[p] !== 0) {
      var len = b[p], end = p + len - 1, i = p + 3;
      var s = String(b[p + 1] + 256 * b[p + 2]), quote = false, raw = false;
      while (i < end) {
        var c = b[i];
        if (raw) {
          s += String.fromCharCode(c);
        } else if (quote) {
          s += String.fromCharCode(c);
          if (c === 34) quote = false;
        } else if (c === 34) {
          s += '"';
          quote = true;
        } else if (c === 0x8D && i + 3 < end + 1) {
          s += lineNumber(b[i + 1], b[i + 2], b[i + 3]);
          i += 3;
        } else if ((c < 0x20 || c >= 0x80) && c in tokens) {
          s += tokens[c];
          if (c === rem || c === data) raw = true;
        } else {
          s += String.fromCharCode(c);
        }
        i++;
      }
      lines.push(s);
      p += len;
    }
    return lines;
  }

  function textLines(text) {
    var lines = text.split(/\r\n|\r|\n/).map(function (l) {
      return l.replace(/\s+$/, '');
    }).filter(function (l) { return l !== ''; });
    var numbered = lines.every(function (l) { return /^\s*\d/.test(l); });
    if (!numbered) {
      lines = lines.map(function (l, n) { return (n + 1) * 10 + ' ' + l; });
    }
    return lines.map(function (l) { return l.replace(/^\s+/, ''); });
  }

  // the program in a file (Uint8Array): lines of text
  function programLines(bytes, tokens) {
    if (isTokenised(bytes)) return detokenise(bytes, tokens);
    var text = '';
    for (var i = 0; i < bytes.length; i++) text += String.fromCharCode(bytes[i]);
    return textLines(text);
  }

  // the keys that enter it at the > prompt
  function keys(lines) {
    return 'NEW\r' + lines.join('\r') + '\r';
  }

  // a file name for Minix: letters, digits and . _ - only, at most 14
  // characters, with an extension (BASIC adds .bbc to a name without one)
  function minixName(name, ext) {
    name = name.replace(/^.*[\\/]/, '').replace(/[^A-Za-z0-9._-]/g, '_');
    var dot = name.lastIndexOf('.');
    var base = dot > 0 ? name.slice(0, dot) : name;
    var e = dot > 0 ? name.slice(dot) : ext;
    e = e.slice(0, 5);
    return (base || 'prog').slice(0, 14 - e.length) + e;
  }

  var CHUNK = 16384;		// bytes per dd (its buffer is one block)
  var GAP = 256 * 1024;		// between uploads, beyond Minix's read-ahead
  var LINE = 230;		// longest *command line typed

  // is this a listing to load as a program?  A text file named .bas or
  // .txt, or without an extension
  function isListing(name, bytes) {
    if (!/(\.(bas|txt)|^[^.]*)$/i.test(name.replace(/^.*[\\/]/, ''))) return false;
    for (var i = 0; i < bytes.length; i++) {
      var c = bytes[i];
      if (c < 32 && c !== 9 && c !== 10 && c !== 13 && c !== 26) return false;
    }
    return bytes.length > 0;
  }

  // An upload of the file name/bytes to the card from offset next on:
  // {name, tokenised, listing, size, writes: [{offset, bytes}], copy: the
  // lines (with CR) that copy it into the current directory, load: the
  // lines that load it, next}.  With program, a tokenised file is LOADed
  // and a listing (numbered if need be) read in with NEW and *EXEC;
  // otherwise the file is copied as it is (data files, several programs).
  // Each part of the file goes at a multiple of its size, so that one dd
  // (bs=size skip=k count=1) reads it; a new upload never reuses card
  // blocks, which Minix may still have in its cache.
  function upload(name, bytes, tokens, next, program) {
    var tok = isTokenised(bytes), data = bytes, i;
    var listing = program && !tok && isListing(name, bytes);
    if (listing) {
      var text = textLines(BBCLoad.latin1(bytes)).join('\r') + '\r';
      data = new Uint8Array(text.length);
      for (i = 0; i < text.length; i++) data[i] = text.charCodeAt(i) & 0xFF;
    }
    var n = minixName(name, tok ? '.bbc' : listing ? '.bas' : '');
    var writes = [], parts = [];
    for (var p = 0; p < data.length; p += CHUNK) {
      var c = Math.min(CHUNK, data.length - p), k = Math.ceil(next / c);
      writes.push({ offset: k * c, bytes: data.subarray(p, p + c) });
      parts.push('dd if=/dev/c0d0 bs=' + c + ' skip=' + k + ' count=1');
      next = (k + 1) * c;
    }
    // *(dd ...; dd ...) >name, then >>name, in lines of at most LINE
    var copy = [], group = [], redirect = ' >';
    function flushGroup() {
      var cmd = group.length > 1 ? '(' + group.join('; ') + ')' : group[0];
      copy.push('*' + cmd + redirect + n + ' 2>/dev/null\r');
      group = [];
      redirect = ' >>';
    }
    parts.forEach(function (part) {
      if (group.length && ('*(' + group.join('; ') + '; ' + part + ') >>' + n +
                           ' 2>/dev/null').length > LINE) flushGroup();
      group.push(part);
    });
    if (group.length) flushGroup();
    else copy = ['*>' + n + '\r'];
    return {
      name: n, tokenised: tok, listing: listing, size: data.length,
      writes: writes, copy: copy,
      load: !program ? [] : tok ? ['LOAD "' + n + '"\r'] :
        listing ? ['NEW\r', '*EXEC ' + n + '\r'] : [],
      next: next + GAP
    };
  }

  // Downloads.  A name for the shell: letters, digits and . _ - /
  function shellName(name) {
    return name.trim().replace(/^"|"$/g, '').replace(/[^A-Za-z0-9._\/-]/g, '');
  }

  // the names a download looks for: a name without an extension also as
  // name.bbc and name.BBC (SAVE adds .bbc if that file exists, else .BBC)
  function downloadNames(name) {
    var n = shellName(name);
    return /\.[^\/]*$/.test(n) ? [n] : [n, n + '.bbc', n + '.BBC'];
  }

  // the line that shows the size of name (wc -c)
  function sizeLine(name) {
    return '*wc -c ' + downloadNames(name).join(' ') + ' 2>/dev/null\r';
  }

  // the file and its size in the output of sizeLine: {name, size} or null
  function fileSize(output, name) {
    var names = downloadNames(name);
    for (var i = 0; i < names.length; i++) {
      var re = new RegExp('^\\s*(\\d+)\\s+' + names[i].replace(/[.\/]/g, '\\$&') + '\\s*\r?$', 'm');
      var m = re.exec(output);
      if (m) return { name: names[i], size: +m[1] };
    }
    return null;
  }

  // the line that copies name (size bytes) to the card at offset (and
  // sync, so that it is on the card, not in Minix's cache): {line,
  // offset, next}
  function copyOut(name, size, next) {
    var k = Math.ceil(next / CHUNK);
    return {
      line: '*dd if=' + name + ' of=/dev/c0d0 bs=' + CHUNK + ' seek=' + k + ' 2>/dev/null; sync\r',
      offset: k * CHUNK,
      next: (k + Math.ceil(size / CHUNK)) * CHUNK + GAP
    };
  }

  function latin1(bytes) {
    var s = '';
    for (var i = 0; i < bytes.length; i += 8192) {
      s += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
    }
    return s;
  }

  return {
    tokenTable: tokenTable, isTokenised: isTokenised, detokenise: detokenise,
    textLines: textLines, programLines: programLines, keys: keys,
    upload: upload, latin1: latin1, isListing: isListing,
    sizeLine: sizeLine, fileSize: fileSize, copyOut: copyOut
  };
})();

if (typeof module !== 'undefined') module.exports = BBCLoad;
