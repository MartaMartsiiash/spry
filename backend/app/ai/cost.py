"""Bedrock list prices (USD per million tokens). Regional inference profiles +10%."""

# Bare model id (without eu./global. prefix) -> (input $/MTok, output $/MTok)
MODEL_PRICES_USD: dict[str, tuple[float, float]] = {
    "anthropic.claude-opus-5-5": (4.00, 20.00),
    "anthropic.claude-sonnet-5-5": (2.00, 10.00),
    "anthropic.claude-haiku-5-5": (0.10, 0.50),
    # Available on this Free project when Opus/Haiku 5.5 are blocked.
    "anthropic.claude-sonnet-4-6": (3.00, 15.00),
}


def _bare_model_id(model: str) -> str:
    for prefix in ("eu.", "us.", "global."):
        if model.startswith(prefix):
            return model[len(prefix) :]
    return model


def cost_usd(model: str, usage: dict[str, int], *, regional: bool = True) -> float:
    """Return the dollar cost of one call from input/output token counts."""
    prices = MODEL_PRICES_USD.get(model) or MODEL_PRICES_USD.get(_bare_model_id(model))
    if prices is None:
        return 0.0
    input_rate, output_rate = prices
    if regional:
        input_rate *= 1.1
        output_rate *= 1.1
    dollars = (
        usage.get("input_tokens", 0) / 1_000_000 * input_rate
        + usage.get("output_tokens", 0) / 1_000_000 * output_rate
    )
    return round(dollars, 6)
