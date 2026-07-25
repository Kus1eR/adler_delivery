import re
from datetime import datetime, timezone


def utc_now() -> datetime:
    """Return naive UTC for SQLite DateTime and existing API compatibility."""
    return datetime.now(timezone.utc).replace(tzinfo=None)


def normalize_phone(phone: str) -> str:
    """Normalize to +7XXXXXXXXXX format. Accepts +7, 8, 7 prefixes with any separators."""
    digits = re.sub(r"\D", "", phone.strip())
    if digits.startswith("8") and len(digits) == 11:
        digits = "+7" + digits[1:]
    elif digits.startswith("7") and len(digits) == 11:
        digits = "+" + digits
    elif len(digits) == 10:
        digits = "+7" + digits
    return digits
