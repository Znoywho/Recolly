"""Which model provider a feature uses, chosen with an environment variable."""

import os


def provider_from_env(variable: str, allowed: tuple[str, ...]) -> str:
    """The provider named by `variable` (the first of `allowed` when unset); a typo stops the server at start-up."""
    value = os.getenv(variable, "").strip().lower() or allowed[0]
    if value not in allowed:
        raise ValueError(f"{variable}={value!r} is not supported, use one of: {', '.join(allowed)}")
    return value
