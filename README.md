# Codex Usage

An Omarchy bar widget for Codex subscription usage.

The bar shows the current 5-hour usage percentage. Clicking it opens a compact
panel with the 5-hour limit, weekly remaining allowance, reset times, and
purchased Codex credits.

## Install

```bash
omarchy plugin add https://github.com/peterszarvas94/omarchy-codex-usage --enable --yes
```

The widget uses Codex's local app-server RPC and the standard Omarchy agents
usage collector. It does not use API keys or send usage data to a third party.
