"""Create the research graph for the configuration-driven runner."""

import os
from pathlib import Path
import shutil
import sys

from azure.identity import DefaultAzureCredential
from langchain_azure_ai.chat_models import AzureAIOpenAIApiChatModel
from langchain_azure_ai.agents.hosting import FoundryCheckpointSaver
from deepagents.backends import LocalShellBackend

from agent import build_agent


def create_backend():
    """Use the hosted session's persistent HOME or an ignored local workspace."""
    source = Path(__file__).resolve().parent
    workspace = (
        Path(os.environ["HOME"]) / "deep-agents"
        if os.environ.get("FOUNDRY_HOSTING_ENVIRONMENT")
        else source.parent / ".workspace"
    )
    workspace.mkdir(parents=True, exist_ok=True)
    for directory in ("skills", "data"):
        for bundled in (source / directory).rglob("*"):
            if bundled.is_file():
                destination = workspace / bundled.relative_to(source)
                destination.parent.mkdir(parents=True, exist_ok=True)
                try:
                    with destination.open("xb") as target, bundled.open("rb") as content:
                        shutil.copyfileobj(content, target)
                except FileExistsError:
                    pass
    # Supply only shell essentials; never inherit credentials or telemetry config.
    env = {key: os.environ[key] for key in ("PATH", "SYSTEMROOT", "WINDIR") if key in os.environ}
    env["PATH"] = str(Path(sys.executable).parent) + os.pathsep + env.get("PATH", os.defpath)
    return LocalShellBackend(root_dir=workspace, env=env, inherit_env=False)


def create_graph():
    model = AzureAIOpenAIApiChatModel(
        project_endpoint=os.environ["FOUNDRY_PROJECT_ENDPOINT"],
        credential=DefaultAzureCredential(),
        model=os.environ["AZURE_AI_MODEL_DEPLOYMENT_NAME"],
        use_responses_api=True,
        store=False,
    )
    return build_agent(model, create_backend(), FoundryCheckpointSaver(user_isolation=True))
