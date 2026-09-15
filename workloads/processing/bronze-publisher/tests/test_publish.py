import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).parents[1] / "publish.py"
SPEC = importlib.util.spec_from_file_location("publish", MODULE_PATH)
publish = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(publish)


class PublisherContractTests(unittest.TestCase):
    def test_known_tlc_schema_is_accepted(self):
        self.assertEqual(publish.schema_mismatches(publish.EXPECTED_SCHEMA), [])

    def test_missing_and_changed_columns_are_reported(self):
        actual = dict(publish.EXPECTED_SCHEMA)
        del actual["VendorID"]
        actual["fare_amount"] = "string"

        self.assertEqual(
            publish.schema_mismatches(actual),
            ["missing column: VendorID", "fare_amount: expected double, got string"],
        )

    def test_month_is_canonical(self):
        self.assertEqual(publish.format_month("1"), "01")
        with self.assertRaises(ValueError):
            publish.format_month(13)


if __name__ == "__main__":
    unittest.main()
