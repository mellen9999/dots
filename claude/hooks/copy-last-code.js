#!/usr/bin/env bun
// Stop hook: extract the last fenced code block from the assistant's most
// recent reply and pipe it to wl-copy. Silent no-op if there's no code.
import { readFileSync } from 'fs'
import { execFileSync } from 'child_process'

let input
try { input = JSON.parse(readFileSync(0, 'utf8')) } catch { process.exit(0) }
const tp = input.transcript_path
if (!tp) process.exit(0)

let lines
try { lines = readFileSync(tp, 'utf8').trim().split('\n') } catch { process.exit(0) }

let lastText = ''
for (let i = lines.length - 1; i >= 0; i--) {
  try {
    const obj = JSON.parse(lines[i])
    if (obj.type !== 'assistant') continue
    const blocks = obj.message?.content || []
    const texts = blocks.filter(b => b.type === 'text').map(b => b.text).join('\n')
    if (texts.trim()) { lastText = texts; break }
  } catch (_) {}
}
if (!lastText) process.exit(0)

const matches = [...lastText.matchAll(/```[a-zA-Z0-9_+-]*\n([\s\S]*?)\n```/g)]
if (!matches.length) process.exit(0)

const code = matches[matches.length - 1][1]
try { execFileSync('wl-copy', [], { input: code }) } catch {}
