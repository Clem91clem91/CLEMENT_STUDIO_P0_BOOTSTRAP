# CLEMENT STUDIO — Cognitive Operating System Target

Status: architecture cible approuvée pour la production GitHub.

## Principe directeur

Odysseus reste le runtime/interface principal, mais la propriété cognitive appartient à CLEMENT STUDIO. Les modèles sont remplaçables et ne possèdent ni la mémoire ni la connaissance.

```text
USER
  -> ODYSSEUS UI/API
  -> CLEMENT CORE / Odysseus Adapter
  -> INTENT
  -> MEMORY + KNOWLEDGE
  -> CONTEXT BUILDER
  -> SKILLS
  -> DYNAMIC ORCHESTRATOR
  -> AGENTS + MENTALITIES + ARENA
  -> MODEL ROUTER + ACTION BUS + RESOURCE MANAGER
  -> EXECUTION
  -> RAW EVIDENCE -> PROVENANCE -> CONSISTENCY -> VERIFIER
  -> RESULT
  -> EVENT BUS -> MEMORY / KNOWLEDGE / OBSERVABILITY / PERFORMANCE HISTORY
```

## Cores stables

- `CLEMENT_STUDIO_CORE`: contrats partagés, contexte, événements, provenance, Integration Decision Engine et adapters runtime.
- `CLEMENT_STUDIO_INTENT`: Intent Compiler, contraintes, risque, capacités requises et résultat attendu.
- `CLEMENT_STUDIO_MEMORY`: Working/User/Project/Technical/Procedural/Episodic/Decision/Archive, temporalité et statuts ACTIVE/SUPERSEDED/ARCHIVED/UNCERTAIN.
- `CLEMENT_STUDIO_KNOWLEDGE_PIPELINE`: ingestion, normalisation, extraction et politiques d'ingestion.
- `CLEMENT_STUDIO_KNOWLEDGE`: ontologie, entités, relations, entity resolution, temporal graph, provenance et Digital Twin.
- `CLEMENT_STUDIO_ORCHESTRATOR`: skills, mentalities, Agent Factory, coalitions, Arena, verifier et apprentissage historique.
- `CLEMENT_STUDIO_OMNIROUTE`: routage de modèles uniquement.
- `CLEMENT_STUDIO_MCP_HUB`: Action Bus / capability routing.
- `CLEMENT_STUDIO_GPU_MANAGER`: ressources, VRAM, réservation et scheduling.
- `CLEMENT_STUDIO_VERIFIED_RESPONSE`: evidence/provenance/consistency/verdict final.

## Règles d'intégration

Chaque technologie externe est évaluée avec `KEEP | ADAPT | FORK | REIMPLEMENT | REJECT` avant adoption. Mem0, Graphiti, Neo4j, OpenMetadata, OpenAleph, OSIRIS et autres restent des moteurs potentiellement interchangeables derrière les API CLEMENT.

## Séparation Memory / Knowledge / Events

- Memory = ce que CLEMENT doit retenir.
- Knowledge = ce qui existe et comment les objets sont reliés.
- Event = ce qui s'est produit à un instant donné.

Les trois peuvent se référencer mais ne partagent pas le même contrat de stockage.

## Production immédiate

Wave Cognitive Foundation crée d'abord trois nouveaux repos privés :

1. `CLEMENT_STUDIO_CORE`
2. `CLEMENT_STUDIO_INTENT`
3. `CLEMENT_STUDIO_KNOWLEDGE`

Les repos Wave A existants sont conservés et seront étendus par branches dédiées après validation du socle.

## Gouvernance

- Windows 11 / PowerShell prioritaire.
- Pas de Docker / WSL / Hyper-V.
- GitHub-first.
- Feature branches + tests + draft PR.
- Aucun merge, tag ou release sans validation explicite.
- Fail-closed : tests en échec => pas de certification.
