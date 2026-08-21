from clement_social_automation.workflow import ApprovalState, ContentDraft, PublishResult, publish_with_approval


class Provider:
    def publish(self, draft: ContentDraft) -> PublishResult:
        return PublishResult(draft.content_id, "provider-post-1", "PUBLISHED", {"ok": True})


def test_unapproved_content_is_blocked() -> None:
    draft = ContentDraft("C1", "social", "hello", ApprovalState.DRAFT)
    result = publish_with_approval(Provider(), draft)
    assert result.status == "BLOCKED_APPROVAL_REQUIRED"
    assert result.provider_id is None


def test_approved_content_can_reach_provider() -> None:
    draft = ContentDraft("C1", "social", "hello", ApprovalState.APPROVED)
    result = publish_with_approval(Provider(), draft)
    assert result.status == "PUBLISHED"
    assert result.provider_id == "provider-post-1"
