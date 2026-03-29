.PHONY: all rust python q test test-rust test-python test-q docker-up docker-down docker-logs clean lint

RUST_DIR := src/rust
PYTHON_DIR := src/python
Q_DIR := src/q

# ─── Build ────────────────────────────────────────────────────────────────────

all: rust python q
	@echo "✓ All components built successfully"

rust:
	@echo "Building Rust workspace..."
	cd $(RUST_DIR) && cargo build --workspace
	@echo "✓ Rust build complete"

python:
	@echo "Setting up Python package..."
	cd $(PYTHON_DIR) && pip install -e ".[dev]" --quiet
	@echo "✓ Python package installed"

q:
	@echo "Validating q source..."
	@test -f $(Q_DIR)/init.q || (echo "✗ init.q not found" && exit 1)
	@test -f $(Q_DIR)/schema/tables.q || (echo "✗ schema/tables.q not found" && exit 1)
	@echo "✓ q source validated"

# ─── Test ─────────────────────────────────────────────────────────────────────

test: test-rust test-python test-q
	@echo "✓ All tests passed"

test-rust:
	@echo "Running Rust tests..."
	cd $(RUST_DIR) && cargo test --workspace
	@echo "✓ Rust tests passed"

test-python:
	@echo "Running Python tests..."
	cd $(PYTHON_DIR) && pytest tests/
	@echo "✓ Python tests passed"

test-q:
	@echo "Running q tests..."
	@if [ -f tests/q/run_all.q ]; then \
		q tests/q/run_all.q -q; \
	else \
		echo "  (no q tests yet — skipping)"; \
	fi
	@echo "✓ q tests complete"

# ─── Lint ─────────────────────────────────────────────────────────────────────

lint: lint-rust lint-python
	@echo "✓ All linting passed"

lint-rust:
	@echo "Linting Rust..."
	cd $(RUST_DIR) && cargo clippy --workspace -- -D warnings
	cd $(RUST_DIR) && cargo fmt --check
	@echo "✓ Rust lint passed"

lint-python:
	@echo "Linting Python..."
	cd $(PYTHON_DIR) && ruff check .
	@echo "✓ Python lint passed"

# ─── Docker ───────────────────────────────────────────────────────────────────

docker-up:
	docker compose up -d
	@echo "✓ Docker services started"

docker-down:
	docker compose down
	@echo "✓ Docker services stopped"

docker-logs:
	docker compose logs -f

# ─── Clean ────────────────────────────────────────────────────────────────────

clean:
	@echo "Cleaning build artifacts..."
	cd $(RUST_DIR) && cargo clean
	rm -rf $(PYTHON_DIR)/.venv
	rm -rf $(PYTHON_DIR)/*.egg-info
	rm -rf $(PYTHON_DIR)/.pytest_cache
	rm -rf $(PYTHON_DIR)/.mypy_cache
	rm -rf $(PYTHON_DIR)/.ruff_cache
	rm -rf $(PYTHON_DIR)/htmlcov
	@echo "✓ Clean complete"
