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

Deux garde-fous l'appliquent : le `.gitignore` exclut `data/`, et une action GitHub (`.github/workflows/guard.yml`) fait échouer tout push ou pull request si un fichier de `data/`, quel que soit son format, est suivi par git ou si un secret est détecté (gitleaks).

### Chargement des fichiers RH

Les deux fichiers RH entrent dans `RAW` en trois temps, toujours avec le rôle des outils (`TRANSFORMER`) : `snowflake/rh/chargement_rh_1_preparer.sql`, le dépôt des CSV sur le stage depuis Snowsight, puis `snowflake/rh/chargement_rh_2_copier.sql`.

- Le **format de fichier** (`NYC_TAXI.RAW.CSV_RH`) dit à Snowflake comment lire un CSV : une ligne d'en-tête à sauter, des champs éventuellement entre guillemets, aucun espace retiré (`RAW` est une copie fidèle du fichier).
- Le **stage** (`NYC_TAXI.RAW.RH_STAGE`) est l'espace de dépôt interne où l'on pose les fichiers avant de les copier. Il est chiffré côté serveur et dispose d'une table de répertoire, ce qui permet le dépôt et la consultation depuis Snowsight.
- **`COPY INTO`** lit chaque fichier du stage, convertit les colonnes (`$1`, `$2`…) vers les types des tables, ajoute le nom du fichier et l'heure de chargement (`METADATA$FILENAME`, `METADATA$START_SCAN_TIME`), et s'arrête à la première erreur (`ON_ERROR = ABORT_STATEMENT`). Il garde l'historique des fichiers chargés : relancé, il ne charge rien de plus.
- **`PURGE = TRUE`** efface le fichier du stage une fois copié. C'est la règle R3 du contrat : le fichier du personnel ne séjourne pas dans l'entrepôt au-delà du chargement ; seules les tables, soumises aux règles d'accès, le conservent.

Chargement réussi quand `RAW.DRIVERS` compte 400 lignes, `RAW.DRIVER_SHIFTS` 25 951, et que `LIST @NYC_TAXI.RAW.RH_STAGE;` ne renvoie rien.

### Protections en place

