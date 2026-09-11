"""Platform-aware shell backend for Deep Agents."""

from __future__ import annotations

import base64
import os

from deepagents.backends import LocalShellBackend
from deepagents.backends.protocol import ExecuteResponse


class PlatformShellBackend(LocalShellBackend):
    """Use PowerShell on Windows and the native shell on hosted Linux."""

    def execute(
        self,
        command: str,
        *,
        timeout: int | None = None,
    ) -> ExecuteResponse:
        if os.name != "nt" or not command:
            return super().execute(command, timeout=timeout)

        encoded_command = base64.b64encode(command.encode("utf-16-le")).decode("ascii")
        powershell_command = (
            "pwsh -NoLogo -NoProfile -NonInteractive "
            f"-EncodedCommand {encoded_command}"
        )
        return super().execute(powershell_command, timeout=timeout)