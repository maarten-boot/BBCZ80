// The test of the web version (tools/mkweb.py --test), in Node:
//	node test.js R68K_JS TOKENS_JSON TESTS_DIR REF_DIR
// Boots the emulator, runs the asm demo from the menu, then types the
// upstream test programs (TESTS_DIR/*.BBC) in through loader.js, runs them
// and compares their output with the bascheck references (REF_DIR/u_*.ref).
'use strict';
const fs = require('fs');
const path = require('path');
const BBCLoad = require('./loader.js');

const [r68kJs, tokensJson, testsDir, refDir] = process.argv.slice(2);
const tokens = BBCLoad.tokenTable(JSON.parse(fs.readFileSync(tokensJson)));
// the programs that run on their own (bascheck's u_*.in: CHAIN "NAME")
const PROGRAMS = ['BYREFTST', 'EXITTEST', 'FORTEST', 'INT32TST', 'SLICETST'];

let out = '', mark = 0, M;
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

async function main() {
  M = await require(path.resolve(r68kJs))({
    r68kOutput: (b) => { out += Buffer.from(b).toString('latin1'); },
  });
  let failed = 0;
  await until('Return: BASIC prompt) ?', 60);
  console.log(`menu after ${secs()}`);
  send('5\r');
  const asm = await until('for the menu', 120);
  const ok = asm.includes('CALL upper: HELLO FROM THE 68000!');
  console.log(`${ok ? 'ok  ' : 'FAIL'}  asm demo (${secs()})`);
  if (!ok) failed++;
  await until('\n>', 30);

  for (const name of PROGRAMS) {
    const lines = BBCLoad.programLines(fs.readFileSync(path.join(testsDir, name + '.BBC')), tokens);
    send(BBCLoad.keys(lines) + 'RUN\r');
    await until('\n>RUN', 600);
    const got = (await until('\n>', 600)).replace(/\r/g, '').replace(/^\n/, '').replace(/>$/, '');
    const ref = fs.readFileSync(path.join(refDir, 'u_' + name.toLowerCase() + '.ref'), 'latin1');
    const same = got.trim() === ref.replace(/\r/g, '').trim();
    console.log(`${same ? 'ok  ' : 'FAIL'}  ${name}: ${lines.length} lines typed in and run (${secs()})`);
    if (!same) {
      failed++;
      console.log('--- got\n' + got + '\n--- expected\n' + ref);
    }
  }
  console.log(failed ? `${failed} failed` : 'all ok');
  process.exit(failed ? 1 : 0);
}

main().catch((e) => {
  console.log('FAIL ' + e.message + '\n--- output\n' + out.slice(-2000));
  process.exit(1);
});
