import Foundation

enum MarkdownPreviewStyles {
    static let css = """
    :root {
      color-scheme: light dark;

      --bg: #ffffff;
      --text: #1f2328;
      --muted: #656d76;
      --link: #0969da;
      --border: #d0d7de;
      --heading-border: #d8dee4;
      --code-bg: #f6f8fa;
      --inline-code-bg: rgba(175, 184, 193, 0.24);
      --quote-border: #d0d7de;
      --table-stripe: #f6f8fa;
      --mark-bg: #fff8c5;
      --selection: rgba(9, 105, 218, 0.22);
      --error-bg: #fff8f7;
      --error-border: #ffcecb;
      --error-text: #cf222e;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #1e1e1e;
        --text: #d4d4d4;
        --muted: #9aa4af;
        --link: #58a6ff;
        --border: #3c4043;
        --heading-border: #3c4043;
        --code-bg: #2a2d2e;
        --inline-code-bg: rgba(110, 118, 129, 0.35);
        --quote-border: #4b5157;
        --table-stripe: #252526;
        --mark-bg: #4b3f13;
        --selection: rgba(88, 166, 255, 0.32);
        --error-bg: #2b1a1a;
        --error-border: #613b39;
        --error-text: #ff7b72;
      }
    }

    * {
      box-sizing: border-box;
    }

    html {
      min-height: 100%;
      background: var(--bg);
      color-scheme: light dark;
    }

    body {
      margin: 0;
      min-height: 100%;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text",
        "Helvetica Neue", "PingFang SC", "Hiragino Sans GB", sans-serif;
      font-size: 16px;
      line-height: 1.72;
      -webkit-font-smoothing: antialiased;
      text-rendering: optimizeLegibility;
    }

    ::selection {
      background: var(--selection);
    }

    .markdown-body {
      max-width: 900px;
      margin: 0 auto;
      padding: 44px 52px 88px;
      overflow-wrap: break-word;
    }

    .markdown-body > :first-child {
      margin-top: 0 !important;
    }

    .markdown-body > :last-child {
      margin-bottom: 0 !important;
    }

    h1, h2, h3, h4, h5, h6 {
      margin: 1.55em 0 0.65em;
      color: var(--text);
      font-weight: 650;
      line-height: 1.3;
      letter-spacing: -0.015em;
    }

    h1 {
      padding-bottom: 0.3em;
      border-bottom: 1px solid var(--heading-border);
      font-size: 2em;
    }

    h2 {
      padding-bottom: 0.28em;
      border-bottom: 1px solid var(--heading-border);
      font-size: 1.55em;
    }

    h3 { font-size: 1.3em; }
    h4 { font-size: 1.1em; }
    h5 { font-size: 1em; }
    h6 { color: var(--muted); font-size: 0.92em; }

    p, ul, ol, dl, table, pre, blockquote, details {
      margin: 0 0 1.05em;
    }

    ul, ol {
      padding-left: 2em;
    }

    li + li {
      margin-top: 0.26em;
    }

    li > p {
      margin-top: 0.5em;
    }

    a {
      color: var(--link);
      text-decoration: none;
    }

    a:hover {
      text-decoration: underline;
      text-underline-offset: 2px;
    }

    strong {
      font-weight: 650;
    }

    mark {
      padding: 0.1em 0.22em;
      border-radius: 4px;
      background: var(--mark-bg);
      color: inherit;
    }

    blockquote {
      margin-left: 0;
      padding: 0.15em 1.1em;
      border-left: 4px solid var(--quote-border);
      color: var(--muted);
    }

    blockquote > :last-child {
      margin-bottom: 0;
    }

    hr {
      height: 1px;
      margin: 2em 0;
      border: 0;
      background: var(--border);
    }

    code, kbd, samp, pre {
      font-family: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Monaco,
        "Cascadia Mono", "Roboto Mono", monospace;
    }

    code {
      padding: 0.16em 0.38em;
      border-radius: 5px;
      background: var(--inline-code-bg);
      font-size: 0.88em;
    }

    pre {
      overflow: auto;
      padding: 18px 20px;
      border: 1px solid var(--border);
      border-radius: 9px;
      background: var(--code-bg);
      line-height: 1.58;
      tab-size: 4;
    }

    pre code {
      display: inline;
      padding: 0;
      border-radius: 0;
      background: transparent;
      font-size: 0.89em;
      white-space: pre;
    }

    pre.code-block {
      padding: 0;
    }

    pre.code-block > code {
      display: flex;
      align-items: stretch;
      width: max-content;
      min-width: 100%;
      padding: 16px 0;
      background: transparent;
      font-size: 0.89em;
      line-height: 1.65;
    }

    .code-line-numbers {
      flex: none;
      min-width: 2.8em;
      padding: 0 14px 0 16px;
      border-right: 1px solid var(--border);
      color: var(--muted);
      opacity: 0.82;
      text-align: right;
      white-space: pre;
      font-variant-numeric: tabular-nums;
      user-select: none;
      -webkit-user-select: none;
    }

    .code-block-lines {
      flex: 1 0 auto;
      padding: 0 20px;
      white-space: pre;
    }

    kbd {
      padding: 0.15em 0.42em;
      border: 1px solid var(--border);
      border-bottom-width: 2px;
      border-radius: 5px;
      background: var(--code-bg);
      font-size: 0.85em;
    }

    table {
      display: block;
      width: max-content;
      max-width: 100%;
      overflow: auto;
      border-spacing: 0;
      border-collapse: collapse;
      font-size: 0.95em;
    }

    th, td {
      padding: 7px 14px;
      border: 1px solid var(--border);
    }

    th {
      background: var(--code-bg);
      font-weight: 650;
      text-align: left;
    }

    tr:nth-child(even) td {
      background: var(--table-stripe);
    }

    img {
      display: block;
      max-width: 100%;
      height: auto;
      margin: 1.4em auto;
      border-radius: 8px;
    }

    video, audio, iframe {
      max-width: 100%;
    }

    details {
      padding: 0.8em 1em;
      border: 1px solid var(--border);
      border-radius: 8px;
    }

    summary {
      cursor: pointer;
      font-weight: 600;
    }

    .contains-task-list {
      padding-left: 1.4em;
      list-style: none;
    }

    .task-list-item {
      list-style: none;
    }

    .task-list-item-checkbox {
      margin: 0 0.5em 0.18em -1.35em;
      vertical-align: middle;
    }

    .textcove-error {
      max-width: 760px;
      margin: 72px auto;
      padding: 28px 30px;
      border: 1px solid var(--error-border);
      border-radius: 12px;
      background: var(--error-bg);
      color: var(--text);
    }

    .textcove-error-icon {
      display: flex;
      align-items: center;
      justify-content: center;
      width: 34px;
      height: 34px;
      margin-bottom: 14px;
      border-radius: 50%;
      background: var(--error-text);
      color: var(--bg);
      font-weight: 700;
    }

    .textcove-error h1 {
      margin: 0 0 8px;
      padding: 0;
      border: 0;
      color: var(--error-text);
      font-size: 1.35em;
    }

    .textcove-error p {
      margin: 0;
      color: var(--text);
      white-space: pre-wrap;
    }

    @media (max-width: 760px) {
      .markdown-body {
        padding: 28px 24px 64px;
      }
    }
    """
}
