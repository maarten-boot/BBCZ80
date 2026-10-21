// The page of BBC BASIC 68000 (page.html): the terminal, the emulator
// (R68K, from r68k.js) and the toolbar.
(function () {
  'use strict';

  var COLS = 80, ROWS = 24;
  var screenEl = document.getElementById('screen');
  var statusEl = document.getElementById('status');
  var stopBtn = document.getElementById('stop');
  var M = null;			// the emulator module, once it runs
  var typing = null;		// timer while keys are typed in
  var lineOut = null;		// output while typeLines waits for a prompt
  var sdNext = 1 << 20;		// free space on the SD card (loader.js)

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
    },
    printErr: function (s) { console.warn(s); }
  }).then(function (mod) {
    M = mod;
    status('Running');
    term.onData(send);
    term.focus();
  }, function (e) {
    status('The emulator did not start: ' + e);
  });

  // type lines at the > prompt, each when the prompt is back (loader.js
  // says why); then done()
  function typeLines(lines, what, done) {
    var i = 0, total = lines.length;
    stopBtn.hidden = false;
    clearInterval(typing);
    lineOut = '';
    send(lines[0]);
    typing = setInterval(function () {
      if (lineOut.indexOf('\n>') < 0 || M._r68k_pending()) {
        status(what + ' (' + (i + 1) + '/' + total + ')', true);
        return;
      }
      if (++i < total) {
        lineOut = '';
        send(lines[i]);
        return;
      }
      clearInterval(typing);
      typing = null;
      lineOut = null;
      stopBtn.hidden = true;
      done();
    }, 50);
    term.focus();
  }

  // Load program: the files go to the SD card, dd copies them into BASIC's
  // directory (loader.js); one file is loaded too (LOAD, or NEW and *EXEC
  // for a listing), several are left for CHAIN or LOAD.
  function loadFiles(list) {
    var files = Array.prototype.slice.call(list);	// (the input is cleared)
    if (!M || !files.length) return;
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
    ups.forEach(function (u) {
      var up = BBCLoad.upload(u.file.name, u.bytes, BBC_TOKENS, sdNext);
      up.writes.forEach(function (w) { M.r68kSdWrite(w.offset, w.bytes); });
      sdNext = up.next;
      lines = lines.concat(up.copy);
      names.push(up.name);
      u.up = up;
    });
    var one = ups.length === 1 ? ups[0].up : null;
    if (one) lines = lines.concat(one.load);
    typeLines(lines, 'Copying ' + names.join(', '), function () {
      if (!one) status(names.length + ' files copied: ' + names.join(', ') + '; CHAIN or LOAD them');
      else if (one.tokenised) status(one.name + ' loaded (' + one.size + ' bytes); type RUN');
      else status(one.name + ' (a listing) being read in by *EXEC; then type RUN');
    });
  }

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
