// BBC BASIC programs to type into the emulated BBC BASIC (src68k/web).
//
// A program file is either tokenised (SAVE of BBC BASIC Z80, CP/M, 68000,
// Windows or SDL: lines of [length][number lo][number hi] text CR, ending
// with a 0 length) or a text listing.  Both become lines of text with line
// numbers, which keys() turns into what is typed at the > prompt: NEW, then
// the lines.  A listing without line numbers (as BBC BASIC for Windows
// saves it as text) is numbered 10, 20, ...
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

  return {
    tokenTable: tokenTable, isTokenised: isTokenised, detokenise: detokenise,
    textLines: textLines, programLines: programLines, keys: keys
  };
})();

if (typeof module !== 'undefined') module.exports = BBCLoad;
