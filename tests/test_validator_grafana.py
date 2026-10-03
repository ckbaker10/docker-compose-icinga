"""Check that versioned views use exact buckets and stable dashboard UIDs."""

import importlib.util
import pathlib
import unittest

PATH = pathlib.Path(__file__).resolve().parents[1] / "scripts/provision-validator-grafana.py"
SPEC = importlib.util.spec_from_file_location("provision_validator_grafana", PATH)
GRAFANA = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GRAFANA)


class DashboardContractTest(unittest.TestCase):
    def test_each_resolution_uses_its_own_bucket_without_averaging(self):
        for period, (bucket, _, _) in GRAFANA.PERIODS.items():
            with self.subTest(period=period):
                view = GRAFANA.dashboard(period)
                self.assertEqual(view["uid"], "iev-stats-" + period)
                self.assertEqual(len(view["panels"]), 3)
                self.assertEqual(view["timezone"], "utc")
                queries = [panel["targets"][0]["query"] for panel in view["panels"]]
                self.assertTrue(all(f'from(bucket: "{bucket}")' in query for query in queries))
                self.assertFalse(any("aggregateWindow" in query or "mean(" in query for query in queries))
                self.assertIn('r._field == "total"', queries[0])
                self.assertIn('r._field == "mode_bounce"', queries[1])
                self.assertIn('r._field == "status_auffaellig"', queries[2])


if __name__ == "__main__":
    unittest.main()
