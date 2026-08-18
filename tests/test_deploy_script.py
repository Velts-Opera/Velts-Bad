from pathlib import Path

SCRIPT_PATH = Path("scripts/deploy-livekit.ps1")


def script_text() -> str:
    return SCRIPT_PATH.read_text(encoding="utf-8")


def test_production_deploy_requires_exact_main_ci_success():
    text = script_text()

    assert "Assert-GitHubCiGreen" in text
    assert "actions/runs?branch=main&event=push" in text
    assert "$_.head_sha -eq $HeadSha" in text
    assert "$_.name -eq 'CI'" in text
    assert "$_.event -eq 'push'" in text
    assert "$_.status -eq 'completed'" in text
    assert "$_.conclusion -eq 'success'" in text
    assert "Assert-GitHubCiGreen $headSha" in text


def test_deploy_ci_gate_fails_closed_on_api_or_missing_success():
    text = script_text()

    assert "não foi possível verificar o CI" in text
    assert "não possui um run CI de push concluído com sucesso" in text


def test_deploy_never_creates_a_new_livekit_agent():
    text = script_text()

    assert "lk agent create" not in text
    assert "lk agent config --id $AgentId" in text
    assert "lk agent deploy" in text


def test_deploy_only_cleans_stale_secrets_after_successful_deploy():
    text = script_text()

    deploy_index = text.index("& lk agent deploy .")
    overwrite_index = text.index("--overwrite")
    assert deploy_index < overwrite_index
