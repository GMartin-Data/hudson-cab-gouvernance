# hudson-cab-gouvernance

Gouvernance d'un entrepôt Snowflake de données du personnel : les chauffeurs de Hudson Cab Partners (New York), gérés depuis Paris par Hudson Cab Europe. Catalogue, masquage, accès par ligne, conservation, qualité, audit. Brief pédagogique de trois jours ; ce dépôt est le livrable.

Documents de référence :

- `CONTRAT_GOUVERNANCE.md` : ce qui est imposé (objets, rôles, matrice des accès, règles). Il ne se modifie pas ; les écarts se signalent ci-dessous.
- `GUIDE_BRIEF_GOUVERNANCE.md` : les étapes suivies.
- `docs/VEILLE.md` : droit applicable, dispositif de veille, fiches, contrat face aux textes.
- `docs/REGISTRE.md` : inventaire des données personnelles et registre du traitement.
- `docs/ACCES.md` : droits accordés et cahier de tests des accès.

## Gouvernance

### Les fichiers du personnel ne sont pas publiés

`data/` entre dans `.gitignore` pour le prémunir d'un versioning qui **exposerait des données personnelles** (même si ici, dans le cadre de ce projet pédagogique, elles sont *fictives*) sur un dépôt **public**. Rappelons que cette précaution initiale protège définitivement d'un leak qui, même après suppression a posteriori, en guise de correctif, verrait tout de même ces données demeurer dans l'historique, ce qui est tout à fait inacceptable.

Deux garde-fous l'appliquent : le `.gitignore` exclut `data/`, et une action GitHub (`.github/workflows/guard.yml`) fait échouer tout push ou pull request si un `data/*.csv` est suivi par git ou si un secret est détecté (gitleaks).

### Chargement des fichiers RH

_À rédiger à l'étape 8 : format de fichier, stage, `COPY INTO`, `PURGE = TRUE` (règle R3)._

### Protections en place

_À compléter au fil des trois jours : catalogue et tags, masquage, accès par ligne, purge, qualité, audit._

### Ordre d'exécution des scripts

_À compléter : quel script, avec quel rôle, dans quel ordre, et comment vérifier que les règles survivent au pipeline._

### Choix et limites

_À compléter._

### Écarts avec le contrat

_À compléter depuis `docs/VEILLE.md`, section 4._
