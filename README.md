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

Les deux fichiers RH entrent dans `RAW` en trois temps, toujours avec le rôle des outils (`TRANSFORMER`) : `snowflake/rh/chargement_rh_1_preparer.sql`, le dépôt des CSV sur le stage depuis Snowsight, puis `snowflake/rh/chargement_rh_2_copier.sql`.

- Le **format de fichier** (`NYC_TAXI.RAW.CSV_RH`) dit à Snowflake comment lire un CSV : une ligne d'en-tête à sauter, des champs éventuellement entre guillemets, aucun espace retiré (`RAW` est une copie fidèle du fichier).
- Le **stage** (`NYC_TAXI.RAW.RH_STAGE`) est l'espace de dépôt interne où l'on pose les fichiers avant de les copier. Il est chiffré côté serveur et dispose d'une table de répertoire, ce qui permet le dépôt et la consultation depuis Snowsight.
- **`COPY INTO`** lit chaque fichier du stage, convertit les colonnes (`$1`, `$2`…) vers les types des tables, ajoute le nom du fichier et l'heure de chargement (`METADATA$FILENAME`, `METADATA$START_SCAN_TIME`), et s'arrête à la première erreur (`ON_ERROR = ABORT_STATEMENT`). Il garde l'historique des fichiers chargés : relancé, il ne charge rien de plus.
- **`PURGE = TRUE`** efface le fichier du stage une fois copié. C'est la règle R3 du contrat : le fichier du personnel ne séjourne pas dans l'entrepôt au-delà du chargement ; seules les tables, soumises aux règles d'accès, le conservent.

Chargement réussi quand `RAW.DRIVERS` compte 400 lignes, `RAW.DRIVER_SHIFTS` 25 951, et que `LIST @NYC_TAXI.RAW.RH_STAGE;` ne renvoie rien.

### Protections en place

_À compléter au fil des trois jours : catalogue et tags, masquage, accès par ligne, purge, qualité, audit._

### Ordre d'exécution des scripts

_À compléter : quel script, avec quel rôle, dans quel ordre, et comment vérifier que les règles survivent au pipeline._

### Choix et limites

- **Script de copie fourni rendu rejouable.** `chargement_rh_2_copier.sql` désignait les fichiers par `FILES = ('drivers.csv')`. Combiné à `PURGE = TRUE`, il échouait à la relance (« Remote file was not found ») : le fichier purgé est exigé nommément. Remplacé par `PATTERN = '.*drivers[.]csv'`, qui charge ce qui correspond et traite zéro fichier sans erreur. La vérification finale tient en une requête (`LIST ->> SELECT`), lisible d'un coup dans Snowsight.
- **Le staging fourni dédoublonne en silence.** `STG_RH__DRIVER_SHIFTS` ne garde qu'une ligne par `shift_id` (`QUALIFY ROW_NUMBER() … = 1`) : 25 951 lignes dans `RAW`, 25 933 dans la vue. Une vue de staging devrait rester 1:1 avec sa source ; ici une décision (quelle version d'un service garder) est prise sans trace. Vérifié : les 18 lignes en trop sont des doublons stricts (mêmes valeurs dans toutes les colonnes), donc le choix non déterministe de la ligne conservée est sans effet sur les résultats. Le SQL fourni n'est pas modifié ; en contrepartie, la règle de qualité `service_unique` (jour 3) mesure les doublons dans **`RAW`**, pas dans la vue, qui les a déjà fait disparaître.
- **Des colonnes personnelles sans tag.** L'inventaire (`docs/REGISTRE.md`) classe `depot`, `hire_date`, `end_date`, et les colonnes calculées `is_active` et `tenure_years`, comme données personnelles **indirectes**. Le vocabulaire imposé du tag `DONNEE_PERSONNELLE` (`nom`, `email`, `telephone`, `date_naissance`, `identifiant_officiel`, `identifiant_interne`) n'a aucune valeur pour elles : elles ne portent pas le tag, donc aucun masquage ne s'y attachera. Leur description le dit ; leur protection vient du niveau `confidentiel` de la table et de l'accès par ligne sur `depot` (jour 2). Écart entre l'inventaire et le contrat, signalé sans modifier ce dernier.
- **Le modèle de catalogue du kit a été déplacé** de `snowflake/gouvernance/modele_catalogue_dim_depot.sql` vers `snowflake/rh/catalogue/catalogue_dim_depot.sql`, pour que le dossier `catalogue/` contienne une fiche par table ; son corps est inchangé.

### Écarts avec le contrat

_À compléter depuis `docs/VEILLE.md`, section 4._