| Protection | Ce qu'elle fait | Où | Preuve |
|---|---|---|---|
| Fichiers du personnel hors du dépôt | `data/` ignoré par git ; la CI échoue si un fichier de `data/` est suivi ou si un secret est détecté | `.gitignore`, `.github/workflows/guard.yml` | `git ls-files data/` vide ; run `guard` vert |
| Stage vidé après chargement (R3) | `PURGE = TRUE` retire le fichier du stage une fois copié | `snowflake/rh/chargement_rh_2_copier.sql` | `LIST @NYC_TAXI.RAW.RH_STAGE` vide |
| Séparation des rôles | `TRANSFORMER` possède les données et ne gouverne pas ; `GOUVERNANCE` écrit les règles et ne lit pas les données (aucun `SELECT`) ; `ACCOUNTADMIN` installe et se retire | `snowflake/gouvernance/01_gouvernance.sql` | `snowflake/verif/01_verif_gouvernance.sql` : 15 contrôles OK |
| Catalogue | description de chaque table et de chaque colonne de `DIM_DEPOT`, `DIM_DRIVER`, `RAW.DRIVERS` ; tags `SENSIBILITE` et `DUREE_CONSERVATION` sur les cinq tables | `snowflake/rh/catalogue/` | `snowflake/verif/02_verif_catalogue.sql` : 11 contrôles OK |
| Colonnes personnelles identifiées | tag `DONNEE_PERSONNELLE` sur 17 colonnes, avec sa nature (`nom`, `email`, `telephone`, `date_naissance`, `identifiant_officiel`, `identifiant_interne`), d'après l'inventaire de `docs/REGISTRE.md` | `snowflake/rh/catalogue/` | même script ; le masquage du jour 2 s'attachera à ce tag |
| Rôles métier en lecture seule | `RH_PAIE`, `RESP_DEPOT_QUEENS`, `RESP_DEPOT_BRONX`, `ANALYSTE` : `USAGE` + `SELECT` sur `MARTS` seulement (tables futures comprises pour l'analyste), rien sur `RAW` ni `STAGING`, aucun rôle hérité, aucune écriture | `snowflake/gouvernance/02_roles_metier.sql` | `snowflake/verif/03_verif_roles.sql` : 13 contrôles OK |
| Masquage par rôle | deux politiques attachées au tag `DONNEE_PERSONNELLE` (`MASK_TEXTE`, `MASK_DATE`) : 17 colonnes protégées dans `RAW` et `MARTS` d'un coup, selon le rôle actif et la nature de la donnée ; `TRANSFORMER` et `RH_PAIE` en clair, `driver_id` visible des rôles métier, année de naissance seule pour l'analyste | `snowflake/gouvernance/03_masquage.sql` | `snowflake/verif/04_verif_acces.sql` : 79 contrôles OK, un bloc par rôle |
| Accès par ligne (dépôt) | table `GOUVERNANCE.ACCES_DEPOT` (quel rôle voit quel dépôt) lue par la politique `RAP_DEPOT` sur `DIM_DRIVER` et `MART_DRIVER_MONTHLY` ; un rôle absent de la table ne voit aucune ligne (`ACCOUNTADMIN` compris) | `snowflake/gouvernance/04_acces_depot.sql` | même script : 161 / 365 pour Queens, 122 / 290 pour le Bronx, 0 pour l'administrateur |
| Purge et conservation (R1, R2) | _jour 3_ | | |
| Qualité | _jour 3_ | | |
| Audit | _jour 3_ | | |

### Ordre d'exécution des scripts

Chaque script commence par le rôle qui doit l'exécuter et finit par une requête de vérification : si elle n'affiche rien, une instruction a échoué plus haut. Tous sont rejouables.

| # | Script | Rôle | C'est bon quand |
|---|---|---|---|
| 1 | `snowflake/00_installation.sql` (fourni) | `ACCOUNTADMIN` | schémas `RAW`, `STAGING`, `MARTS` ; rôle `TRANSFORMER` |
| 2 | `snowflake/rh/chargement_rh_1_preparer.sql` (fourni) | `TRANSFORMER` | stage `RH_STAGE`, format `CSV_RH`, deux tables `RAW` |
| 3 | dépôt de `data/drivers.csv` et `data/driver_shifts.csv` sur `RH_STAGE` depuis Snowsight | `TRANSFORMER` | `LIST @NYC_TAXI.RAW.RH_STAGE` : 2 fichiers |
| 4 | `snowflake/rh/chargement_rh_2_copier.sql` (fourni, corrigé) | `TRANSFORMER` | `400 \| 25951 \| 0` ; relancé : même ligne |
| 5 | `snowflake/rh/00_tables_rh.sql` (fourni) | `TRANSFORMER` | 3 tables dans `MARTS` |
| 6 | `snowflake/rh/staging/stg_rh__drivers.sql`, `stg_rh__driver_shifts.sql` (fournis) | `TRANSFORMER` | 400 ; 25 933 |
| 7 | `snowflake/rh/marts/dim_depot.sql`, `dim_driver.sql`, `mart_driver_monthly.sql` (fournis) | `TRANSFORMER` | 3 ; 400 ; 914 |
| 8 | `snowflake/verif/01_verif_gouvernance.sql` | `ACCOUNTADMIN` | erreur attendue avant l'étape 9 (le rôle n'existe pas) |
| 9 | `snowflake/gouvernance/01_gouvernance.sql` | `ACCOUNTADMIN` puis `GOUVERNANCE` | `SHOW TAGS` : 3 lignes ; puis `verif/01` : 15 OK |
| 10 | `snowflake/verif/02_verif_catalogue.sql` | `TRANSFORMER` | des KO attendus avant l'étape 11 |
| 11 | `snowflake/rh/catalogue/catalogue_*.sql` (cinq fichiers, ordre indifférent) | `TRANSFORMER` | `verif/02` : 11 OK |
| 12 | `snowflake/verif/03_verif_roles.sql` | `ACCOUNTADMIN` | erreur attendue avant l'étape 13 (les rôles n'existent pas) |
| 13 | `snowflake/gouvernance/02_roles_metier.sql` | `ACCOUNTADMIN` | `SHOW GRANTS TO ROLE ANALYSTE` : 7 lignes ; puis `verif/03` : 13 OK |
| 14 | `snowflake/verif/04_verif_acces.sql` | un bloc par rôle | des KO attendus avant les étapes 15 et 16 (tout en clair, tous les dépôts visibles) |
| 15 | `snowflake/gouvernance/03_masquage.sql` | `GOUVERNANCE` | 17 colonnes protégées via le tag, `ACTIVE` ; `verif/04` : seuls les contrôles d'accès par ligne restent KO |
| 16 | `snowflake/gouvernance/04_acces_depot.sql` | `GOUVERNANCE` | `RAP_DEPOT` `ACTIVE` sur `DIM_DRIVER` et `MART_DRIVER_MONTHLY` ; puis `verif/04` : 79 OK, 0 KO |

