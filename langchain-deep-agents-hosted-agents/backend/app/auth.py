import base64
import json
from typing import Annotated

from fastapi import Header, HTTPException

from .config import get_settings
from .models import UserContext


def get_user(
    client_principal: Annotated[str | None, Header(alias="x-ms-client-principal")] = None,
) -> UserContext:
    settings = get_settings()
    if settings.local_development:
        return UserContext(owner_id=settings.local_owner_id, display_name=settings.local_user_name, email=settings.local_user_email)
    if not client_principal:
        raise HTTPException(status_code=401, detail="Sign in through Azure Static Web Apps.")
    try:
        padding = "=" * (-len(client_principal) % 4)
        payload = json.loads(base64.b64decode(client_principal + padding))
        owner_id = payload.get("userId")
        if not owner_id or "authenticated" not in payload.get("userRoles", []):
            raise ValueError("Missing authenticated user")
        user_details = payload.get("userDetails")
        return UserContext(owner_id=owner_id, display_name=user_details, email=user_details)
    except (ValueError, json.JSONDecodeError) as exc:
        raise HTTPException(status_code=401, detail="Invalid Static Web Apps principal.") from exc