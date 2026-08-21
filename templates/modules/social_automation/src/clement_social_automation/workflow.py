from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Protocol


class ApprovalState(str, Enum):
    DRAFT = "DRAFT"
    REVIEWED = "REVIEWED"
    APPROVED = "APPROVED"
    REJECTED = "REJECTED"


@dataclass(frozen=True, slots=True)
class ContentDraft:
    content_id: str
    channel: str
    text: str
    approval: ApprovalState = ApprovalState.DRAFT


@dataclass(frozen=True, slots=True)
class PublishResult:
    content_id: str
    provider_id: str | None
    status: str
    evidence: dict


class SocialProvider(Protocol):
    def publish(self, draft: ContentDraft) -> PublishResult: ...


def can_publish(draft: ContentDraft) -> bool:
    return draft.approval is ApprovalState.APPROVED


def publish_with_approval(provider: SocialProvider, draft: ContentDraft) -> PublishResult:
    if not can_publish(draft):
        return PublishResult(draft.content_id, None, "BLOCKED_APPROVAL_REQUIRED", {"approval": draft.approval.value})
    result = provider.publish(draft)
    if not result.provider_id:
        return PublishResult(draft.content_id, None, "INCONCLUSIVE", result.evidence)
    return result
