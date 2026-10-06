"""Small offline policy checks; no game, sampler, backend, SSH or legacy replay."""
import unittest
from acceptance import collection_plan


class NightPolicyTests(unittest.TestCase):
    def profile(self):
        return {"profile_id": "night_low_power", "functional_evidence_collection_allowed": True,
                "repeated_verification_allowed": False, "performance_qualification_allowed": False,
                "baseline_comparison_allowed": False, "functional_capture_seconds_max": 180,
                "functional_capture_interval_min_s": .5}

    def test_short_functional_capture_allowed_without_repeated_verification(self):
        p = collection_plan(self.profile(), 120, .5)
        self.assertEqual(p["seconds"], 120)
        self.assertTrue(p["functional_only"])

    def test_long_request_is_bounded_to_one_short_flow(self):
        self.assertEqual(collection_plan(self.profile(), 900, .25)["seconds"], 180)

    def test_fast_poll_request_preserves_low_power_interval(self):
        self.assertEqual(collection_plan(self.profile(), 20, .05)["interval_s"], .5)

    def test_functional_permission_does_not_enable_performance_or_comparison(self):
        p = collection_plan(self.profile(), 60, .5)
        self.assertFalse(p["performance_qualification_allowed"])
        self.assertFalse(p["baseline_comparison_allowed"])

    def test_explicit_functional_stop_remains_effective(self):
        p = self.profile(); p["functional_evidence_collection_allowed"] = False
        with self.assertRaises(ValueError): collection_plan(p, 30, .5)

    def test_normal_profile_keeps_existing_capture_duration(self):
        p = collection_plan({"profile_id": "normal", "performance_qualification_allowed": True}, 900, .25)
        self.assertEqual(p["seconds"], 900); self.assertFalse(p["functional_only"])


if __name__ == "__main__": unittest.main()
