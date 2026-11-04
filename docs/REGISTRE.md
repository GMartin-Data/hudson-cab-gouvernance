# Registre du traitement — données du personnel

Il se remplit en deux temps :

- **Partie 1, jour 1** : l'inventaire des données personnelles des deux fichiers, avant tout chargement ;
- **Partie 2, jour 3** : la fiche de registre, qui s'appuie sur l'inventaire et sur ce que vous avez construit.

---

## Partie 1 — Inventaire des données personnelles (jour 1)

Une donnée personnelle est une information qui se rapporte à une personne identifiée ou identifiable. Trois cas à distinguer :

- **identifiant direct** : la colonne suffit à désigner la personne (un nom, un e-mail) ;
- **identifiant indirect** : la colonne ne suffit pas seule, mais permet d'identifier quelqu'un une fois combinée à d'autres (une date de naissance et un dépôt) ;
- **pas une donnée personnelle** : la colonne ne dit rien d'une personne.

### `drivers.csv` : les colonnes

| Colonne | Exemple de valeur | Donnée personnelle ? (direct, indirect, non) | Valeur du tag `DONNEE_PERSONNELLE` | Qui en a besoin, et pour quoi faire |
|---|---|---|---|---|
| `driver_id` | D0500 | indirect | `identifiant_interne` | tous les rôles métiers (clé de jointure) |
| `first_name` | Luc | direct | `nom` | RH_PAIE: dossier du salarié, RESP_DEPOTs: contact |
| `last_name` | Dupont | direct | `nom` | RH_PAIE: dossier du salarié, RESP_DEPOTs: contact |
| `email` | prenom.nom@domaine.exemple | direct | `email` | RH_PAIE: dossier du salarié, ANALYSTE: aucun besoin |
| `phone` | +1 (917) 555-0000 | direct | `telephone` | RH_PAIE: dossier du salarié, RESP_DEPOT: contacter par téléphone le chauffeur, ANALYSTE: aucun besoin |
| `birth_date` | YYYY-MM-DD | indirect | `date_naissance` | RH_PAIE: dossier du salarié, ANALYSTE: uniquement l'année de naissance
| `tlc_license_number` | 5851973 | direct | `identifiant_officiel` | RH_PAIE: dossier du salarié, ANALYSTE: aucun besoin 
| `depot` | Bronx | indirect | | RH_PAIE: dossier du salarié, RESP_DEPOT: ouvre leurs lignes, ANALYSTE: axe d'analyse
| `hire_date` | YYYY-MM-DD | indirect | | RH_PAIE: dossier du salarié, ANALYSTE |
| `end_date` | YYYY-MM-DD | indirect | | RH_PAIE: dossier du salarié, ANALYSTE |

### `driver_shifts.csv` : les colonnes

| Colonne | Exemple de valeur | Donnée personnelle ? (direct, indirect, non) | Valeur du tag `DONNEE_PERSONNELLE` | Qui en a besoin, et pour quoi faire |
|---|---|---|---|---|
| `shift_id`| S000000 | non | | ANALYSTE |
| `driver_id`| D0500 | indirect | `identifiant_interne` | ANALYSTE |
| `shift_date`| YYYY-MM-DD | non | | ANALYSTE |
| `depot` | Bronx | indirect | | RESP_DEPOT: Ouvre leurs lignes, ANALYSTE: axe d'analyse
| `start_hour`| 10 | non | | RESP_DEPOT: organisation des prises de poste, ANALYSTE |
| `hours_worked`| 7.5 | non | | ANALYSTE |
| `trips_count`| 25 | non | | ANALYSTE |
| `revenue_usd`| 543.21 | non | | RH_PAIE, ANALYSTE |

### Où cette donnée est-elle copiée ?

Pour chaque colonne personnelle : la liste des tables et des vues de l'entrepôt où elle se retrouve, y compris sous une autre forme (colonne renommée, colonne calculée). À compléter au fil des trois jours.

