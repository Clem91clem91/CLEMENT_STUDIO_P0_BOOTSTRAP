from clement_memory.semantics import ClaimVerdict, TestVerdict, evaluate_negative_test, memory_priority


def test_false_claim_rejected_means_negative_test_passes() -> None:
    result = evaluate_negative_test(claim_is_proven=False, expected_claim_truth=False)
    assert result.claim_verdict is ClaimVerdict.FAIL
    assert result.test_verdict is TestVerdict.PASS


def test_fake_model_evidence_rejection_is_a_pass_condition() -> None:
    result = evaluate_negative_test(claim_is_proven=False)
    assert result.test_verdict.value == "PASS"


def test_missing_evidence_is_inconclusive_not_pass() -> None:
    result = evaluate_negative_test(claim_is_proven=None)
    assert result.claim_verdict.value == "INCONCLUSIVE"
    assert result.test_verdict.value == "INCONCLUSIVE"


def test_tool_evidence_outranks_memory_and_model() -> None:
    assert memory_priority("tool") < memory_priority("memory") < memory_priority("model")
