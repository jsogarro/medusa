"""Placeholder test to verify pytest setup."""


def test_placeholder() -> None:
    """Verify test infrastructure works."""
    assert 1 + 1 == 2


def test_imports() -> None:
    """Verify package can be imported."""
    import medusa

    assert medusa.__version__ == "0.1.0"
