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
        // ── Public entry point ──────────────────────────────────────────────

        /// <summary>Returns the complete HTML document as a string.</summary>
        public static string GetHtml() => HtmlContent;

        // ── Helper: serialize a C# payload to a JS-safe string literal ──────
        // Usage: CallJs("gasAPI.addUserMessage", payload)
        // Produces: window.gasAPI.addUserMessage("{\"text\":\"hello\"}")
        // The double-serialization makes the JSON a valid JS string literal.
        public static string BuildCall(string method, object payload)
        {
            var json = JsonSerializer.Serialize(payload);
            var jsLiteral = JsonSerializer.Serialize(json); // JSON-encode the JSON string → safe JS literal
            return $"window.{method}({jsLiteral})";
        }

        // ── The HTML ────────────────────────────────────────────────────────
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
.user-row{display:flex;justify-content:flex-end;margin:6px 0}
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
  white-space:pre-wrap;
  word-break:break-word;
}

/* ─── Agent turn ─────────────────────────────────────────────────── */
.agent-row{margin:12px 0 6px}
.agent-badge{
  display:flex;align-items:center;gap:7px;
  margin-bottom:7px;user-select:none;
}
.agent-dot{
  width:19px;height:19px;border-radius:50%;flex-shrink:0;
  background:linear-gradient(140deg,#4338CA,#7C3AED);
  display:flex;align-items:center;justify-content:center;
  font-size:9px;font-weight:700;color:#fff;letter-spacing:0;
}
.agent-label{font-size:11px;font-weight:600;color:#2D3748}

/* Agent text content */
.agent-content{
  font-size:13.5px;line-height:1.75;
  color:#B8C5D4;
  cursor:text;user-select:text;
  word-break:break-word;
}

/* Streaming cursor */
.agent-content.streaming{white-space:pre-wrap}
.agent-content.streaming::after{
  content:'▋';
  animation:blink .75s step-end infinite;
  color:#6366F1;margin-left:1px;
}
@keyframes blink{0%,100%{opacity:1}50%{opacity:0}}

/* ─── Markdown ───────────────────────────────────────────────────── */
.agent-content p{margin-bottom:10px}
.agent-content p:last-child{margin-bottom:0}
.agent-content h1{font-size:20px;font-weight:700;color:#E2ECF5;margin:20px 0 10px}
.agent-content h2{font-size:16.5px;font-weight:600;color:#D0DCE8;margin:16px 0 8px}
.agent-content h3{font-size:14px;font-weight:600;color:#B8C5D4;margin:12px 0 6px}
.agent-content strong{font-weight:600;color:#D0DCE8}
.agent-content em{font-style:italic;color:#8898AA}
.agent-content del{text-decoration:line-through;color:#4A5568}
.agent-content a{color:#818CF8;text-decoration:none}
.agent-content a:hover{text-decoration:underline}
.agent-content hr{border:none;border-top:1px solid #0F1626;margin:18px 0}
.agent-content ul,.agent-content ol{padding-left:22px;margin-bottom:10px}
.agent-content li{margin-bottom:4px}
.agent-content li p{margin-bottom:0}

/* Inline code */
.agent-content code{
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
  margin:14px 0;overflow:hidden;
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
.reasoning-wrap{margin:8px 0}
.reasoning-header{
  display:flex;align-items:center;gap:5px;
  padding:3px 0;cursor:pointer;user-select:none;
  color:#2A3548;font-size:11px;
  transition:color .12s;
}
.reasoning-header:hover{color:#3A4A60}
.r-caret{font-size:8px;transition:transform .15s;display:inline-block}
.r-caret.open{transform:rotate(90deg)}
.r-lbl{font-weight:500}
.r-preview{
  color:#1C2530;font-style:italic;font-size:11px;margin-left:4px;
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
  font-size:12.5px;color:#3A4E62;
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
.tool-wrap{margin:5px 0}
.tool-header{
  display:flex;align-items:center;gap:6px;
  padding:3px 0;cursor:pointer;user-select:none;
  font-size:11px;color:#2A3548;
  transition:color .12s;
}
.tool-header:hover{color:#3A4A60}
.t-caret{font-size:8px;transition:transform .15s;display:inline-block}
.t-caret.open{transform:rotate(90deg)}
.t-name{font-weight:500}
.t-chip{
  margin-left:auto;font-size:10px;padding:1px 7px;
  border-radius:3px;font-weight:500;
}
.t-chip.running{color:#92712A;background:#110D00}
.t-chip.done{color:#2A7A52;background:#001A0E}
.t-chip.error{color:#7A3030;background:#1A0000}
.tool-body{
  display:none;
  margin:3px 0 3px 10px;
  padding:7px 12px;
  background:#07080C;
  border-left:2px solid #0F1A26;
  border-radius:0 4px 4px 0;
  font-family:'Cascadia Code','Cascadia Mono',Consolas,monospace;
  font-size:11px;color:#2A3A50;
  white-space:pre-wrap;word-break:break-word;
  max-height:160px;overflow-y:auto;
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
const S = { turns:{}, userScrolled:false };
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

// ─── Markdown parser ────────────────────────────────────────────────────────
function md(raw) {
  if (!raw || !raw.trim()) return '';
  const lines = raw.split('\n');
  let out = '', i = 0;

  while (i < lines.length) {
    const line = lines[i];
    const t = line.trim();

    // Fenced code block
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

    // Headings
    if (t.startsWith('### ')) { out += `<h3>${inl(t.slice(4))}</h3>`; i++; continue; }
    if (t.startsWith('## '))  { out += `<h2>${inl(t.slice(3))}</h2>`; i++; continue; }
    if (t.startsWith('# '))   { out += `<h1>${inl(t.slice(2))}</h1>`; i++; continue; }

    // HR
    if (/^(-{3,}|_{3,}|\*{3,})$/.test(t)) { out += '<hr>'; i++; continue; }

    // Unordered list
    if (/^[-*•]\s/.test(t)) {
      const items = [];
      while (i < lines.length && /^[-*•]\s/.test(lines[i].trim())) {
        items.push(`<li>${inl(lines[i].trim().slice(2))}</li>`);
        i++;
      }
      out += `<ul>${items.join('')}</ul>`;
      continue;
    }

    // Ordered list
    if (/^\d+[.)]\s/.test(t)) {
      const items = [];
      while (i < lines.length && /^\d+[.)]\s/.test(lines[i].trim())) {
        items.push(`<li>${inl(lines[i].trim().replace(/^\d+[.)]\s/,''))}</li>`);
        i++;
      }
      out += `<ol>${items.join('')}</ol>`;
      continue;
    }

    // Blank line
    if (!t) { i++; continue; }

    // Paragraph — collect consecutive non-special lines
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

// Inline markdown (operates on already-escaped HTML isn't right — we escape first)
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

// ─── Copy code button ────────────────────────────────────────────────────────
function copyCode(btn) {
  const code = btn.closest('.code-block').querySelector('pre code');
  navigator.clipboard.writeText(code.textContent).then(() => {
    btn.textContent = 'Copied!'; btn.classList.add('ok');
    setTimeout(() => { btn.textContent = 'Copy'; btn.classList.remove('ok'); }, 2000);
  });
}

// ─── Reasoning helpers ───────────────────────────────────────────────────────
function toggleReasoning(hdr) {
  const wrap  = hdr.closest('.reasoning-wrap');
  const body  = wrap.querySelector('.reasoning-body');
  const caret = hdr.querySelector('.r-caret');
  const prev  = hdr.querySelector('.r-preview');
  const open  = body.classList.toggle('open');
  caret.classList.toggle('open', open);
  if (prev) prev.style.display = open ? 'none' : '';
}

// ─── Tool helpers ─────────────────────────────────────────────────────────────
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
    S.userScrolled = false;
    jmp.classList.remove('show');
  },

  // ── User message ─────────────────────────────────────────────────────────
  addUserMessage(jsonStr) {
    const {text, timestamp} = JSON.parse(jsonStr);
    hideEmpty();
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

  // ── Agent text ────────────────────────────────────────────────────────────
  onPartDelta(jsonStr) {
    const {partID, delta, type} = JSON.parse(jsonStr);
    hideEmpty();

    if (!S.turns[partID]) {
      if (type === 'text') {
        const row = document.createElement('div');
        row.className = 'agent-row';
        row.innerHTML = `
          <div class="agent-badge">
            <div class="agent-dot">G</div>
            <span class="agent-label">GAS</span>
          </div>
          <div class="agent-content streaming"></div>`;
        msgs.appendChild(row);
        S.turns[partID] = {type:'text', el:row, content:row.querySelector('.agent-content'), raw:''};

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
        msgs.appendChild(wrap);
        S.turns[partID] = {type:'reasoning', el:wrap, content:wrap.querySelector('.reasoning-body'), preview:wrap.querySelector('.r-preview'), raw:''};
      }
    }

    const t = S.turns[partID];
    if (!t || !t.content) return;
    t.raw += delta;
    t.content.textContent = t.raw;
    scrollToBottom();
  },

  // ── Finalize / replay ─────────────────────────────────────────────────────
  onPartUpdated(jsonStr) {
    const {partID, type, text} = JSON.parse(jsonStr);
    hideEmpty();

    if (!S.turns[partID]) {
      // Replay (loading history) — create and immediately render
      if (type === 'text') {
        const row = document.createElement('div');
        row.className = 'agent-row';
        row.innerHTML = `
          <div class="agent-badge">
            <div class="agent-dot">G</div>
            <span class="agent-label">GAS</span>
          </div>
          <div class="agent-content">${md(text)}</div>`;
        msgs.appendChild(row);
        S.turns[partID] = {type:'text', el:row, raw:text};
      } else if (type === 'reasoning') {
        const first = (text||'').split('\n').find(l=>l.trim())||'';
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
        msgs.appendChild(wrap);
        S.turns[partID] = {type:'reasoning', el:wrap, raw:text};
      }
      scrollToBottom();
      return;
    }

    const t = S.turns[partID];
    t.raw = text;

    if (type === 'text' && t.content) {
      t.content.classList.remove('streaming');
      t.content.innerHTML = md(text);

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

    const meta   = toolMeta(name);
    const detail = (output||input||'Executing…').slice(0,500);
    const sc     = statusClass(status);
    const sl     = statusLabel(status);

    const wrap = document.createElement('div');
    wrap.className = 'tool-wrap';
    wrap.dataset.toolId = id;
    wrap.innerHTML = `
      <div class="tool-header" onclick="toggleTool(this)">
        <span>${meta.icon}</span>
        <span class="t-name">${esc(meta.label)}</span>
        <span class="t-chip ${sc}">${sl}</span>
        <span class="t-caret">▶</span>
      </div>
      <div class="tool-body">${esc(detail)}</div>`;
    msgs.appendChild(wrap);
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
      const d = (output||input||body.textContent||'').slice(0,500);
      if (d) body.textContent = d;
    }
  }
};
</script>
</body>
</html>
""";
    }
}
