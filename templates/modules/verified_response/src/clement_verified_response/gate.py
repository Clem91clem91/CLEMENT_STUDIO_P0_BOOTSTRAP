from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Any


class Verdict(str, Enum):
    PASS = "PASS"
    PARTIAL = "PARTIAL"
    FAIL = "FAIL"
    INCONCLUSIVE = "INCONCLUSIVE"


@dataclass(frozen=True, slots=True)
class VerifiedClaim:
    name: str
    value: Any
    verdict: Verdict
    source_type: str | None
    source_id: str | None
    source_path: str | None
    verified: bool
    reason: str


@dataclass(frozen=True, slots=True)
class ResponseGateResult:
    verdict: Verdict
    claims: tuple[VerifiedClaim, ...]
    model_may_explain: bool = True
    model_may_override_verdict: bool = False


def compute_response_verdict(claims: list[VerifiedClaim]) -> ResponseGateResult:
    if not claims:
        return ResponseGateResult(Verdict.INCONCLUSIVE, ())
    verdicts = {claim.verdict for claim in claims}
    if Verdict.FAIL in verdicts:
        verdict = Verdict.FAIL
    elif Verdict.INCONCLUSIVE in verdicts:
        verdict = Verdict.INCONCLUSIVE
    elif Verdict.PARTIAL in verdicts:
        verdict = Verdict.PARTIAL
    elif all(claim.verified and claim.verdict is Verdict.PASS for claim in claims):
        verdict = Verdict.PASS
    else:
        verdict = Verdict.INCONCLUSIVE
    return ResponseGateResult(verdict, tuple(claims))


def negative_claim_test(*, claim_name: str, false_claim_was_rejected: bool | None, source_id: str | None = None) -> VerifiedClaim:
    if false_claim_was_rejected is None:
        return VerifiedClaim(claim_name, None, Verdict.INCONCLUSIVE, None, source_id, None, False, "NEGATIVE_TEST_EVIDENCE_MISSING")
    return VerifiedClaim(
        claim_name,
        False,
        Verdict.PASS if false_claim_was_rejected else Verdict.FAIL,
        "NEGATIVE_TEST",
        source_id,
        None,
        bool(false_claim_was_rejected),
        "FALSE_CLAIM_REJECTED" if false_claim_was_rejected else "FALSE_CLAIM_ACCEPTED",
    )
