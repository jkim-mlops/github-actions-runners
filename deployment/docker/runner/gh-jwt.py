import os
import subprocess

import boto3
import requests
from github import Auth, GithubIntegration
from pydantic import Field, computed_field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="GITHUB_")

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

# Get runner registration token using the API directly
headers = {
    "Authorization": f"Bearer {installation_auth_token.token}",
    "Accept": "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
}
response = requests.post(
    f"https://api.github.com/repos/{settings.repo_owner}/{settings.repo_name}/actions/runners/registration-token",
    headers=headers,
)
response.raise_for_status()
runner_token = response.json()["token"]

# Fetch and setup runner if not already present
if not os.path.isfile("/runner/actions-runner/config.sh"):
    print("Fetching GitHub Actions runner...")
    os.chdir("/runner")
    result = subprocess.run(["/runner/fetch-runner.sh"], check=True)

# Configure runner
os.chdir("/runner/actions-runner")
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
