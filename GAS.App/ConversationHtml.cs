using System.Text.Json;

namespace GAS.App
{
    /// <summary>
    /// Provides the self-contained HTML/CSS/JS conversation frontend
    /// that is loaded into the WebView2 control.
    /// All application logic stays in WPF; this file is UI-only.
    /// </summary>
    internal static class ConversationHtml
    {
        public static string GetHtml() => HtmlContent;

        public static string BuildCall(string method, object payload)
        {
            var json = JsonSerializer.Serialize(payload);
            var jsLiteral = JsonSerializer.Serialize(json);
            return $"window.{method}({jsLiteral})";
        }

        private const string HtmlContent = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>GAS</title>
<style>
/* ─── Reset ─────────────────────────────────────────────────────── */
*,*::before,*::after{box-sizing:border-box;margin:0;padding:0}

html,body{
  height:100%;
  background:#0C0C0F;
  color:#C9D5E0;
  font-family:'Segoe UI Variable Text','Segoe UI',system-ui,sans-serif;
  font-size:14px;
  line-height:1.7;
  overflow:hidden;
  -webkit-font-smoothing:antialiased;
}

/* ─── Scroll container ───────────────────────────────────────────── */
#scroll{
  height:100%;
  overflow-y:auto;
  overflow-x:hidden;
  padding:20px 0 40px;
}
#scroll::-webkit-scrollbar{width:5px}
#scroll::-webkit-scrollbar-track{background:transparent}
#scroll::-webkit-scrollbar-thumb{background:#1A1A25;border-radius:3px}
#scroll::-webkit-scrollbar-thumb:hover{background:#252535}

/* ─── Messages container ─────────────────────────────────────────── */
#messages{padding:0 22px;max-width:100%}

/* ─── Empty state ────────────────────────────────────────────────── */
#empty{
  display:flex;flex-direction:column;align-items:center;justify-content:center;
  min-height:calc(100vh - 60px);
  color:#1A1A2E;user-select:none;pointer-events:none;
}
#empty svg{margin-bottom:16px;opacity:.3}
#empty h2{font-size:15px;font-weight:600;color:#263040;margin-bottom:6px}
#empty p{font-size:12px;color:#1A1A2E;text-align:center;line-height:1.5}

/* ─── Timestamp ──────────────────────────────────────────────────── */
.ts{
  text-align:center;font-size:10px;color:#1C2232;
  margin:16px 0 10px;user-select:none;
}

