#!/usr/bin/env python3
"""The web page in a real browser (tools/mkweb.py --test, when chromium and
the Python websockets module are there), through the DevTools protocol:

	browsertest.py PAGE TESTS_DIR

Opens PAGE (bbc68k.html) as a file in headless Chromium and, with key
events as a user types them:
* runs the asm demo from the menu;
* stops life with Escape;
* loads TESTS_DIR/FORTEST.BBC with the Load program button (its file
  input), types RUN and checks the result;
* runs a timing loop at full speed and at 10 MHz.
The screen is read from xterm.js's rows in the page.
"""

import asyncio
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.request

import websockets

PORT = 9337


class Page:
    def __init__(self, ws):
        self.ws, self.n = ws, 0

    async def call(self, method, **params):
        self.n += 1
        await self.ws.send(json.dumps({'id': self.n, 'method': method, 'params': params}))
        while True:
            m = json.loads(await self.ws.recv())
            if m.get('id') == self.n:
                if 'error' in m:
                    raise RuntimeError('%s: %s' % (method, m['error']))
                return m.get('result', {})

    async def js(self, expr):
        r = await self.call('Runtime.evaluate', expression=expr, returnByValue=True)
        return r.get('result', {}).get('value')

    async def screen(self):
        return await self.js("document.querySelector('.xterm-rows').innerText")

    async def wait(self, text, secs, where='screen'):
        end = time.time() + secs
        while time.time() < end:
            s = await (self.screen() if where == 'screen' else
                       self.js("document.getElementById('status').textContent"))
            if s and text in s:
                return s
            await asyncio.sleep(0.2)
        raise TimeoutError('%r not on the %s; it shows:\n%s' % (text, where, s))

    async def key(self, name, code, vk):
        for t in ('keyDown', 'keyUp'):
            await self.call('Input.dispatchKeyEvent', type=t, key=name, code=code,
                            windowsVirtualKeyCode=vk, nativeVirtualKeyCode=vk)

    async def type(self, text):
        for c in text:
            if c == '\r':
                await self.call('Input.dispatchKeyEvent', type='keyDown', key='Enter',
                                code='Enter', windowsVirtualKeyCode=13, text='\r')
                await self.call('Input.dispatchKeyEvent', type='keyUp', key='Enter',
                                code='Enter', windowsVirtualKeyCode=13)
            else:
                await self.call('Input.insertText', text=c)


async def run(page_file, tests):
    prof = tempfile.mkdtemp()
    chrome = subprocess.Popen(
        [shutil.which('chromium') or 'chromium', '--headless=new', '--no-sandbox',
         '--disable-gpu', '--remote-debugging-port=%d' % PORT, '--user-data-dir=' + prof,
         '--window-size=1200,900', 'file://' + os.path.abspath(page_file)],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    failed = 0
    try:
        for _ in range(100):
            try:
                targets = json.load(urllib.request.urlopen('http://127.0.0.1:%d/json' % PORT))
                url = [t for t in targets if t['type'] == 'page'][0]['webSocketDebuggerUrl']
                break
            except Exception:
                await asyncio.sleep(0.2)
        async with websockets.connect(url, max_size=None) as ws:
            p = Page(ws)
            t0 = time.time()
            await p.wait('Return: BASIC prompt) ?', 60)
            print('ok    boot to the menu (%.1f s)' % (time.time() - t0))
            await p.js("document.querySelector('.xterm-helper-textarea').focus()")

            await p.type('5\r')
            s = await p.wait('for the menu', 60)
            ok = 'CALL upper: HELLO FROM THE 68000!' in s
            print('%s  asm demo, typed with key events' % ('ok  ' if ok else 'FAIL'))
            failed += not ok

            await p.type('CHAIN "life"\r')
            await p.wait('generation 2', 30)
            await p.key('Escape', 'Escape', 27)
            s = await p.wait('Escape at line', 30)
            print('ok    Escape stops life')

            await p.type('CLS\r')
            await p.call('DOM.enable')
            doc = await p.call('DOM.getDocument')
            node = await p.call('DOM.querySelector', nodeId=doc['root']['nodeId'],
                                selector='#file')
            await p.call('DOM.setFileInputFiles', nodeId=node['nodeId'],
                         files=[os.path.join(os.path.abspath(tests), 'FORTEST.BBC')])
            st = await p.wait('typed in', 120, where='status')
            await p.type('RUN\r')
            s = await p.wait('FOR...NEXT tests completed.', 120)
            print('ok    Load program: FORTEST.BBC (status "%s"), RUN completes' % st)

            loop = 'T%=TIME:FOR I%=1 TO 20000:NEXT:PRINT "loop ";TIME-T%\r'

            async def timed():
                await p.type('CLS\r' + loop)
                end = time.time() + 120
                while time.time() < end:
                    m = re.search(r'^loop (\d+)', await p.screen(), re.M)
                    if m:
                        return int(m.group(1))
                    await asyncio.sleep(0.2)
                raise TimeoutError('no loop time')

            fast = await timed()
            await p.js("var s=document.getElementById('speed'); s.value='10';"
                       "s.dispatchEvent(new Event('change'))")
            await p.js("document.querySelector('.xterm-helper-textarea').focus()")
            slow = await timed()
            ok = slow > fast
            print('%s  speed: 20000 empty loops take %d cs at full speed, %d cs at 10 MHz'
                  % ('ok  ' if ok else 'FAIL', fast, slow))
            failed += not ok
            await p.call('Page.captureScreenshot')
    except Exception as e:
        print('FAIL  %s' % e)
        failed += 1
    finally:
        chrome.kill()
        chrome.wait()
        shutil.rmtree(prof, ignore_errors=True)
    print('browser: %s' % ('all ok' if not failed else '%d failed' % failed))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(asyncio.run(run(sys.argv[1], sys.argv[2])))
