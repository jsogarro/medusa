.PHONY: all rust python q test test-rust test-python test-q test-q-docker docker-up docker-down docker-logs clean lint

RUST_DIR := src/rust
PYTHON_DIR := src/python
Q_DIR := src/q
KDB_QHOME ?= $(HOME)/q

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
	@if [ -f tests/q/run_all_tests.q ]; then \
		if command -v q >/dev/null 2>&1; then \
			log_file=$$(mktemp); \
			q tests/q/run_all_tests.q >$$log_file 2>&1; \
			status=$$?; \
			cat $$log_file; \
			if [ $$status -ne 0 ]; then \
				if grep -q "couldn't connect to license daemon" $$log_file; then \
					echo "  host q hit license-daemon error — retrying in Docker..."; \
					rm -f $$log_file; \
					$(MAKE) test-q-docker; \
					exit $$?; \
				fi; \
				rm -f $$log_file; \
				exit $$status; \
			fi; \
			rm -f $$log_file; \
		else \
			echo "  host q not found — running in Docker..."; \
			$(MAKE) test-q-docker; \
			exit $$?; \
		fi; \
	else \
		echo "  (no q tests yet — skipping)"; \
	fi
	@echo "✓ q tests complete"

test-q-docker:
	@echo "Running q tests in Docker..."
	@test -f "$(KDB_QHOME)/kc-linux.lic" || (echo "Missing Linux q license: $(KDB_QHOME)/kc-linux.lic"; exit 1)
	@docker run --rm --platform linux/amd64 \
		-v "$(KDB_QHOME)":/opt/kdb:ro \
		-v "$(KDB_QHOME)/kc-linux.lic":/opt/kdb/kc.lic:ro \
		-v "$$(pwd)":/work \
		-w /work \
		-e QHOME=/opt/kdb \
		-e QLIC=/opt/kdb \
			kdb-l64 tests/q/run_all_tests.q
	@echo "✓ Docker q tests passed"

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
