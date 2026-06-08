import logging
import os
import subprocess
import uuid

import boto3
import requests
from github import Auth, GithubIntegration
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger("runner-setup")


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="GITHUB_", env_file=".env")

    app_private_key_param: str = Field(
        default=...,
        description="SSM parameter name containing the GitHub App private key",
    )
    app_client_id_param: str = Field(
        default=...,
        description="SSM parameter name containing the GitHub App client ID",
    )
    app_installation_id: str = Field(default=..., description="GitHub App installation ID")
    repo_owner: str = Field(default=..., description="Repository owner (organization or user)")
    repo_name: str = Field(default=..., description="Repository name")
    runner_base_dir: str = Field(default="/runner", description="Base directory for runner files")
    test_mode: bool = Field(default=False, description="Run in test mode (skip runner setup)")
    runner_name: str = Field(default="", description="Runner name; generated once if not provided")

    @property
    def runner_url(self) -> str:
        return f"https://github.com/{self.repo_owner}/{self.repo_name}"

    def model_post_init(self, __context) -> None:
        # Generate a stable, unique runner name exactly once. (A previous
        # @computed_field property minted a fresh UUID on every access.)
        if not self.runner_name:
            self.runner_name = f"{self.repo_name}-runner-{uuid.uuid4().hex[:8]}"


def build_config_args(url: str, token: str, name: str, labels: str = "") -> list[str]:
    """Build the argument list for the runner's config.sh.

    A unique label per runner (passed via the RUNNER_LABELS env var) keeps
    GitHub dispatching jobs to idle ephemeral runners (community #120813).
    """
    args = ["--url", url, "--token", token, "--name", name, "--unattended", "--ephemeral"]
    if labels:
        args += ["--labels", labels]
    return args


def get_runner_token(settings: Settings) -> str:
    """Authenticate as the GitHub App and fetch a runner registration token."""
    ssm = boto3.client("ssm")
    private_key = ssm.get_parameter(Name=settings.app_private_key_param, WithDecryption=True)["Parameter"]["Value"]
    client_id = ssm.get_parameter(Name=settings.app_client_id_param, WithDecryption=True)["Parameter"]["Value"]

    auth = Auth.AppAuth(client_id, private_key)
    gi = GithubIntegration(auth=auth)
    installation_token = gi.get_access_token(int(settings.app_installation_id)).token
    logger.info(f"Got installation token for installation {settings.app_installation_id}")

    # TODO: Refactor to use the pygithub client if runner registration becomes available.
    headers = {
        "Authorization": f"Bearer {installation_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    url = f"https://api.github.com/repos/{settings.repo_owner}/{settings.repo_name}/actions/runners/registration-token"
    logger.info(f"Requesting runner token from: {url}")
    response = requests.post(url, headers=headers)
    if response.status_code != 201:
        logger.error(f"Error response: {response.status_code} | Response body: {response.text}")
    response.raise_for_status()
    logger.info("Successfully obtained runner registration token")
    return response.json()["token"]


def main() -> None:
    settings = Settings()
    runner_token = get_runner_token(settings)

    if settings.test_mode:
        logger.info(
            f"Test mode enabled - skipping runner setup | URL: {settings.runner_url} | Name: {settings.runner_name}"
        )
        return

    # Fetch and setup runner if not already present
    runner_config_path = os.path.join(settings.runner_base_dir, "actions-runner", "config.sh")
    if not os.path.isfile(runner_config_path):
        logger.info("Fetching GitHub Actions runner...")
        os.chdir(settings.runner_base_dir)
        subprocess.run([f"{settings.runner_base_dir}/fetch-runner.sh"], check=True)

    # Configure runner
    runner_dir = os.path.join(settings.runner_base_dir, "actions-runner")
    os.chdir(runner_dir)
    logger.info("Configuring runner...")
    subprocess.run(
        ["./config.sh"]
        + build_config_args(
            settings.runner_url,
            runner_token,
            settings.runner_name,
            os.environ.get("RUNNER_LABELS", ""),
        ),
        check=True,
    )

    # Run the runner
    logger.info("Starting runner...")
    os.execv("./run.sh", ["./run.sh"])


if __name__ == "__main__":
    main()