Table déduite des SQL fournis (`snowflake/rh/chargement_rh_2_copier.sql`, `staging/`, `marts/`). Les vues de `STAGING` lisent `RAW` sans rien stocker : ce qui protège `RAW` s'applique à elles. Lignes en gras : colonnes qui n'existent dans aucun fichier.

| Colonne d'origine | Table ou vue | Colonne | Sous quelle forme |
|---|---|---|---|
| `driver_id` (les deux fichiers) | `RAW.DRIVERS`, `RAW.DRIVER_SHIFTS` | `driver_id` | copie fidèle |
| `driver_id` | `STAGING.STG_RH__DRIVERS`, `STAGING.STG_RH__DRIVER_SHIFTS` | `driver_id` | tel quel (vue) |
| `driver_id` | `MARTS.DIM_DRIVER`, `MARTS.MART_DRIVER_MONTHLY` | `driver_id` | tel quel ; clé de jointure entre les deux tables |
| `first_name` | `RAW.DRIVERS`, `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `first_name` | tel quel |
| `last_name` | `RAW.DRIVERS`, `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `last_name` | tel quel |
| **`first_name` + `last_name`** | **`MARTS.MART_DRIVER_MONTHLY`** | **`driver_name`** | **colonne calculée : `first_name \|\| ' ' \|\| last_name` ; une ligne par chauffeur et par mois** |
| `email` | `RAW.DRIVERS` | `email` | copie fidèle |
| `email` | `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `email` | `LOWER(TRIM(email))` : même donnée, normalisée |
| `phone` | `RAW.DRIVERS` | `phone` | copie fidèle |
| `phone` | `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `phone` | `NULLIF(TRIM(phone), '')` : même donnée, vide devient NULL |
| `birth_date` | `RAW.DRIVERS`, `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `birth_date` | tel quel (typée `DATE`) |
| `tlc_license_number` | `RAW.DRIVERS`, `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `tlc_license_number` | tel quel |
| `depot` (chauffeurs) | `RAW.DRIVERS` | `depot` | copie fidèle, casse et espaces d'origine |
| `depot` (chauffeurs) | `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `depot` | `INITCAP(TRIM(depot))` : normalisé |
| `depot` (services) | `RAW.DRIVER_SHIFTS`, `STAGING.STG_RH__DRIVER_SHIFTS`, `MARTS.MART_DRIVER_MONTHLY` | `depot` | copie fidèle, puis normalisé, puis axe d'agrégation |
| `hire_date` | `RAW.DRIVERS`, `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `hire_date` | tel quel |
| `end_date` | `RAW.DRIVERS`, `STAGING.STG_RH__DRIVERS`, `MARTS.DIM_DRIVER` | `end_date` | tel quel ; vide = en poste |
| **`end_date`** | **`MARTS.DIM_DRIVER`** | **`is_active`** | **colonne calculée : `end_date IS NULL`** |
| **`hire_date` + `end_date`** | **`MARTS.DIM_DRIVER`** | **`tenure_years`** | **colonne calculée : ancienneté en années, `DATEDIFF` jusqu'à `end_date` ou aujourd'hui** |
| `shift_date` | `RAW.DRIVER_SHIFTS`, `STAGING.STG_RH__DRIVER_SHIFTS` | `shift_date` | tel quel |
| `shift_date` | `MARTS.MART_DRIVER_MONTHLY` | `activity_month` | tronquée au mois |
| `hours_worked`, `trips_count`, `revenue_usd` | `RAW.DRIVER_SHIFTS`, `STAGING.STG_RH__DRIVER_SHIFTS` | mêmes noms | tel quel (dédoublonnage par `shift_id` dans la vue) |
| `hours_worked`, `trips_count`, `revenue_usd` | `MARTS.MART_DRIVER_MONTHLY` | `nb_shifts`, `hours_worked`, `trips_count`, `revenue_usd` | sommes par chauffeur, mois et dépôt : activité d'une personne identifiée par `driver_id` |
| `start_hour` | `RAW.DRIVER_SHIFTS`, `STAGING.STG_RH__DRIVER_SHIFTS` | `start_hour` | tel quel ; absente de `MARTS` |
| `shift_id` | `RAW.DRIVER_SHIFTS`, `STAGING.STG_RH__DRIVER_SHIFTS` | `shift_id` | tel quel ; absente de `MARTS` |

