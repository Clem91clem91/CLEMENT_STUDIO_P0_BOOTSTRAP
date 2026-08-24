from clement_knowledge_pipeline.pipeline import KnowledgeRegistry, KnowledgeSource, license_allows_automated_ingestion


def test_hash_deduplication_keeps_single_document() -> None:
    registry = KnowledgeRegistry()
    source_a = KnowledgeSource("S1", "WEB", "https://example/a", "CC-BY-4.0")
    source_b = KnowledgeSource("S2", "DRIVE", "drive:file", "CC-BY-4.0")
    first = registry.ingest_bytes(content=b"same content", source=source_a)
    second = registry.ingest_bytes(content=b"same content", source=source_b)
    assert first.document_id == second.document_id
    assert len(registry.documents()) == 1


def test_search_uses_ingested_text() -> None:
    registry = KnowledgeRegistry()
    source = KnowledgeSource("S1", "FILE", "memory.txt", "CC0")
    registry.ingest_bytes(content=b"CLEMENT evidence contract", source=source)
    assert len(registry.search("evidence")) == 1


def test_unknown_license_is_not_assumed_allowed() -> None:
    assert license_allows_automated_ingestion(None) is None
    assert license_allows_automated_ingestion("unknown") is None
    assert license_allows_automated_ingestion("CC-BY-4.0") is True
    assert license_allows_automated_ingestion("all-rights-reserved") is False
