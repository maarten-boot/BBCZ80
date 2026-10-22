// The page of BBC BASIC 68000 (page.html): the terminal, the emulator
// (R68K, from r68k.js) and the toolbar.  BBC_BARE (page.html, from
// mkweb.py): bare BBC BASIC, whose files are on the SD card's FAT16 file
// system, which the page reads and writes itself (fat.js); otherwise
// Minix, which copies files to and from the card with dd.
(function () {
  'use strict';

  var COLS = 80, ROWS = 24;
  var screenEl = document.getElementById('screen');
  var statusEl = document.getElementById('status');
  var stopBtn = document.getElementById('stop');
  var M = null;			// the emulator module, once it runs
  var typing = null;		// timer while keys are typed in
  var lineOut = null;		// output while typeLines waits for a prompt
  var tail = '';		// the last of the output: where is BASIC?
  var sdNext = 1 << 20;		// free space on the SD card (loader.js)
  var card = null;		// the card's file system (bare: fat.js)

  var term = new Terminal({
    cols: COLS, rows: ROWS, scrollback: 0, cursorBlink: true,
    fontFamily: 'ui-monospace, "DejaVu Sans Mono", Menlo, Consolas, "Liberation Mono", monospace',
    theme: { background: '#0b0c0e', foreground: '#e8e3c8', cursor: '#f0b429' }
  });
  term.open(screenEl);

  // the font size that fits 80 x 24 into the window
  function fit() {
    var w = Math.min(window.innerWidth - 40, 1100);
    var h = window.innerHeight - screenEl.getBoundingClientRect().top - 60;
    var size = Math.floor(Math.min(w / (COLS * 0.6), Math.max(h, 240) / (ROWS * 1.2)));
    size = Math.max(7, Math.min(size, 22));
    if (term.options.fontSize !== size) term.options.fontSize = size;
  }
  fit();
  window.addEventListener('resize', fit);

  function status(text, busy) {
    statusEl.textContent = text;
    statusEl.classList.toggle('busy', !!busy);
  }

  function send(text) {
    if (!M) return;
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      if (c < 256) M._r68k_key(c);
    }
  }

  R68K({
    r68kOutput: function (bytes) {
      var text = BBCLoad.latin1(bytes);
      term.write(text);
      if (lineOut !== null) lineOut += text;
      tail = (tail + text).slice(-200);
    },
    printErr: function (s) { console.warn(s); },
    sdFormat: BBC_BARE
  }).then(function (mod) {
    M = mod;
    if (BBC_BARE) card = BBCFat.card(M.r68kSdRead, M.r68kSdWrite);
    status('Running');
    term.onData(send);
    term.focus();
  }, function (e) {
    status('The emulator did not start: ' + e);
  });

  // type lines at the > prompt, each when the prompt is back (loader.js
  // says why); then done(the output of each line)
  function typeLines(lines, what, done) {
    var i = 0, total = lines.length, outs = [];
    stopBtn.hidden = false;
    clearInterval(typing);
    lineOut = '';
    send(lines[0]);
    typing = setInterval(function () {
      if (lineOut.indexOf('\n>') < 0 || M._r68k_pending()) {
        status(what + ' (' + (i + 1) + '/' + total + ')', true);
        return;
      }
      outs.push(lineOut);
      if (++i < total) {
        lineOut = '';
        send(lines[i]);
        return;
      }
      clearInterval(typing);
      typing = null;
      lineOut = null;
      stopBtn.hidden = true;
      done(outs);
    }, 50);
    term.focus();
  }

  // Uploads and downloads type *commands at BASIC's > prompt.  then() runs
  // there: at once if BASIC is at the prompt; else (a program's INPUT,
  // such as the demo menu, a running program, a half typed line) after
  // Escape has brought it there.  Not at the Minix shell.
  function toPrompt(what, then) {
    var atPrompt = /(^|\n)>$/;
    if (atPrompt.test(tail)) return then();
    if (/# $/.test(tail)) {
      status(what + ': BBC BASIC is not running (type bbcbasic at the # prompt)');
      return;
    }
    status(what + ': Escape, to get to the > prompt', true);
    send('\x1b');
    var t0 = Date.now();
    typing = setInterval(function () {		// (busy meanwhile)
      if (atPrompt.test(tail) && !M._r68k_pending()) {
        clearInterval(typing);
        typing = null;
        then();
      } else if (Date.now() - t0 > 5000) {
        clearInterval(typing);
        typing = null;
        status(what + ': BBC BASIC is not at its > prompt; get there and try again');
      }
    }, 50);
  }

  // Load program: the files go to the SD card, dd copies them into BASIC's
  // directory (loader.js); one program is loaded too (LOAD, or NEW and
  // *EXEC for a listing); several files, or one that is not a program,
  // are copied as they are, for CHAIN, LOAD or OPENIN.
  function loadFiles(list) {
    var files = Array.prototype.slice.call(list);	// (the input is cleared)
    if (!M || !files.length || typing) return;
    var done = 0, ups = [];
    files.forEach(function (file, i) {
      var r = new FileReader();
      r.onload = function () {
        ups[i] = { file: file, bytes: new Uint8Array(r.result) };
        if (++done === files.length) copyFiles(ups);
      };
      r.readAsArrayBuffer(file);
    });
  }

  function copyFiles(ups) {
    var lines = [], names = [];
    if (card) return copyBare(ups);
    ups.forEach(function (u) {
      var up = BBCLoad.upload(u.file.name, u.bytes, BBC_TOKENS, sdNext, ups.length === 1);
      up.writes.forEach(function (w) { M.r68kSdWrite(w.offset, w.bytes); });
      sdNext = up.next;
      lines = lines.concat(up.copy);
      names.push(up.name);
      u.up = up;
    });
    var one = ups.length === 1 ? ups[0].up : null;
    if (one) lines = lines.concat(one.load);
    function copied() {
      if (!one) status(names.length + ' files copied: ' + names.join(', ') + '; CHAIN or LOAD them');
      else if (one.tokenised) status(one.name + ' loaded (' + one.size + ' bytes); type RUN');
      else if (one.listing) status(one.name + ' (a listing) being read in by *EXEC; then type RUN');
      else status(one.name + ' copied (' + one.size + ' bytes; not a program)');
    }
    toPrompt('Load program', function () {
      typeLines(lines, 'Copying ' + names.join(', '), copied);
    });
  }

  // bare: the files straight onto the card; one program is loaded
  function copyBare(ups) {
    var names = [], one = null;
    try {
      ups.forEach(function (u) {
        var pr = BBCLoad.prepare(u.file.name, u.bytes, ups.length === 1, BBCFat.make83);
        pr.name = card.writeFile(pr.name, pr.data);
        names.push(pr.name);
        if (ups.length === 1) one = pr;
      });
    } catch (e) {
      status('Load program: ' + e.message);
      return;
    }
    if (!one || !one.load.length) {
      status((one ? one.name + ' (' + one.size + ' bytes; not a program)' : names.length +
              ' files') + ' copied to the SD card' + (one ? '' : ': ' + names.join(', ')));
      return;
    }
    toPrompt('Load program', function () {
      typeLines(one.load, 'Loading ' + one.name, function () {
        status(one.tokenised ? one.name + ' loaded (' + one.size + ' bytes); type RUN'
               : one.name + ' (a listing) being read in by *EXEC; then type RUN');
      });
    });
  }

  // Download: wc -c finds the file and its size, dd copies it to the SD
  // card (and sync), the page reads it from there and saves it
  var dlName = document.getElementById('dlname');
  function download() {
    var name = dlName.value;
    if (!M || !name.trim() || typing) return;
    if (card) return downloadBare(name.trim());
    function save(f, c) {
      var bytes = M.r68kSdRead(c.offset, f.size);
      saveAs(f.name.replace(/^.*\//, ''), bytes);
      status(f.name + ': ' + bytes.length + ' bytes downloaded');
    }
    function found(outs) {
      var f = BBCLoad.fileSize(outs[0], name);
      if (!f) {
        status(name + ': no such file in BASIC\'s directory');
        return;
      }
      var c = BBCLoad.copyOut(f.name, f.size, sdNext);
      sdNext = c.next;
      typeLines([c.line], 'Copying ' + f.name, function () { save(f, c); });
    }
    toPrompt('Download', function () {
      typeLines([BBCLoad.sizeLine(name)], 'Finding ' + name, found);
    });
  }
  // bare: straight off the card (a name without an extension also as
  // name.BBC, as SAVE writes it)
  function downloadBare(name) {
    var tries = /\.[^\/]*$/.test(name) ? [name] : [name, name + '.BBC'], bytes = null, n;
    for (var i = 0; i < tries.length && !bytes; i++) {
      n = tries[i];
      try { bytes = card.readFile(n); } catch (e) { bytes = null; }
    }
    if (!bytes) {
      status(name + ': no such file on the SD card');
      return;
    }
    saveAs(n.replace(/^.*\//, '').toUpperCase(), bytes);
    status(n.toUpperCase() + ': ' + bytes.length + ' bytes downloaded');
  }

  function saveAs(name, bytes) {
    var a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([bytes], { type: 'application/octet-stream' }));
    a.download = name;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(function () { URL.revokeObjectURL(a.href); }, 10000);
  }

  document.getElementById('download').addEventListener('click', download);
  dlName.addEventListener('keydown', function (e) {
    if (e.key === 'Enter') download();
  });

  document.getElementById('file').addEventListener('change', function (e) {
    loadFiles(e.target.files);
    e.target.value = '';
  });
  stopBtn.addEventListener('click', function () {
    if (M) M._r68k_drop();
    clearInterval(typing);
    typing = null;
    lineOut = null;
    stopBtn.hidden = true;
    status('Stopped');
    term.focus();
  });
  screenEl.addEventListener('dragover', function (e) {
    e.preventDefault();
    screenEl.classList.add('drop');
  });
  screenEl.addEventListener('dragleave', function () { screenEl.classList.remove('drop'); });
  screenEl.addEventListener('drop', function (e) {
    e.preventDefault();
    screenEl.classList.remove('drop');
    loadFiles(e.dataTransfer.files);
  });

  document.getElementById('speed').addEventListener('change', function (e) {
    if (M) M._r68k_speed(+e.target.value);
    term.focus();
  });
  document.getElementById('reset').addEventListener('click', function () {
    location.reload();
  });
  var helpBtn = document.getElementById('helpbtn'), help = document.getElementById('help');
  helpBtn.addEventListener('click', function () {
    help.hidden = !help.hidden;
    helpBtn.setAttribute('aria-expanded', String(!help.hidden));
    fit();
  });
})();
