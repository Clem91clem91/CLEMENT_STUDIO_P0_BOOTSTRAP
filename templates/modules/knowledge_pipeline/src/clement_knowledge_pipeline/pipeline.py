from __future__ import annotations

import hashlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True, slots=True)
class KnowledgeSource:
    source_id: str
    source_type: str
    locator: str
    license: str | None = None


@dataclass(frozen=True, slots=True)
class KnowledgeDocument:
    document_id: str
    sha256: str
    byte_size: int
    source: KnowledgeSource
    text: str


class KnowledgeRegistry:
    def __init__(self) -> None:
        self._documents_by_hash: dict[str, KnowledgeDocument] = {}

    def ingest_bytes(self, *, content: bytes, source: KnowledgeSource, text: str | None = None) -> KnowledgeDocument:
        digest = hashlib.sha256(content).hexdigest()
        existing = self._documents_by_hash.get(digest)
        if existing is not None:
            return existing
        decoded = text if text is not None else content.decode("utf-8", errors="replace")
        doc = KnowledgeDocument(
            document_id=f"DOC-{digest[:16]}",
            sha256=digest,
            byte_size=len(content),
            source=source,
            text=decoded,
        )
        self._documents_by_hash[digest] = doc
        return doc

    def ingest_file(self, path: str | Path, *, license: str | None = None) -> KnowledgeDocument:
        file_path = Path(path)
        content = file_path.read_bytes()
        source = KnowledgeSource(
            source_id=f"FILE-{hashlib.sha256(str(file_path.resolve()).encode('utf-8')).hexdigest()[:12]}",
            source_type="FILE",
            locator=str(file_path.resolve()),
            license=license,
        )
        return self.ingest_bytes(content=content, source=source)

    def documents(self) -> tuple[KnowledgeDocument, ...]:
        return tuple(self._documents_by_hash.values())

    def search(self, query: str) -> tuple[KnowledgeDocument, ...]:
        needle = query.casefold().strip()
        if not needle:
            return ()
        return tuple(doc for doc in self._documents_by_hash.values() if needle in doc.text.casefold())


def license_allows_automated_ingestion(license_name: str | None) -> bool | None:
    if license_name is None or not license_name.strip():
        return None
    normalized = license_name.casefold().replace("_", "-")
    allowed_markers = ("public-domain", "cc0", "cc-by", "cc-by-sa", "mit", "apache-2")
    if any(marker in normalized for marker in allowed_markers):
        return True
    restricted_markers = ("all-rights-reserved", "no-redistribution")
    if any(marker in normalized for marker in restricted_markers):
        return False
    return None
