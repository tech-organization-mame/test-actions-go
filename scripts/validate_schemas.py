"""スキーマと例の検証。

`valid`の例は通り、`invalid`の例は通らないことを確認する。
使い方：python scripts/validate_schemas.py
必要：pip install jsonschema
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = ROOT / "schemas"
EXAMPLES = SCHEMAS / "examples"


def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> int:
    failures = []
    count = 0
    for name in ("result", "context"):
        schema = load(SCHEMAS / f"{name}.schema.json")
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema)
        for kind in ("valid", "invalid"):
            paths = sorted(EXAMPLES.glob(f"{name}.{kind}-*.json"))
            if not paths:  # ファイル名の変更などで、例が0件になっても成功させない
                print("NG", f"{name}.{kind}-*.json", "(例が0件)")
                failures.append(f"{name}.{kind}: no examples")
            for path in paths:
                count += 1
                errors = list(validator.iter_errors(load(path)))
                ok = (not errors) if kind == "valid" else bool(errors)
                print(("OK" if ok else "NG"), path.name, f"({kind})")
                if not ok:
                    failures.append(path.name)
    print(f"checked={count} failed={len(failures)}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
