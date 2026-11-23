# Medusa Trading Terminal - Workspace Features

## Overview

The Medusa Electron app now includes a professional Bloomberg-style customizable workspace with drag-and-dock panels, pop-out windows, and symbol linking across widgets.

## Key Features

### 1. Drag-and-Dock Layout

- **Powered by react-mosaic-component** — Industrial-strength tiling window manager
- **Drag-and-drop** panel resizing and rearrangement
- **Split panels** horizontally or vertically
- **Persistent layouts** saved to localStorage
- **Preset layouts** for common workflows (Trading, Portfolio, Research, Options)

### 2. Pop-Out Windows

- **Multi-monitor support** — Pop any widget into a separate Electron window
- **Cross-window symbol linking** — Linked widgets update across all windows via Electron IPC
- **Independent workflows** — Run multiple workspaces simultaneously

### 3. Symbol Linking (Color Groups)

Widgets can be linked together by color group:
- **Red** 🔴
- **Blue** 🔵
- **Green** 🟢
- **Yellow** 🟡
- **Unlinked** ⚪

When a user clicks a symbol in a linked widget (e.g., Watchlist), ALL widgets in the same color group update to that symbol:
- Chart shows the new symbol's price action
- Order Book shows the new symbol's depth
- Trade Ticket updates the symbol field
- Time & Sales shows the new symbol's trades

### 4. Available Widgets

| Widget | Description | Supports Linking |
|--------|-------------|------------------|
| **Price Chart** | Advanced candlestick chart with indicators | ✅ |
| **Order Blotter** | Real-time order tracking | ❌ |
| **Positions** | Portfolio positions monitor | ✅ |
| **Trade Ticket** | Order entry form | ✅ |
| **Order Book** | Level 2 market depth | ✅ |
| **Time & Sales** | Trade tape | ✅ |
| **P&L** | Profit & loss analytics | ❌ |
| **Risk** | Risk metrics dashboard | ❌ |
| **Watchlist** | Symbol monitor | ✅ |
| **Strategies** | Strategy performance | ❌ |
| **Exchanges** | Exchange status | ❌ |
| **Equity Curve** | Portfolio equity over time | ❌ |
| **Greeks** | Options Greeks dashboard | ❌ |
| **Yield Curve** | Bond yield curves | ❌ |
| **Options Chain** | Options chain grid | ✅ |
| **Payoff Diagram** | Options payoff visualization | ❌ |
| **Vol Surface** | Volatility surface 3D | ❌ |
| **Bond Ladder** | Bond maturity ladder | ❌ |
| **Duration** | Duration & DV01 metrics | ❌ |
| **Volume Analysis** | VWAP, CVD, volume spikes | ❌ |
| **Strategy Builder** | Visual strategy builder | ❌ |

## Usage

### Accessing Workspace Mode

Navigate to the **Trading** tab to enter workspace mode. The fixed page layout is replaced with the customizable workspace.

### Workspace Toolbar

Located at the top of the workspace:

- **Add Widget** (+) — Dropdown to add a new widget to the layout
- **Load** — Load a preset or saved layout
- **Save** — Save the current layout with a custom name
- **Export** (⬇) — Export layout as JSON file
- **Import** (⬆) — Import layout from JSON file

### Widget Controls

Each widget has a thin title bar (h-7) with controls on the right:

1. **Link Color Selector** (colored dot) — Hover to select a link group
2. **Pop-Out** (⊡) — Opens widget in a new window
3. **Close** (×) — Removes widget from layout

### Preset Layouts

#### Trading
- Chart (60%) + Order Book + Trade Ticket + Order Blotter
- **Use case:** Active trading workflow

#### Portfolio
- Positions + P&L + Risk + Strategy Monitor
- **Use case:** Portfolio monitoring and risk management

#### Research
- Chart + Watchlist + Equity Curve + Volume Analysis
- **Use case:** Market research and analysis

#### Options
- Options Chain + Greeks + Payoff Diagram + Vol Surface
- **Use case:** Options trading and analysis

