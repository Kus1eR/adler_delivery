from pydantic import ValidationError

from app.config import Settings


def main() -> None:
    try:
        Settings(_env_file=None)
    except ValidationError as exc:
        assert "SECRET_KEY" in str(exc)
    else:
        raise AssertionError("SECRET_KEY must not have a production-unsafe default")


if __name__ == "__main__":
    main()
    print("required secret configuration check: OK")
