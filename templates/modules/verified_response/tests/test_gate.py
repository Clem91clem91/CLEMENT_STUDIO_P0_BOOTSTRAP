from clement_verified_response.gate import Verdict, VerifiedClaim, compute_response_verdict, negative_claim_test


def test_rejecting_an_unproven_claim_makes_negative_test_pass() -> None:
    claim = negative_claim_test(claim_name="unproven_agent_count", false_claim_was_rejected=True, source_id="TASK_REPORT")
    assert claim.verdict is Verdict.PASS
    assert compute_response_verdict([claim]).verdict is Verdict.PASS


def test_accepting_an_unproven_value_fails_gate() -> None:
    claim = negative_claim_test(claim_name="unproven_value", false_claim_was_rejected=False, source_id="MODEL")
    result = compute_response_verdict([claim])
    assert result.verdict is Verdict.FAIL
    assert result.model_may_override_verdict is False


def test_no_claim_evidence_is_inconclusive() -> None:
    assert compute_response_verdict([]).verdict is Verdict.INCONCLUSIVE


def test_unverified_claim_never_becomes_pass() -> None:
    claim = VerifiedClaim("x", 1, Verdict.PASS, "TOOL", "E1", "$.x", False, "NOT_VERIFIED")
    assert compute_response_verdict([claim]).verdict is Verdict.INCONCLUSIVE
