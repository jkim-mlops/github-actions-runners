import importlib

import pytest

# env_prefix is GITHUB_, so Settings reads these.
GITHUB_ENV = {
    "GITHUB_APP_PRIVATE_KEY_PARAM": "/x/key",
    "GITHUB_APP_CLIENT_ID_PARAM": "/x/client-id",
    "GITHUB_APP_INSTALLATION_ID": "123",
    "GITHUB_REPO_OWNER": "o",
    "GITHUB_REPO_NAME": "myrepo",
}


@pytest.fixture
def setup_runner(monkeypatch):
    for key, value in GITHUB_ENV.items():
        monkeypatch.setenv(key, value)
    import setup_runner as mod

    importlib.reload(mod)
    return mod


def test_runner_name_is_stable(setup_runner):
    settings = setup_runner.Settings()
    # The bug being fixed: a @computed_field property minted a fresh UUID per access.
    assert settings.runner_name == settings.runner_name
    assert settings.runner_name.startswith("myrepo-runner-")


def test_build_config_args_includes_labels(setup_runner):
    args = setup_runner.build_config_args(url="u", token="t", name="n", labels="self-hosted,docker,abc")
    assert "--labels" in args
    assert args[args.index("--labels") + 1] == "self-hosted,docker,abc"


def test_build_config_args_omits_labels_when_empty(setup_runner):
    args = setup_runner.build_config_args(url="u", token="t", name="n", labels="")
    assert "--labels" not in args


def test_build_config_args_is_ephemeral_and_unattended(setup_runner):
    args = setup_runner.build_config_args(url="u", token="t", name="n")
    assert "--ephemeral" in args
    assert "--unattended" in args
