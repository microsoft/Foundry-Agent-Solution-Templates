import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).parents[1]
REPORT_SCRIPT = ROOT / "scripts" / "validation-report.ps1"


def write_report(tmp_path: Path, statuses: tuple[str, str]) -> dict[str, str]:
    script_path = str(REPORT_SCRIPT).replace("'", "''")
    output_path = str(tmp_path).replace("'", "''")
    command = (
        f". '{script_path}'; "
        "$results = @("
        "[pscustomobject]@{ id = 'network'; name = 'Private network'; "
        "objective = 'Prevent public fallback.'; "
        "method = 'Inspect live network controls.'; "
        "checklist = @('Public access is disabled.','Private DNS uses RFC1918.'); "
        f"status = '{statuses[0]}'; evidence = 'Private controls matched.'; "
        "durationSeconds = 1.25; failure = 'Network mismatch.' },"
        "[pscustomobject]@{ id = 'cmk'; name = 'Customer-managed keys'; "
        "objective = 'Validate live encryption bindings.'; "
        "method = 'Compare Key Vault key versions.'; "
        "checklist = @('Foundry CMK matches.','Search CMK matches.'); "
        f"status = '{statuses[1]}'; evidence = 'CMK controls matched.'; "
        "durationSeconds = 0.5; failure = '' }"
        "); "
        "$written = Write-SecurityValidationReport "
        f"-Results $results -OutputDirectory '{output_path}' "
        "-EnvironmentName 'env-test' -DeploymentMode 'Source' "
        "-ResourceGroupName 'rg-env-test' "
        "-AgentServiceName 'private-search-agent' -AgentVersion '7' "
        "-SourceRevision '0123456789abcdef' -SourceTreeState 'clean' "
        "-IncludePrivateDataPlane $true "
        "-GeneratedAtUtc ([DateTime]'2026-07-30T08:00:00Z'); "
        "$written | ConvertTo-Json -Compress"
    )
    result = subprocess.run(
        ["pwsh", "-NoProfile", "-Command", command],
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


def test_report_writer_emits_readable_markdown(tmp_path: Path) -> None:
    written = write_report(tmp_path, ("Passed", "Passed"))

    markdown = Path(written["LatestMarkdownPath"]).read_text(encoding="utf-8")

    assert written["OverallStatus"] == "passed"
    assert "> **PASSED** - Every control" in markdown
    assert "| Checklist assertions | 4 |" in markdown
    assert "| Agent version | 7 |" in markdown
    assert "| Source tree state | clean |" in markdown
    assert "| Validation scope | Management plane and private data plane |" in markdown
    assert "| Private network | PASSED |" in markdown
    assert "| Customer-managed keys | PASSED |" in markdown
    assert "## Detailed security acceptance checklist" in markdown
    assert "**Security objective:** Prevent public fallback." in markdown
    assert "**Validation method:** Inspect live network controls." in markdown
    assert "- [x] Public access is disabled." in markdown
    assert "### Adopter-owned follow-up" in markdown
    assert "not a signed independent security assessment" in markdown
    assert "not continuous monitoring" in markdown
    assert len(list(tmp_path.glob("security-validation-*.md"))) == 1
    assert list(tmp_path.glob("*.json")) == []


def test_report_writer_does_not_present_incomplete_run_as_passed(
    tmp_path: Path,
) -> None:
    written = write_report(tmp_path, ("Failed", "NotRun"))

    markdown = Path(written["LatestMarkdownPath"]).read_text(encoding="utf-8")

    assert written["OverallStatus"] == "failed"
    assert "Network mismatch." in markdown
    assert "| Customer-managed keys | NOTRUN |" in markdown
    assert "- [ ] Public access is disabled." in markdown
    assert "This control family failed" in markdown
    assert "must not be treated as validated" in markdown
