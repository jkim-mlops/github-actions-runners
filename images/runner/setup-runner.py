import os
import subprocess

import boto3
import requests
from github import Auth, GithubIntegration
from pydantic import Field, computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


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
    installation_id: str = Field(default=..., description="GitHub App installation ID")
    repo_owner: str = Field(
        default=..., description="Repository owner (organization or user)"
    )
    repo_name: str = Field(default=..., description="Repository name")
    runner_base_dir: str = Field(
        default="/runner", description="Base directory for runner files"
    )
    test_mode: bool = Field(
        default=False, description="Run in test mode (skip runner setup)"
    )

    @property
    def runner_url(self) -> str:
        return f"https://github.com/{self.repo_owner}/{self.repo_name}"

    @computed_field
    @property
    def runner_name(self) -> str:
        """Generate runner name: repo-name-runner"""
        return f"{self.repo_name}-runner"


settings = Settings()

# Create SSM client
ssm = boto3.client("ssm")

# Get private key from SSM
private_key_response = ssm.get_parameter(
    Name=settings.app_private_key_param, WithDecryption=True
)
private_key_content = private_key_response["Parameter"]["Value"]

# Get client ID from SSM
client_id_response = ssm.get_parameter(
    Name=settings.app_client_id_param, WithDecryption=True
)
client_id = client_id_response["Parameter"]["Value"]

# Authenticate as GitHub App
auth = Auth.AppAuth(client_id, private_key_content)
gi = GithubIntegration(auth=auth)

# Get installation and access token
installation_id_int = int(settings.installation_id)
installation_auth_token = gi.get_access_token(installation_id_int)

print(f"Got installation token for installation {installation_id_int}")

# Get runner registration token using the API directly
# TODO: Refactor this call to use the pygithub client if it becomes available in the future.
headers = {
    "Authorization": f"Bearer {installation_auth_token.token}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}
url = f"https://api.github.com/repos/{settings.repo_owner}/{settings.repo_name}/actions/runners/registration-token"
print(f"Requesting runner token from: {url}")
response = requests.post(url, headers=headers)

if response.status_code != 201:
    print(f"Error response: {response.status_code}")
    print(f"Response body: {response.text}")

response.raise_for_status()
runner_token = response.json()["token"]
print("Successfully obtained runner registration token")

if settings.test_mode:
    print("Test mode enabled - skipping runner setup")
    print("Runner would be configured with:")
    print(f"  URL: {settings.runner_url}")
    print(f"  Name: {settings.runner_name}")
    exit(0)

# Fetch and setup runner if not already present
runner_config_path = os.path.join(
    settings.runner_base_dir, "actions-runner", "config.sh"
)
if not os.path.isfile(runner_config_path):
    print("Fetching GitHub Actions runner...")
    os.chdir(settings.runner_base_dir)
    result = subprocess.run([f"{settings.runner_base_dir}/fetch-runner.sh"], check=True)

# Configure runner
runner_dir = os.path.join(settings.runner_base_dir, "actions-runner")
os.chdir(runner_dir)
print("Configuring runner...")
subprocess.run(
    [
        "./config.sh",
        "--url",
        settings.runner_url,
        "--token",
        runner_token,
        "--name",
        settings.runner_name,
        "--unattended",
        "--ephemeral",
    ],
    check=True,
)

# Run the runner
print("Starting runner...")
os.execv("./run.sh", ["./run.sh"])
