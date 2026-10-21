// The page of BBC BASIC 68000 (page.html): the terminal, the emulator
// (R68K, from r68k.js) and the toolbar.
(function () {
  'use strict';

  var COLS = 80, ROWS = 24;
  var screenEl = document.getElementById('screen');
  var statusEl = document.getElementById('status');
  var stopBtn = document.getElementById('stop');
  var M = null;			// the emulator module, once it runs
  var typing = null;		// timer while a program is typed in

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

  function latin1(bytes) {
    var s = '';
    for (var i = 0; i < bytes.length; i += 8192) {
      s += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192));
    }
    return s;
  }

  function send(text) {
    if (!M) return;
    for (var i = 0; i < text.length; i++) {
      var c = text.charCodeAt(i);
      if (c < 256) M._r68k_key(c);
    }
  }

  R68K({
    r68kOutput: function (bytes) { term.write(latin1(bytes)); },
    printErr: function (s) { console.warn(s); }
  }).then(function (mod) {
    M = mod;
    status('Running');
    term.onData(send);
    term.focus();
  }, function (e) {
    status('The emulator did not start: ' + e);
  });

  // typing a program in: progress until the keys are taken
  function typeIn(name, lines) {
    if (!M) return;
    if (!lines.length) {
      status(name + ': no program found');
      return;
    }
    send(BBCLoad.keys(lines));
    var total = M._r68k_pending();
    stopBtn.hidden = false;
    clearInterval(typing);
    typing = setInterval(function () {
      var left = M._r68k_pending();
      if (left === 0) {
        clearInterval(typing);
        typing = null;
        stopBtn.hidden = true;
        status(name + ': ' + lines.length + ' lines typed in; type RUN');
      } else {
        status('Typing ' + name + ': ' + Math.round(100 * (total - left) / total) + '%', true);
      }
    }, 150);
    term.focus();
  }

  function loadFile(file) {
    var r = new FileReader();
    r.onload = function () {
      typeIn(file.name, BBCLoad.programLines(new Uint8Array(r.result), BBC_TOKENS));
    };
    r.readAsArrayBuffer(file);
  }

  document.getElementById('file').addEventListener('change', function (e) {
    if (e.target.files[0]) loadFile(e.target.files[0]);
    e.target.value = '';
  });
  stopBtn.addEventListener('click', function () {
    if (M) M._r68k_drop();
    clearInterval(typing);
    typing = null;
    stopBtn.hidden = true;
    status('Typing stopped');
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
    if (e.dataTransfer.files[0]) loadFile(e.dataTransfer.files[0]);
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