À partir de l'étape 12, les scripts s'exécutent avec la CLI `snow` (`snow sql -c <connexion> -f <script>`), authentifiée par paire de clés ; la connexion n'est pas dans le dépôt. Tous les tests de rôle commencent par `USE SECONDARY ROLES NONE` : sans cela, Snowflake additionne les droits de tous les rôles de l'utilisateur et un test « refusé » renvoie des lignes.

Les règles doivent survivre au pipeline : les scripts de `marts/` remplissent les tables par `INSERT OVERWRITE` sans les recréer, donc les descriptions, les tags et les politiques restent en place après une relance des étapes 5 à 7. Vérification : relancer 5 à 7, puis `verif/02` et `verif/04`. Fait le 2026-11-03 (`verif/02` : 11 OK) et le 2026-11-24, politiques posées : 3 / 400 / 914, `verif/02` 11 OK, `verif/04` 79 OK ; le rôle des outils, présent dans `ACCES_DEPOT` et en clair dans les politiques, a reconstruit le mart avec de vraies valeurs (`driver_name` `NULL` sur 25 lignes seulement, les services sans chauffeur connu, comme avant).

Captures Snowsight des tags de `DIM_DRIVER` : `docs/capture_tags_dim_driver.png` (tags et description de la table, descriptions de colonnes) et `docs/capture_tags_colonnes_dim_driver.png` (tag `DONNEE_PERSONNELLE` colonne par colonne).

