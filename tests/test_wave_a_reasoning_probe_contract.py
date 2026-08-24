from pathlib import Path


def test_wave_a_reasoning_probe_is_not_exact_string_only() -> None:
    script = (Path(__file__).resolve().parents[1] / "scripts" / "certify_wave_a_shadow.py").read_text(encoding="utf-8")
    assert "/no_think" in script
    assert "WAVE_A_MODEL_MARKER_OBSERVED" in script
    assert "WAVE_A_RESPONSE_CHARS" in script
    assert "response.provider != \"lm_studio_local\"" in script
    assert "or not raw_choices" in script
    assert "or not observable" in script
    assert '"WAVE_A_MODEL_PASS" not in run.run.response.text' not in script


def test_wave_a_reasoning_probe_accepts_reasoning_fields_as_observable_output() -> None:
    script = (Path(__file__).resolve().parents[1] / "scripts" / "certify_wave_a_shadow.py").read_text(encoding="utf-8")
    assert '"reasoning_content"' in script
    assert '"reasoning"' in script
    assert '"analysis"' in script
