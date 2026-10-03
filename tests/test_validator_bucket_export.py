"""Offline UTC and idempotent cursor tests for the bucket exporter."""

import datetime as dt
import importlib.util
import json
import pathlib
import tempfile
import unittest
from unittest import mock

PATH = pathlib.Path(__file__).resolve().parents[1] / "scripts/validator-bucket-export.py"
SPEC = importlib.util.spec_from_file_location("validator_bucket_export", PATH)
EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORT)


class BucketExportTest(unittest.TestCase):
    def test_calendar_month_and_bounded_chunks(self):
        start = dt.datetime(2028, 2, 1, tzinfo=dt.timezone.utc)
        self.assertEqual(EXPORT.next_bucket("month", start), dt.datetime(2028, 3, 1, tzinfo=dt.timezone.utc))
        self.assertEqual(EXPORT.chunk_end("month", start, dt.datetime(2028, 4, 1, tzinfo=dt.timezone.utc)),
                         dt.datetime(2028, 4, 1, tzinfo=dt.timezone.utc))

    def test_line_has_only_fixed_fields_and_bucket_timestamp(self):
        item = {
            "start": "2028-02-01T00:00:00Z",
            "total": 2,
            "by_mode": {"check": 1, "bounce": 1, "reply": 0, "other": 0},
            "by_status": {"ohne_festgestellte_probleme": 1, "auffaellig": 1, "unvollstaendig": 0, "other": 0},
            "complete": True,
            "known": False,
        }
        line = EXPORT.line("month", item)
        self.assertIn("total=2i", line)
        self.assertIn("known=0i", line)
        self.assertTrue(line.endswith("1832976000000000000\n"))
        with self.assertRaises(ValueError):
            EXPORT.line("month", dict(item, by_mode=dict(item["by_mode"], bounce=2)))

    def test_current_bucket_retried_after_success(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            token = root / "token"
            token.write_text("synthetic", encoding="ascii")
            current = {period: EXPORT.stamp(EXPORT.floor(period, dt.datetime.now(dt.timezone.utc)))
                       for period in EXPORT.PERIODS}
            cfg = {"state_file": str(root / "state.json"), "influx_token_file": str(token), "initial": current}
            with mock.patch.object(EXPORT, "source_series", return_value=[] ) as source, \
                 mock.patch.object(EXPORT, "write_influx") as write:
                self.assertEqual(EXPORT.run(cfg), current)
                self.assertEqual(EXPORT.run(cfg), current)
                self.assertEqual(source.call_count, 6)
                self.assertEqual(write.call_count, 6)
            self.assertEqual(json.loads((root / "state.json").read_text(encoding="utf-8")), current)


if __name__ == "__main__":
    unittest.main()