Capture de la même requête lue par trois rôles : `docs/capture_meme_requete_deux_roles.png` (sortie de la CLI `snow`, rendue en image). La requête compte par dépôt les chauffeurs, les e-mails en clair et les dates de naissance absentes, sans afficher une seule valeur personnelle : `RH_PAIE` voit 3 dépôts, 400 chauffeurs, 400 e-mails en clair ; `RESP_DEPOT_QUEENS` voit Queens seul, 161 chauffeurs, 0 e-mail en clair, 161 dates absentes ; `ANALYSTE` voit les 3 dépôts, 0 e-mail en clair, 0 date absente (l'année est conservée).

### Choix et limites

- **Script de copie fourni rendu rejouable.** `chargement_rh_2_copier.sql` désignait les fichiers par `FILES = ('drivers.csv')`. Combiné à `PURGE = TRUE`, il échouait à la relance (« Remote file was not found ») : le fichier purgé est exigé nommément. Remplacé par `PATTERN = '.*drivers[.]csv'`, qui charge ce qui correspond et traite zéro fichier sans erreur. La vérification finale tient en une requête (`LIST ->> SELECT`), lisible d'un coup dans Snowsight.
- **Le staging fourni dédoublonne en silence.** `STG_RH__DRIVER_SHIFTS` ne garde qu'une ligne par `shift_id` (`QUALIFY ROW_NUMBER() … = 1`) : 25 951 lignes dans `RAW`, 25 933 dans la vue. Une vue de staging devrait rester 1:1 avec sa source ; ici une décision (quelle version d'un service garder) est prise sans trace. Vérifié : les 18 lignes en trop sont des doublons stricts (mêmes valeurs dans toutes les colonnes), donc le choix non déterministe de la ligne conservée est sans effet sur les résultats. Le SQL fourni n'est pas modifié ; en contrepartie, la règle de qualité `service_unique` (jour 3) mesure les doublons dans **`RAW`**, pas dans la vue, qui les a déjà fait disparaître.
- **Des colonnes personnelles sans tag.** L'inventaire (`docs/REGISTRE.md`) classe `depot`, `hire_date`, `end_date`, et les colonnes calculées `is_active` et `tenure_years`, comme données personnelles **indirectes**. Le vocabulaire imposé du tag `DONNEE_PERSONNELLE` (`nom`, `email`, `telephone`, `date_naissance`, `identifiant_officiel`, `identifiant_interne`) n'a aucune valeur pour elles : elles ne portent pas le tag, donc aucun masquage ne s'y attachera. Leur description le dit ; leur protection vient du niveau `confidentiel` de la table et de l'accès par ligne sur `depot` (jour 2). Écart entre l'inventaire et le contrat, signalé sans modifier ce dernier.
- **Le modèle de catalogue du kit a été déplacé** de `snowflake/gouvernance/modele_catalogue_dim_depot.sql` vers `snowflake/rh/catalogue/catalogue_dim_depot.sql`, pour que le dossier `catalogue/` contienne une fiche par table ; son corps est inchangé.
- **Masquer plutôt que supprimer, pour chaque colonne personnelle.** Le contrat laisse le choix ; ici aucune colonne n'est retirée des tables, parce que `RH_PAIE` doit lire chacune d'elles en clair et qu'une colonne supprimée pour l'analyste le serait aussi pour la paie. Colonne par colonne : `first_name`, `last_name`, `phone` (tag `nom`, `telephone`) en clair pour la paie et les responsables de dépôt, qui appellent leurs chauffeurs, `*****` pour l'analyste ; `email` en clair pour la paie, `*****@<domaine>` pour les autres (la partie locale identifie, le domaine non) ; `tlc_license_number` (`identifiant_officiel`) en clair pour la paie seule, `*****` sinon : public à New York, il désigne une personne sans ambiguïté et personne d'autre n'en a l'usage ; `birth_date` en clair pour la paie, réduite au 1er janvier de l'année pour l'analyste (le catalogue dit qu'elle n'a besoin que de l'année), `NULL` pour tout autre rôle (une fausse date entrerait dans un calcul d'âge sans erreur) ; `driver_name` du mart, calculé à partir de `DIM_DRIVER`, suit la règle de `nom`. `driver_id` (`identifiant_interne`) reste visible de tous les rôles métier, comme le contrat l'exige, pour compter et joindre sans nommer ; il est masqué pour les rôles hors de la matrice (`ACCOUNTADMIN`, `SYSADMIN`), pour qui le contrat dit « rien ». Le détail et les preuves : `docs/ACCES.md`, partie 2.
- **Un masque remplace aussi les `NULL`** : l'analyste lit `*****` sur les 400 téléphones, y compris les 12 vides du fichier, et ne sait donc pas qui n'a pas de téléphone. Accepté : c'est une information sur une personne.
- **Sept e-mails du fichier n'ont pas de `@`** (écrits « prénom.nom at domaine »). Le masque partiel « garder le domaine » n'a rien à garder et les aurait laissés en clair : la politique masque entièrement une valeur sans `@`. L'anomalie elle-même relève de la règle de qualité `email_valide` (jour 3).
- **Les politiques lisent le rôle actif** (`CURRENT_ROLE()`), pas la hiérarchie ni les rôles secondaires. `SYSADMIN` et `ACCOUNTADMIN` héritent de tous les rôles du brief et pourraient défaire la protection en deux `USE ROLE` ; tant qu'ils restent eux-mêmes, ils ne voient aucune ligne de `DIM_DRIVER` ni du mart et lisent `RAW` masqué. Risque documenté dans `docs/ACCES.md` (« ce que cette carte permet de défaire ») ; l'audit du jour 3 nomme le rôle qui a lu.
- **Pas de politique de lignes sur `RAW`.** Les rôles métier n'y ont aucun droit ; les administrateurs y voient les lignes par héritage, colonnes personnelles masquées, ce que le contrat décrit lui-même (section 4). La politique de lignes porte sur `DIM_DRIVER` et `MART_DRIVER_MONTHLY`, les tables que les rôles métier lisent.
- **Le compte de lignes du catalogue n'est pas filtré.** `INFORMATION_SCHEMA.TABLES.row_count` de `DIM_DRIVER` vaut 400 pour un responsable de dépôt qui ne voit que 161 chauffeurs : c'est le compte physique des micro-partitions, hors de portée de la politique. Aucune donnée personnelle n'en sort ; limite connue, testée dans `verif/04`.
- **Ouvrir un dépôt, c'est une ligne, pas une politique.** Un responsable pour Brooklyn ou Staten Island demain : `INSERT INTO GOUVERNANCE.ACCES_DEPOT`, le rôle correspondant dans `02_roles_metier.sql`, et une branche de plus dans `MASK_TEXTE` si ce rôle doit voir des colonnes en clair. La politique de lignes, elle, ne change pas.
- **Un seul étage de rôles.** Les six rôles du contrat sont donnés directement aux utilisateurs ; la pratique courante sépare des rôles d'accès techniques (`MARTS_READ`…) et des rôles fonctionnels qui en héritent. À l'échelle du brief, l'étage supplémentaire n'apporterait rien ; la carte des droits (`docs/ACCES.md`) tient lieu de référentiel.

### Écarts avec le contrat

_À compléter depuis `docs/VEILLE.md`, section 4._