/* ─── User message ───────────────────────────────────────────────── */
.user-row{display:flex;justify-content:flex-end;margin:12px 0 16px}
.user-bubble{
  background:linear-gradient(140deg,#4338CA,#6366F1);
  color:#fff;
  border-radius:18px 18px 4px 18px;
  padding:10px 16px;
  max-width:82%;
  font-size:13.5px;
  line-height:1.6;
  cursor:text;
  user-select:text;
  white-space:pre-wrap;word-break:break-word;
}

/* ─── Agent Turn Container (Single Badge Per Turn) ─────────────────── */
.agent-turn{
  margin:16px 0 20px;
}
.agent-badge{
  display:flex;align-items:center;gap:7px;
  margin-bottom:10px;user-select:none;
}
.agent-dot{
  width:19px;height:19px;border-radius:50%;flex-shrink:0;
  background:linear-gradient(140deg,#4338CA,#7C3AED);
  display:flex;align-items:center;justify-content:center;
  font-size:9px;font-weight:700;color:#fff;
}
.agent-label{font-size:11px;font-weight:600;color:#4A5E78}

.turn-body{
  display:flex;flex-direction:column;gap:10px;
}

/* Agent text block */
.agent-text{
  font-size:13.5px;line-height:1.75;
  color:#B8C5D4;
  cursor:text;user-select:text;
  word-break:break-word;
}
.agent-text.streaming{white-space:pre-wrap}
.agent-text.streaming::after{
  content:'▋';
  animation:blink .75s step-end infinite;
  color:#6366F1;margin-left:1px;
}
@keyframes blink{0%,100%{opacity:1}50%{opacity:0}}

/* ─── Markdown ───────────────────────────────────────────────────── */
.agent-text p{margin-bottom:10px}
.agent-text p:last-child{margin-bottom:0}
.agent-text h1{font-size:18px;font-weight:700;color:#E2ECF5;margin:16px 0 8px}
.agent-text h2{font-size:16px;font-weight:600;color:#D0DCE8;margin:14px 0 6px}
.agent-text h3{font-size:14px;font-weight:600;color:#B8C5D4;margin:12px 0 4px}
.agent-text strong{font-weight:600;color:#D0DCE8}
.agent-text em{font-style:italic;color:#8898AA}
.agent-text del{text-decoration:line-through;color:#4A5568}
.agent-text a{color:#818CF8;text-decoration:none}
.agent-text a:hover{text-decoration:underline}
.agent-text hr{border:none;border-top:1px solid #0F1626;margin:16px 0}
.agent-text ul,.agent-text ol{padding-left:20px;margin-bottom:10px}
.agent-text li{margin-bottom:4px}

/* Inline code */
.agent-text code{
  font-family:'Cascadia Code','Cascadia Mono',Consolas,monospace;
  font-size:12px;
  background:#0D1422;color:#E06C75;
  padding:2px 5px;border-radius:4px;
  border:1px solid #1A2336;
}

/* ─── Code blocks ────────────────────────────────────────────────── */
.code-block{
  position:relative;
  background:#060A12;
  border:1px solid #141E30;
  border-radius:8px;
  margin:12px 0;overflow:hidden;
}
.code-header{
  display:flex;align-items:center;justify-content:space-between;
  padding:5px 14px;
  background:#0A1020;
  border-bottom:1px solid #141E30;
}
.code-lang{
  font-family:'Cascadia Code',Consolas,monospace;
  font-size:10px;color:#4A5E78;letter-spacing:.05em;
}
.copy-btn{
  font-family:'Segoe UI Variable Text','Segoe UI',sans-serif;
  font-size:10px;color:#4A5E78;background:none;
  border:1px solid #1A2840;border-radius:4px;
  padding:2px 9px;cursor:pointer;
  transition:color .15s,border-color .15s;
}
.copy-btn:hover{color:#8898AA;border-color:#2A3850}
.copy-btn.ok{color:#3FB950;border-color:#1A3A20}
.code-block pre{padding:14px 16px;overflow-x:auto;margin:0}
.code-block pre::-webkit-scrollbar{height:4px}
.code-block pre::-webkit-scrollbar-thumb{background:#1A2840;border-radius:2px}
.code-block code{
  font-family:'Cascadia Code','Cascadia Mono',Consolas,monospace;
  font-size:12px;line-height:1.65;
  color:#A8B8CC;background:none;
  padding:0;border:none;border-radius:0;white-space:pre;
}

/* ─── Reasoning section ──────────────────────────────────────────── */
.reasoning-wrap{margin:4px 0}
.reasoning-header{
  display:flex;align-items:center;gap:6px;
  padding:4px 0;cursor:pointer;user-select:none;
  color:#3A4A60;font-size:11px;
  transition:color .12s;
}
.reasoning-header:hover{color:#5A6B80}
.r-caret{font-size:8px;transition:transform .15s;display:inline-block}
.r-caret.open{transform:rotate(90deg)}
.r-lbl{font-weight:500}
.r-preview{
  color:#2A3548;font-style:italic;font-size:11px;margin-left:4px;
  overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
  flex:1;min-width:0;
}
.reasoning-body{
  display:none;
  margin:4px 0 4px 10px;
  padding:8px 12px;
  background:#08090E;
  border-left:2px solid #1A2A3A;
  border-radius:0 4px 4px 0;
  font-size:12.5px;color:#4A5E78;
  font-style:italic;line-height:1.65;
  white-space:pre-wrap;word-break:break-word;
  max-height:300px;overflow-y:auto;
}
.reasoning-body.open{display:block}
.reasoning-body.streaming::after{
  content:'▋';animation:blink .75s step-end infinite;
  color:#4A6070;margin-left:1px;
}

/* ─── Tool activity ──────────────────────────────────────────────── */
.tool-wrap{margin:4px 0}
.tool-header{
  display:flex;align-items:center;gap:6px;
  padding:4px 8px;
  background:#080B12;
  border:1px solid #101926;
  border-radius:6px;
  cursor:pointer;user-select:none;
  font-size:11.5px;color:#5A6B80;
  transition:background .12s,border-color .12s;
}
.tool-header:hover{background:#0C101A;border-color:#182538;color:#7A8CA0}
.t-caret{font-size:8px;transition:transform .15s;display:inline-block;color:#3A4A60}
.t-caret.open{transform:rotate(90deg)}
.t-name{font-weight:500;color:#7A8CA0}
.t-chip{
  margin-left:auto;font-size:10px;padding:1px 7px;
  border-radius:3px;font-weight:500;
}
.t-chip.running{color:#D97706;background:#181000}
.t-chip.done{color:#10B981;background:#001C10}
.t-chip.error{color:#EF4444;background:#1C0000}
.tool-body{
  display:none;
  margin:4px 0 4px 0;
  padding:8px 12px;
  background:#05070C;
  border:1px solid #0F1724;
  border-radius:6px;
  font-family:'Cascadia Code','Cascadia Mono',Consolas,monospace;
  font-size:11px;color:#5A6B80;
  white-space:pre-wrap;word-break:break-word;
  max-height:220px;overflow-y:auto;
}
.tool-body.open{display:block}

/* ─── Jump to bottom FAB ─────────────────────────────────────────── */
#jmp{
  display:none;position:fixed;bottom:14px;right:16px;
  width:26px;height:26px;border-radius:50%;
  background:#12121C;border:1px solid #1E1E30;
  color:#6366F1;cursor:pointer;font-size:13px;
  align-items:center;justify-content:center;
  z-index:999;transition:background .15s;
}
#jmp:hover{background:#1A1A2A}
#jmp.show{display:flex}

/* ─── Selection colors ───────────────────────────────────────────── */
::selection{background:#3730A3;color:#fff}
</style>
</head>
<body>

<div id="scroll">
  <div id="messages">
    <div id="empty">
      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#263040" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
      </svg>
      <h2>Start a conversation</h2>
      <p>Use the hotkey or command bar<br>to ask GAS anything.</p>
    </div>
  </div>
</div>

<button id="jmp" title="Jump to latest" onclick="scrollToBottom(true)">↓</button>

<script>
'use strict';

// ─── State ─────────────────────────────────────────────────────────────────
const S = {
  turns: {},           // Map of partID -> part metadata
  activeTurnEl: null,  // Current agent turn container element
  lastUserPrompt: '',  // Last prompt text sent by user
  userScrolled: false
};

const scroll = document.getElementById('scroll');
const msgs   = document.getElementById('messages');
const jmp    = document.getElementById('jmp');

// ─── Scroll logic ───────────────────────────────────────────────────────────
scroll.addEventListener('scroll', () => {
  const atBottom = scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 50;
  S.userScrolled = !atBottom;
  jmp.classList.toggle('show', !atBottom);
}, {passive:true});

function scrollToBottom(force) {
  if (force || !S.userScrolled) {
    scroll.scrollTop = scroll.scrollHeight;
    jmp.classList.remove('show');
    S.userScrolled = false;
  }
}

// ─── DOM helpers ────────────────────────────────────────────────────────────
function hideEmpty() {
  const e = document.getElementById('empty');
  if (e) e.remove();
}

function esc(s) {
  return String(s)
    .replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ─── Ensure Active Agent Turn Container ─────────────────────────────────────
// Creates exactly ONE agent turn container with ONE badge per assistant response turn
function getOrCreateActiveTurn() {
  if (!S.activeTurnEl) {
    const turn = document.createElement('div');
    turn.className = 'agent-turn';
    turn.innerHTML = `
      <div class="agent-badge">
        <div class="agent-dot">G</div>
        <span class="agent-label">GAS</span>
      </div>
      <div class="turn-body"></div>`;
    msgs.appendChild(turn);
    S.activeTurnEl = turn.querySelector('.turn-body');
  }
  return S.activeTurnEl;
}

// ─── Tool Output Formatter ─────────────────────────────────────────────────
function formatToolOutput(raw) {
  if (!raw || !raw.trim()) return 'No output details';
  const str = String(raw).trim();

  // If raw XML from OpenCode tool (dir listing, read, etc.)
  if (str.includes('<path>') || str.includes('<entries>') || str.includes('<content>')) {
    let result = '';

    const pathMatch = str.match(/<path>([\s\S]*?)<\/path>/i);
    const typeMatch = str.match(/<type>([\s\S]*?)<\/type>/i);
    const entriesMatch = str.match(/<entries>([\s\S]*?)<\/entries>/i);
    const contentMatch = str.match(/<content>([\s\S]*?)<\/content>/i);

    if (pathMatch) result += `Path: ${pathMatch[1].trim()}\n`;
    if (typeMatch) result += `Type: ${typeMatch[1].trim()}\n`;

    if (entriesMatch) {
      const items = entriesMatch[1].trim().split(/\s+/).filter(Boolean);
      result += `\nEntries (${items.length}):\n` + items.map(i => `  • ${i}`).join('\n');
    } else if (contentMatch) {
      result += `\nContent:\n${contentMatch[1].trim()}`;
    } else {
      // Fallback: strip XML tags cleanly
      result += '\n' + str.replace(/<[^>]+>/g, '').trim();
    }
    return result;
  }

  // If raw JSON object/array
  if ((str.startsWith('{') && str.endsWith('}')) || (str.startsWith('[') && str.endsWith(']'))) {
    try {
      const obj = JSON.parse(str);
      return JSON.stringify(obj, null, 2);
    } catch { }
  }

  return str;
}

// ─── Markdown parser ────────────────────────────────────────────────────────
function md(raw) {
  if (!raw || !raw.trim()) return '';
  const lines = raw.split('\n');
  let out = '', i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const t = line.trim();

    if (t.startsWith('```')) {
      const lang = esc(t.slice(3).trim());
      const code = [];
      i++;
      while (i < lines.length && !lines[i].trim().startsWith('```')) {
        code.push(lines[i]);
        i++;
      }
      i++;
      const escaped = esc(code.join('\n').trimEnd());
      out += `<div class="code-block"><div class="code-header"><span class="code-lang">${lang||'code'}</span><button class="copy-btn" onclick="copyCode(this)">Copy</button></div><pre><code>${escaped}</code></pre></div>`;
      continue;
    }

    if (t.startsWith('### ')) { out += `<h3>${inl(t.slice(4))}</h3>`; i++; continue; }
    if (t.startsWith('## '))  { out += `<h2>${inl(t.slice(3))}</h2>`; i++; continue; }
    if (t.startsWith('# '))   { out += `<h1>${inl(t.slice(2))}</h1>`; i++; continue; }

    if (/^(-{3,}|_{3,}|\*{3,})$/.test(t)) { out += '<hr>'; i++; continue; }

    if (/^[-*•]\s/.test(t)) {
      const items = [];
      while (i < lines.length && /^[-*•]\s/.test(lines[i].trim())) {
        items.push(`<li>${inl(lines[i].trim().slice(2))}</li>`);
        i++;
      }
      out += `<ul>${items.join('')}</ul>`;
      continue;
    }

    if (/^\d+[.)]\s/.test(t)) {
      const items = [];
      while (i < lines.length && /^\d+[.)]\s/.test(lines[i].trim())) {
        items.push(`<li>${inl(lines[i].trim().replace(/^\d+[.)]\s/,''))}</li>`);
        i++;
      }
      out += `<ol>${items.join('')}</ol>`;
      continue;
    }

    if (!t) { i++; continue; }

    const para = [];
    while (i < lines.length) {
      const lt = lines[i].trim();
      if (!lt || lt.startsWith('#') || lt.startsWith('```')
               || /^[-*•]\s/.test(lt) || /^\d+[.)]\s/.test(lt)
               || /^(-{3,}|_{3,}|\*{3,})$/.test(lt)) break;
      para.push(lt);
      i++;
    }
    if (para.length) out += `<p>${inl(para.join(' '))}</p>`;
  }

  return out || `<p>${inl(raw)}</p>`;
}

function inl(raw) {
  return esc(raw)
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/__(.+?)__/g,     '<strong>$1</strong>')
    .replace(/\*(.+?)\*/g,     '<em>$1</em>')
    .replace(/_([^_\s][^_]*)_/g, '<em>$1</em>')
    .replace(/~~(.+?)~~/g,     '<del>$1</del>')
    .replace(/`([^`]+)`/g,     '<code>$1</code>')
    .replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank">$1</a>');
}

function copyCode(btn) {
  const code = btn.closest('.code-block').querySelector('pre code');
  navigator.clipboard.writeText(code.textContent).then(() => {
    btn.textContent = 'Copied!'; btn.classList.add('ok');
    setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('ok'); }, 2000);
  });
}

function toggleReasoning(hdr) {
  const wrap  = hdr.closest('.reasoning-wrap');
  const body  = wrap.querySelector('.reasoning-body');
  const caret = hdr.querySelector('.r-caret');
  const prev  = hdr.querySelector('.r-preview');
  const open  = body.classList.toggle('open');
  caret.classList.toggle('open', open);
  if (prev) prev.style.display = open ? 'none' : '';
}

function toggleTool(hdr) {
  const wrap  = hdr.closest('.tool-wrap');
  const body  = wrap.querySelector('.tool-body');
  const caret = hdr.querySelector('.t-caret');
  const open  = body.classList.toggle('open');
  caret.classList.toggle('open', open);
}

function toolMeta(name) {
  const n = (name||'').toLowerCase();
  if (n.includes('read'))   return {icon:'📄', label:'Reading file'};
  if (n.includes('write'))  return {icon:'✏️',  label:'Writing file'};
  if (n.includes('create')) return {icon:'📝', label:'Creating file'};
  if (n.includes('delete')) return {icon:'🗑️',  label:'Deleting'};
  if (n.includes('list')||n.includes('dir')) return {icon:'📁', label:'Listing directory'};
  if (n.includes('search')||n.includes('grep')) return {icon:'🔍', label:'Searching'};
  if (n.includes('bash')||n.includes('run')||n.includes('exec')||n.includes('command')) return {icon:'⚡', label:'Running command'};
  if (n.includes('browser')) return {icon:'🌐', label:'Browser'};
  if (n.includes('git'))    return {icon:'🔀', label:'Git'};
  if (n.includes('patch')||n.includes('edit')) return {icon:'✏️', label:'Editing'};
  return {icon:'⚙️', label: name||'Tool'};
}

function statusClass(s) {
  const v = (s||'').toLowerCase();
  if (v==='completed'||v==='done') return 'done';
  if (v==='error') return 'error';
  return 'running';
}

function statusLabel(s) {
  const v = (s||'').toLowerCase();
  if (v==='completed'||v==='done') return '✓ Done';
  if (v==='error') return '✕ Error';
  return '⋯ Running';
}

// ─── GAS API (called from WPF via ExecuteScriptAsync) ───────────────────────
window.gasAPI = {

  clearConversation() {
    msgs.innerHTML = `<div id="empty">
      <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#263040" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">
        <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>
      </svg>
      <h2>Start a conversation</h2>
      <p>Use the hotkey or command bar<br>to ask GAS anything.</p>
    </div>`;
    S.turns = {};
    S.activeTurnEl = null;
    S.lastUserPrompt = '';
    S.userScrolled = false;
    jmp.classList.remove('show');
  },

  // ── User message ─────────────────────────────────────────────────────────
  addUserMessage(jsonStr) {
    const {text, timestamp} = JSON.parse(jsonStr);
    hideEmpty();
    S.activeTurnEl = null; // Reset active turn so next agent response gets a fresh turn
    S.lastUserPrompt = (text||'').trim();

    if (timestamp) {
      const ts = document.createElement('div');
      ts.className = 'ts';
      ts.textContent = timestamp;
      msgs.appendChild(ts);
    }
    const row = document.createElement('div');
    row.className = 'user-row';
    row.innerHTML = `<div class="user-bubble">${esc(text)}</div>`;
    msgs.appendChild(row);
    scrollToBottom(true);
  },

  // ── Agent part streaming ─────────────────────────────────────────────────
  onPartDelta(jsonStr) {
    const {partID, delta, type} = JSON.parse(jsonStr);
    hideEmpty();

    if (!S.turns[partID]) {
      const turnBody = getOrCreateActiveTurn();

      if (type === 'text') {
        const textEl = document.createElement('div');
        textEl.className = 'agent-text streaming';
        turnBody.appendChild(textEl);
        S.turns[partID] = {type:'text', content:textEl, raw:''};

      } else if (type === 'reasoning') {
        const wrap = document.createElement('div');
        wrap.className = 'reasoning-wrap';
        wrap.innerHTML = `
          <div class="reasoning-header" onclick="toggleReasoning(this)">
            <span class="r-caret open">▶</span>
            <span class="r-lbl">🧠 Reasoning</span>
            <span class="r-preview" style="display:none"></span>
          </div>
          <div class="reasoning-body open streaming"></div>`;
        turnBody.appendChild(wrap);
        S.turns[partID] = {type:'reasoning', el:wrap, content:wrap.querySelector('.reasoning-body'), preview:wrap.querySelector('.r-preview'), raw:''};
      }
    }

    const t = S.turns[partID];
    if (!t || !t.content) return;
    t.raw += delta;

    // Filter prompt echoes in initial text part
    if (t.type === 'text' && S.lastUserPrompt && (t.raw.trim() === S.lastUserPrompt || S.lastUserPrompt.startsWith(t.raw.trim()))) {
      // Prompt echo detected — don't display prompt echo text
      t.content.style.display = 'none';
      return;
    }

    if (t.content.style.display === 'none') {
      t.content.style.display = '';
    }

    t.content.textContent = t.raw;
    scrollToBottom();
  },

  // ── Finalize / replay part ───────────────────────────────────────────────
  onPartUpdated(jsonStr) {
    const {partID, type, text} = JSON.parse(jsonStr);
    hideEmpty();

    // Ignore prompt echo text parts entirely
    if (type === 'text' && S.lastUserPrompt && text && (text.trim() === S.lastUserPrompt || S.lastUserPrompt.startsWith(text.trim()))) {
      if (S.turns[partID] && S.turns[partID].content) {
        S.turns[partID].content.remove();
        delete S.turns[partID];
      }
      return;
    }

    if (!S.turns[partID]) {
      const turnBody = getOrCreateActiveTurn();

      if (type === 'text') {
        if (!text || !text.trim()) return;
        const textEl = document.createElement('div');
        textEl.className = 'agent-text';
        textEl.innerHTML = md(text);
        turnBody.appendChild(textEl);
        S.turns[partID] = {type:'text', content:textEl, raw:text};
      } else if (type === 'reasoning') {
        if (!text || !text.trim()) return;
        const first = text.split('\n').find(l=>l.trim())||'';
        const prev  = first.length > 80 ? first.slice(0,80)+'…' : first;
        const wrap  = document.createElement('div');
        wrap.className = 'reasoning-wrap';
        wrap.innerHTML = `
          <div class="reasoning-header" onclick="toggleReasoning(this)">
            <span class="r-caret">▶</span>
            <span class="r-lbl">🧠 Reasoning</span>
            <span class="r-preview">· ${esc(prev)}</span>
          </div>
          <div class="reasoning-body">${esc(text)}</div>`;
        turnBody.appendChild(wrap);
        S.turns[partID] = {type:'reasoning', el:wrap, raw:text};
      }
      scrollToBottom();
      return;
    }

    const t = S.turns[partID];
    t.raw = text;

    if (type === 'text' && t.content) {
      if (!text || !text.trim()) {
        t.content.remove();
        delete S.turns[partID];
      } else {
        t.content.style.display = '';
        t.content.classList.remove('streaming');
        t.content.innerHTML = md(text);
      }

    } else if (type === 'reasoning' && t.content) {
      const body  = t.content;
      const caret = t.el.querySelector('.r-caret');
      const prev  = t.preview;
      body.classList.remove('streaming', 'open');
      caret.classList.remove('open');
      body.textContent = text;
      if (prev) {
        const first = text.split('\n').find(l=>l.trim())||'';
        prev.textContent = '· ' + (first.length > 80 ? first.slice(0,80)+'…' : first);
        prev.style.display = '';
      }
    }

    scrollToBottom();
  },

  // ── Tool activity ─────────────────────────────────────────────────────────
  addTool(jsonStr) {
    const {id, name, status, input, output} = JSON.parse(jsonStr);
    hideEmpty();

    if (S.turns[id]) { this.updateTool(jsonStr); return; }

    const turnBody = getOrCreateActiveTurn();
    const meta     = toolMeta(name);
    const formatted = formatToolOutput(output || input);
    const sc       = statusClass(status);
    const sl       = statusLabel(status);

    const wrap = document.createElement('div');
    wrap.className = 'tool-wrap';
    wrap.dataset.toolId = id;
    wrap.innerHTML = `
      <div class="tool-header" onclick="toggleTool(this)">
        <span class="t-caret">▶</span>
        <span>${meta.icon}</span>
        <span class="t-name">${esc(meta.label)}</span>
        <span class="t-chip ${sc}">${sl}</span>
      </div>
      <div class="tool-body">${esc(formatted)}</div>`;
    turnBody.appendChild(wrap);
    S.turns[id] = {type:'tool', el:wrap};
    scrollToBottom();
  },

  updateTool(jsonStr) {
    const {id, status, output, input} = JSON.parse(jsonStr);
    const t = S.turns[id];
    if (!t) return;

    const chip = t.el.querySelector('.t-chip');
    const body = t.el.querySelector('.tool-body');
    const sc   = statusClass(status);
    const sl   = statusLabel(status);

    if (chip) { chip.className = `t-chip ${sc}`; chip.textContent = sl; }
    if (body) {
      const formatted = formatToolOutput(output || input || body.textContent);
      body.textContent = formatted;
    }
  }
};
</script>
</body>
</html>
""";
    }
}
