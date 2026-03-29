# Medusa — Multi-Language Algorithmic Trading System

**kdb+tick architecture** with **TorQ framework** for production HFT infrastructure.

A multi-language algorithmic trading system inspired by Gryphon, built with:
- **q/kdb+**: Core trading engine, in-memory analytics, and schema
- **Rust**: High-performance exchange connectors and IPC bridge
- **Python**: Backtesting, research, and data analysis

## Project Structure

```
medusa/
├── src/
│   ├── q/          # q/kdb+ trading engine (TorQ + kdb+tick)
│   ├── rust/       # Rust exchange connectors (barter-rs)
│   └── python/     # Python backtesting/research (PyKX)
├── configs/        # Strategy and exchange configurations
├── data/           # Market data (gitignored)
├── scripts/        # Setup and build scripts
└── ai/             # AI-assisted development artifacts
```

## Quick Start

### Prerequisites
- kdb+ 4.x (or use Docker)
- Rust 1.75+ (`rustup`)
- Python 3.11+
- Docker & Docker Compose (for development environment)

### Build Everything

```bash
# One-command build
make all

# Or build individually
make rust     # Build Rust workspace
make python   # Install Python package
make q        # Validate q source
```

### Run Development Environment

```bash
# Launch all services (kdb+, Rust daemon, Jupyter)
make docker-up

# Access Jupyter notebooks
open http://localhost:8888

# Connect to kdb+ REPL
rlwrap q src/q/init.q
```

### Run Tests

```bash
make test         # All tests
make test-rust    # Rust only
make test-python  # Python only
make test-q       # q only
```

## Architecture

### Data Flow (kdb+tick)

```
Rust exchange-daemon (barter-rs)
    │
    ├──> Market Data (orderbooks, trades)
    │    │
    │    ▼
    │    Tickerplant (TP, port 5010)     ← .u.upd from Rust
    │        │
    │        ├──→ RDB (port 5011)        ← in-memory, current day
    │        ├──→ HDB (port 5012)        ← on-disk, historical
    │        ├──→ Strategy process        ← .u.sub for real-time
    │        └──→ Risk engine            ← .u.sub for monitoring
    │
    └──> Execution Reports
         └──> Tickerplant
```

## License

MIT License - See LICENSE file
