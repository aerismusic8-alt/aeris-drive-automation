from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github" / "workflows" / "akath-24x7-acceptance-v2.yml"
WORKER = ROOT / "AKATH" / "runtime" / "akath_worker.ps1"


def test_acceptance_does_not_replace_runner_python_with_embedded_python():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "$pythonDir | Out-File -FilePath $env:GITHUB_PATH" not in text
    assert "AKATH_PORTABLE_PYTHON=$pythonExe" in text


def test_acceptance_uses_system_python_for_pytest_and_portable_python_for_runtime():
    text = WORKFLOW.read_text(encoding="utf-8")
    assert "python -m pytest tests/master_brain/ax_akath_identity_migration_tests.py -q" in text
    assert "& $env:AKATH_PORTABLE_PYTHON \"$env:GITHUB_WORKSPACE/AKATH/tests/rehydration_adapter_tests.py\"" in text
    assert "AKATH_PORTABLE_PYTHON" in WORKER.read_text(encoding="utf-8")