Colonnes techniques `_source_file`, `_loaded_at` (`RAW`), renommées `source_file`, `loaded_at` dans `STAGING` : nom du fichier et heure de chargement, pas une donnée personnelle.

### Ce qui a surpris

- **Le prénom est un identifiant direct.** Pris seul il semble anodin ; avec le nom il désigne une personne, et `driver_name` dans `MART_DRIVER_MONTHLY` recolle les deux. Un prénom sans tag aurait laissé l'analyste nommer tout le monde.
- **Aucune colonne du fichier n'est inutile, mais trois n'ont qu'un seul lecteur légitime** : `email`, `tlc_license_number` et la date de naissance complète ne servent qu'au service paie. Elles sont pourtant copiées dans une table (`DIM_DRIVER`) que quatre rôles lisent. La question du jour 2, masquer ou supprimer, part de là.
- **Donnée personnelle et colonne taguée ne se recouvrent pas.** `depot`, `hire_date`, `end_date`, `tenure_years`, `is_active` et les mesures d'activité décrivent une personne sans qu'aucune valeur du tag `DONNEE_PERSONNELLE` ne leur corresponde. Le masquage ne les protège pas ; ce sont le filtrage des lignes et la purge qui le font. Ce « vide » est à dire dans le registre, pas à combler avec des tags hors contrat.
- **La durée de vie des données n'est pas une colonne, c'est une règle.** Quand un chauffeur sort de `DRIVERS` au titre de R1, ses services dans `DRIVER_SHIFTS` et ses lignes mensuelles restent rattachées à un `driver_id` qui ne désigne plus personne dans l'entrepôt. Ce qu'ils deviennent se tranche au jour 3, avec la règle `service_rattache`.

---

## Partie 2 — Fiche de registre (jour 3)

Le registre des activités de traitement décrit ce qu'une organisation fait des données personnelles qu'elle détient. Cette fiche en est une version réduite, limitée à ce qu'un Data Engineer peut renseigner et prouver. La trame complète est celle de la CNIL (lien dans les ressources).

Chaque réponse de la colonne de droite doit pouvoir être vérifiée dans l'entrepôt : indiquez la requête ou le fichier qui le prouve.

### Le traitement

| Rubrique | Réponse |
|---|---|
| Nom du traitement | |
| Finalité : à quoi servent ces données | |
| Personnes concernées | |
| Service responsable des données | |

### Les données

| Catégorie de données | Colonnes concernées | Tables où elles se trouvent |
|---|---|---|
| Identité | | |
| Coordonnées | | |
| Vie professionnelle | | |

### Qui y accède

| Rôle | Ce qu'il voit | Pourquoi il en a besoin | Preuve (requête ou test) |
|---|---|---|---|
| | | | |

### Combien de temps

| Règle | Comment elle est appliquée | Preuve |
|---|---|---|
| R1 : suppression 5 ans après la fin du contrat | | |
| R2 : pas de restauration au-delà de 1 jour | | |
| R3 : pas de fichier sur le stage | | |

Délai réel entre l'exécution de la purge et la disparition définitive d'une donnée dans Snowflake, en tenant compte de Time Travel et de Fail-safe : ______ jours.

### Comment on le contrôle

| Question | Réponse | Preuve |
|---|---|---|
| Peut-on dire qui a lu ces données la semaine dernière ? | | |
| Sait-on quand une donnée est fausse ? | | |
| Que se passe-t-il si le rôle des outils est compromis ? | | |

### Limites connues

Ce que votre mise en œuvre ne couvre pas : deux ou trois lignes, sans détour.
