from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class ClaimVerdict(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    INCONCLUSIVE = "INCONCLUSIVE"


class TestVerdict(str, Enum):
    PASS = "PASS"
    FAIL = "FAIL"
    INCONCLUSIVE = "INCONCLUSIVE"


@dataclass(frozen=True, slots=True)
class NegativeTestResult:
    claim_verdict: ClaimVerdict
    test_verdict: TestVerdict
    reason: str


def evaluate_negative_test(*, claim_is_proven: bool | None, expected_claim_truth: bool = False) -> NegativeTestResult:
    """Separate claim truth from whether a negative test behaved correctly."""
    if claim_is_proven is None:
        return NegativeTestResult(ClaimVerdict.INCONCLUSIVE, TestVerdict.INCONCLUSIVE, "CLAIM_EVIDENCE_MISSING")
    claim_truth = bool(claim_is_proven)
    claim_verdict = ClaimVerdict.PASS if claim_truth else ClaimVerdict.FAIL
    test_passed = claim_truth is expected_claim_truth
    return NegativeTestResult(
        claim_verdict,
        TestVerdict.PASS if test_passed else TestVerdict.FAIL,
        "CLAIM_VERDICT_IS_DISTINCT_FROM_TEST_VERDICT",
    )


def memory_priority(source: str) -> int:
    order = {"tool": 1, "machine_file": 2, "live_state": 3, "memory": 4, "conversation": 5, "model": 6, "hypothesis": 7}
    return order.get(source.strip().lower(), 99)
