# CLEMENT_STUDIO_P0_BOOTSTRAP

Installateur maitre des quatre P0 de CLEMENT STUDIO.

## Etat v0.1.0

Cette premiere tranche est volontairement `DRY-RUN` : elle modelise les dependances et refuse les cycles avant toute future mutation du poste Shadow.

Ordre logique :

- P0-01 Skills Hub ;
- P0-02 Skills MCP depend de P0-01 ;
- P0-03 OmniRoute peut etre certifie en parallele ;
- P0-04 Dynamic Orchestrator depend de P0-01, P0-02 et P0-03.

## Garanties cibles

- idempotence ;
- backups avant mutations ;
- verification des branches et worktrees ;
- hashes SHA256 ;
- PASS/PARTIAL/FAIL/INCONCLUSIVE ;
- aucune suppression ou reset implicite ;
- aucun merge, tag ou release sans validation utilisateur.

## Developpement

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -e ".[dev]"
.\.venv\Scripts\python.exe -m pytest
```
