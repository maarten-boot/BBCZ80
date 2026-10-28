// The test of the web version (tools/mkweb.py --test), in Node:
//	node test.js R68K_JS TOKENS_JSON TESTS_DIR REF_DIR bare|minix
// bare: bare BBC BASIC, files on the SD card's FAT16 file system, which
// the test reads and writes as the page does (fat.js); minix: files copied
// with dd as the Minix page does.
// Boots the emulator to the > prompt and runs the asm demo from the menu
// (CHAIN "menu").  Then, as the
// page's Load program does (loader.js upload: the SD card and dd):
// * the upstream test programs (TESTS_DIR/*.BBC), each loaded, run and
//   compared with its bascheck reference (REF_DIR/u_*.ref);
// * a text listing (the demo's sieve.bas), read in with *EXEC and run;
// * two files at once, the second CHAINed.
// And downloads (loader.js sizeLine, copyOut; pre.js r68kSdRead):
// * a program SAVEd and downloaded: the loaded file up to its end;
// * a 40000-byte binary file uploaded as data and downloaded: identical;
// * *SPOOL output downloaded.
'use strict';
const fs = require('fs');
const path = require('path');
const BBCLoad = require('./loader.js');
const BBCFat = require('./fat.js');

const [r68kJs, tokensJson, testsDir, refDir, mode] = process.argv.slice(2);
const bare = mode !== 'minix';
let card = null;
const tokens = BBCLoad.tokenTable(JSON.parse(fs.readFileSync(tokensJson)));
// the programs that run on their own (bascheck's u_*.in: CHAIN "NAME")
const PROGRAMS = ['BYREFTST', 'EXITTEST', 'FORTEST', 'INT32TST', 'SLICETST'];

let out = '', mark = 0, M, sdNext = 1 << 20;
const t0 = Date.now();

function send(s) {
  for (const c of s) M._r68k_key(c.charCodeAt(0));
}

// wait for text after the mark; resolves with the output up to its end
function until(text, secs) {
  return new Promise((resolve, reject) => {
    const end = Date.now() + secs * 1000;
    (function check() {
      const i = out.indexOf(text, mark);
      if (i >= 0) {
        const got = out.slice(mark, i + text.length);
        mark = i + text.length;
        return resolve(got);
      }
      if (Date.now() > end) return reject(new Error('timeout waiting for ' + JSON.stringify(text)));
      setTimeout(check, 20);
    })();
  });
}

function secs() { return ((Date.now() - t0) / 1000).toFixed(1) + ' s'; }

// upload as the page does: the lines that copy (and with load, load) it
function upload(name, bytes, load) {
  if (bare) {
    const pr = BBCLoad.prepare(name, bytes, load, BBCFat.make83);
    card.writeFile(pr.name, pr.data);
    return pr.load;
  }
  const up = BBCLoad.upload(name, bytes, tokens, sdNext, load);
  for (const w of up.writes) M.r68kSdWrite(w.offset, w.bytes);
  sdNext = up.next;
  return up.copy.concat(load ? up.load : []);
}

// type lines as the page does, each after the prompt is back; the output
// of the last
async function typeLines(lines) {
  let o = '';
  for (const l of lines) {
    send(l);
    await until(l.replace(/\r$/, ''), 60);
    o = await until('\n>', 120);
  }
  return o;
}

// download as the page does: the bytes, or null
async function download(name) {
  if (bare) {
    for (const n of /\.[^/]*$/.test(name) ? [name] : [name, name + '.BBC']) {
      const b = card.readFile(n);
      if (b) return b;
    }
    return null;
  }
  const f = BBCLoad.fileSize(await typeLines([BBCLoad.sizeLine(name)]), name);
  if (!f) return null;
  const c = BBCLoad.copyOut(f.name, f.size, sdNext);
  sdNext = c.next;
  await typeLines([c.line]);
  return M.r68kSdRead(c.offset, f.size);
}