## Implementation Details

### File Structure

```
src/electron/
├── renderer/
│   ├── components/layout/
│   │   ├── WorkspaceManager.tsx       # Main mosaic container
│   │   ├── WorkspaceToolbar.tsx       # Add/Save/Load controls
│   │   ├── WidgetToolbar.tsx          # Per-widget controls
│   │   ├── LinkColorSelector.tsx      # Color group selector
│   │   ├── PopOutContainer.tsx        # Pop-out window renderer
│   │   └── workspace.css              # Mosaic theme overrides
│   ├── stores/
│   │   ├── workspace.ts               # Workspace layout state
│   │   └── symbolLink.ts              # Symbol linking state
│   ├── lib/
│   │   ├── workspace-types.ts         # TypeScript types
│   │   ├── widget-registry.tsx        # Widget component registry
│   │   └── preset-layouts.ts          # Default layouts
│   └── global.d.ts                    # Window API types
├── main/
│   ├── index.ts                       # Pop-out window handler + IPC
│   └── preload.ts                     # popOutWidget + symbolLink APIs
```

### Cross-Window IPC

Symbol link changes are broadcast to ALL windows via Electron IPC:

**Renderer → Main:**
```typescript
window.symbolLink.broadcast(color, symbol, exchange)
```

**Main Process:**
```typescript
ipcMain.on('symbolLink:changed', (_event, color, symbol, exchange) => {
  BrowserWindow.getAllWindows().forEach((win) => {
    win.webContents.send('symbolLink:update', color, symbol, exchange)
  })
})
```

**Main → Renderer:**
```typescript
window.symbolLink.onChange((color, symbol, exchange) => {
  useSymbolLinkStore.setState(...)
})
```

### Persistence

Layouts are saved to localStorage under the key `medusa-workspace-layouts`. Export/import as JSON for version control or sharing.

## Future Enhancements

- [ ] Widget templates (save widget configs separately from layouts)
- [ ] Layout hotkeys (Ctrl+1 → Trading, Ctrl+2 → Portfolio, etc.)
- [ ] Widget search/filter in Add Widget dropdown
- [ ] Multi-workspace tabs (separate workspaces per trading account)
- [ ] Collaborative layouts (share layouts with team)
- [ ] Widget state persistence (chart timeframe, selected expiry, etc.)
- [ ] Drag-to-link (drag a link color from one widget to another)
- [ ] Layout diff/merge (compare two layouts)
- [ ] Touch/tablet support (responsive drag handles)

## Design Principles

- **tastytrade dark theme** — Consistent with existing app palette
- **Thin title bars** (h-7 = 28px) — Maximize chart/data space
- **Subtle borders** — Clean, professional appearance
- **Link colors** — Standard (red/blue/green/yellow) for clarity
- **Pop-out windows inherit theme** — No jarring UI changes
- **Save/load in top-right** — Standard location for workspace controls

## Troubleshooting

### Layout Won't Save
- Check browser localStorage quota (default 5-10MB)
- Export layout to JSON as backup

### Pop-Out Window Doesn't Open
- Check Electron BrowserWindow permissions
- Verify `window.popOutWidget` is available (should be exposed in preload)

### Symbol Link Not Working
- Ensure widget has `supportsLinking: true` in registry
- Check `linkColor` is not `'none'`
- Verify Electron IPC is active (check console for IPC errors)

## Technical Notes

- **react-mosaic-component v6.1.0** — Mature, battle-tested library
- **Zustand** — State management for workspace + symbol linking
- **Electron IPC** — Cross-window communication
- **localStorage** — Client-side persistence (consider IndexedDB for large layouts)
- **TypeScript strict mode** — Full type safety (ignoring mosaic internal type quirks)

## Credits

- **Mosaic layout** inspired by Bloomberg Terminal
- **Symbol linking** inspired by TradingView multi-chart layouts
- **Pop-out windows** inspired by tastytrade desktop app