async function main() {
  M = await require(path.resolve(r68kJs))({
    r68kOutput: (b) => { out += Buffer.from(b).toString('latin1'); },
    sdFormat: bare,
  });
  if (bare) card = BBCFat.card(M.r68kSdRead, M.r68kSdWrite);
  let failed = 0;
  await until('\n>', 60);
  console.log(`prompt after ${secs()}`);
  send('CHAIN "menu"\r');
  await until('Return: BASIC prompt) ?', 30);
  send('5\r');
  const asm = await until('for the menu', 120);
  const ok = asm.includes('CALL upper: HELLO FROM THE 68000!');
  console.log(`${ok ? 'ok  ' : 'FAIL'}  asm demo (${secs()})`);
  if (!ok) failed++;
  await until('\n>', 30);

  for (const name of PROGRAMS) {
    const t1 = Date.now();
    await typeLines(upload(name + '.BBC', fs.readFileSync(path.join(testsDir, name + '.BBC')), true));
    const up = (Date.now() - t1) / 1000;
    send('RUN\r');
    await until('RUN\r', 60);
    const got = (await until('\n>', 600)).replace(/\r/g, '').replace(/^\n/, '').replace(/>$/, '');
    const ref = fs.readFileSync(path.join(refDir, 'u_' + name.toLowerCase() + '.ref'), 'latin1');
    const same = got.trim() === ref.replace(/\r/g, '').trim();
    console.log(`${same ? 'ok  ' : 'FAIL'}  ${name}: uploaded and loaded in ${up.toFixed(1)} s, run (${secs()})`);
    if (!same) {
      failed++;
      console.log('--- got\n' + got + '\n--- expected\n' + ref);
    }
  }

  // a listing: NEW and *EXEC, then RUN (Return at its INPUT)
  let t1 = Date.now();
  await typeLines(upload('sieve.bas', fs.readFileSync(path.join(path.dirname(__filename), '..', 'demo', 'progs', 'sieve.bas')), true));
  await until('250 ENDPROC', 60);
  await until('\n>', 60);
  const ex = (Date.now() - t1) / 1000;
  send('RUN\r');
  await until('?', 60);
  send('\r');
  let ok2 = (await until('\n>', 120)).includes('There are 5133 primes up to 50000');
  console.log(`${ok2 ? 'ok  ' : 'FAIL'}  a listing (sieve.bas): uploaded and *EXECed in ${ex.toFixed(1)} s, run`);
  if (!ok2) failed++;

  // two files, then CHAIN the second
  t1 = Date.now();
  await typeLines(upload('EXITTEST.BBC', fs.readFileSync(path.join(testsDir, 'EXITTEST.BBC')), false).concat(
                 upload('FORTEST.BBC', fs.readFileSync(path.join(testsDir, 'FORTEST.BBC')), false)));
  send('CHAIN "FORTEST"\r');
  ok2 = (await until('\n>', 300)).includes('FOR...NEXT tests completed.');
  console.log(`${ok2 ? 'ok  ' : 'FAIL'}  two files uploaded together, CHAIN "FORTEST" (${((Date.now() - t1) / 1000).toFixed(1)} s)`);
  if (!ok2) failed++;
  // downloads: a program SAVEd (FORTEST, CHAINed just now)
  await typeLines(['SAVE "copy"\r']);
  let got = await download('copy');
  const orig = fs.readFileSync(path.join(testsDir, 'FORTEST.BBC'));
  ok2 = got !== null && got.length > 3 && got.length <= orig.length &&
    Buffer.from(got).equals(orig.subarray(0, got.length)) &&
    got[got.length - 3] === 0 && got[got.length - 1] === 0xFF;
  console.log(`${ok2 ? 'ok  ' : 'FAIL'}  SAVE "copy", download copy(.bbc): ${got ? got.length : 'no'} bytes, the program as loaded`);
  if (!ok2) failed++;

  // a binary file both ways
  const bin = Buffer.alloc(40000);
  for (let i = 0; i < bin.length; i++) bin[i] = (i * 7 + (i >> 8)) & 0xFF;
  await typeLines(upload('data.bin', bin, false));
  got = await download('data.bin');
  ok2 = got !== null && Buffer.from(got).equals(bin);
  console.log(`${ok2 ? 'ok  ' : 'FAIL'}  40000-byte binary file uploaded and downloaded: ${ok2 ? 'identical' : 'different'}`);
  if (!ok2) failed++;

  // *SPOOL output
  await typeLines(['*SPOOL out.txt\r', 'PRINT "hello from the spool"\r', '*SPOOL\r']);
  got = await download('out.txt');
  ok2 = got !== null && Buffer.from(got).toString('latin1').includes('hello from the spool');
  console.log(`${ok2 ? 'ok  ' : 'FAIL'}  *SPOOL out.txt downloaded (${got ? got.length : 'no'} bytes)`);
  if (!ok2) failed++;
  ok2 = (await download('nosuchfile')) === null;
  console.log(`${ok2 ? 'ok  ' : 'FAIL'}  a missing file is reported`);
  if (!ok2) failed++;

  console.log(failed ? `${failed} failed` : 'all ok');
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.log('FAIL ' + e.message + '\n--- output\n' + out.slice(-2000));
  process.exit(1);
});
