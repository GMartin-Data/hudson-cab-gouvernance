# Les accès — carte des droits et cahier de tests

- **Partie 1, jours 1 et 2** : la carte des droits, complétée au fur et à mesure que vous créez rôles et objets ;
- **Partie 2, jour 2** : le cahier de tests, « attendu » écrit avant les politiques, « obtenu » après.

---

## Partie 1 — Carte des droits

À compléter du jour 1 au jour 2. Dans Snowflake, faire une action demande d'être propriétaire de l'objet ou d'avoir reçu un privilège précis. Cette carte vous évite de chercher, à chaque erreur `Insufficient privileges`, quel droit manque et à qui.

Vérifiez chaque ligne dans la documentation des privilèges (ressources du jour 2), puis avec `SHOW GRANTS TO ROLE …`.

### Qui possède quoi

Le propriétaire d'un objet est le rôle qui l'a créé.

| Objet | Propriétaire |
|---|---|
| Tables de `RAW` et de `MARTS`, vues de `STAGING`, stage et format de fichier | `TRANSFORMER` (le rôle des outils, qui a exécuté les SQL fournis) |
| Schéma `GOUVERNANCE` | `GOUVERNANCE` (créé par `ACCOUNTADMIN`, propriété cédée par `GRANT OWNERSHIP … COPY CURRENT GRANTS`, `01_gouvernance.sql`) |
| Tags `SENSIBILITE`, `DONNEE_PERSONNELLE`, `DUREE_CONSERVATION` | `GOUVERNANCE` (créés par lui dans son schéma) |
| Politiques de masquage | `GOUVERNANCE` — jour 2 |
| Politique d'accès par ligne | `GOUVERNANCE` — jour 2 |
| Table `ACCES_DEPOT` | jour 2 |
| Table `QUALITE_RESULTATS` | `GOUVERNANCE` (créée par lui dans son schéma) |
| Vue `V_CATALOGUE` | jour 3 |

### Qui fait quoi, avec quel droit

| Action | Rôle qui la fait | Privilège nécessaire | Accordé par |
|---|---|---|---|
| Créer un tag | `GOUVERNANCE` | propriétaire du schéma `GOUVERNANCE` (la propriété vaut tous les droits sur le schéma, `CREATE TAG` compris) | `ACCOUNTADMIN` (cession de propriété) |
| Voir les schémas où attacher des règles, sans lire les données | `GOUVERNANCE` | `USAGE` sur la base `NYC_TAXI` et sur les schémas `RAW` et `MARTS` (aucun `SELECT`) | `ACCOUNTADMIN` |
| Poser un tag sur une colonne de `DIM_DRIVER` | `TRANSFORMER` | propriétaire de la table + `USAGE` sur le schéma `GOUVERNANCE` + `APPLY` sur le tag | `GOUVERNANCE` (propriétaire du tag) |
| Créer une politique de masquage | `GOUVERNANCE` | propriétaire du schéma `GOUVERNANCE` | `ACCOUNTADMIN` (cession de propriété) — jour 2 |
| Attacher une politique de masquage à un tag | `GOUVERNANCE` | `APPLY MASKING POLICY` sur le compte (la politique s'appliquera à des colonnes de tables qu'il ne possède pas) | `ACCOUNTADMIN` — jour 2 |
| Ajouter une politique d'accès par ligne à une table | `GOUVERNANCE` | `APPLY ROW ACCESS POLICY` sur le compte | `ACCOUNTADMIN` — jour 2 |
| Écrire une ligne dans `QUALITE_RESULTATS` | `TRANSFORMER` | `USAGE` sur le schéma `GOUVERNANCE` + `INSERT` (et `SELECT` pour relire) sur la table | `GOUVERNANCE` (propriétaire de la table) |
| Créer la vue du catalogue dans `GOUVERNANCE` | `TRANSFORMER` | `CREATE VIEW` sur le schéma `GOUVERNANCE` | `GOUVERNANCE` — jour 3 |
| Lire `DIM_DRIVER`, `MART_DRIVER_MONTHLY` et `DIM_DEPOT` | `RH_PAIE`, `RESP_DEPOT_QUEENS`, `RESP_DEPOT_BRONX`, `ANALYSTE` (`TRANSFORMER` lit en tant que propriétaire) | `USAGE` sur la base `NYC_TAXI` et le schéma `MARTS` + `SELECT` sur chaque table | `ACCOUNTADMIN` (`02_roles_metier.sql`) ; `SHOW GRANTS` affiche `TRANSFORMER`, propriétaire des tables, dans `granted_by` : Snowflake enregistre le propriétaire quand l'administrateur agit par `MANAGE GRANTS` |
| Lire toute table de `MARTS`, y compris une table recréée demain | `ANALYSTE` | `SELECT ON ALL TABLES` + `SELECT ON FUTURE TABLES IN SCHEMA MARTS` | `ACCOUNTADMIN`, propriétaire du schéma `MARTS` (un droit sur les objets futurs demande la propriété du schéma ou `MANAGE GRANTS`) |
| Lire la vue du catalogue `V_CATALOGUE` (jour 3), même recréée | les quatre rôles métier | `USAGE` sur le schéma `GOUVERNANCE` + `SELECT ON FUTURE VIEWS IN SCHEMA GOUVERNANCE` (vues seulement : `ACCES_DEPOT` et `QUALITE_RESULTATS` restent fermées) | `ACCOUNTADMIN` (`02_roles_metier.sql`) |
| Endosser un rôle métier pour le tester (`USE ROLE`) | l'utilisateur qui déroule le cahier de tests | `GRANT ROLE … TO USER` | `ACCOUNTADMIN` (`02_roles_metier.sql`) |
| Exécuter une requête | chaque rôle | `USAGE` sur le warehouse `NYC_TAXI_WH` | `ACCOUNTADMIN` (`00_installation.sql`, `01_gouvernance.sql`, `02_roles_metier.sql`) |

### Ce que cette carte permet à un rôle de défaire

Pour chaque rôle qui peut poser ou retirer un tag, ou détacher une politique : que pourrait-il démasquer ? Est-ce acceptable, et qui le surveille ?

- **`SYSADMIN`, donc `ACCOUNTADMIN`, hérite de tous les rôles du brief** : `TRANSFORMER` (lit tout en clair), `GOUVERNANCE` (réécrit tags et politiques) et les quatre rôles métier (`00_installation.sql`, `01_gouvernance.sql`, `02_roles_metier.sql` : `GRANT ROLE … TO ROLE SYSADMIN`). C'est la hiérarchie standard de Snowflake, qui permet à l'administration de gérer ces rôles. Le prix : un utilisateur `SYSADMIN` peut défaire la protection en deux `USE ROLE` (`GOUVERNANCE` pour détacher une politique, `TRANSFORMER` pour lire). Accepté parce que les politiques du jour 2 regardent le rôle **actif** (`CURRENT_ROLE()`) et non l'héritage : tant qu'il reste `SYSADMIN`, il lit `RAW` avec les colonnes personnelles masquées et ne voit aucune ligne de `DIM_DRIVER`. Qui surveille : l'audit du jour 3 (`06_audit.sql`, `ACCESS_HISTORY` joint à `QUERY_HISTORY`) nomme le rôle qui a lu.
- **Aucun rôle métier n'hérite de `TRANSFORMER` ni de `GOUVERNANCE`**, et `GOUVERNANCE` n'hérite de personne : vérifié par `verif/01` (contrôle 15) et `verif/03` (« n'héritent d'aucun rôle »). Un héritage ouvrirait les données sans qu'aucun `SELECT` direct n'apparaisse dans `SHOW GRANTS`.
- **Rôles secondaires** : les politiques lisent le rôle principal, mais les droits de lecture s'additionnent entre tous les rôles actifs. Les utilisateurs qui déroulent le cahier de tests ont `DEFAULT_SECONDARY_ROLES = ()`, et chaque script commence par `USE SECONDARY ROLES NONE`. Sans cela, un test « refusé » renvoie des lignes.

---

## Partie 2 — Cahier de tests

Décidez d'abord à quoi ressemble une valeur masquée pour chaque type de colonne (texte, date) et notez-le ici : ______. Puis remplissez en deux temps : la colonne « attendu » **avant** d'écrire les politiques, à partir de la matrice du contrat ; la colonne « obtenu » après, en exécutant la requête avec le rôle indiqué (`USE ROLE ...`).

Un test est vert quand « obtenu » est identique à « attendu ». Un accès refusé (`Object does not exist or not authorized`) est un résultat comme un autre : écrivez-le.

### Lignes visibles

| N° | Rôle | Requête | Attendu | Obtenu | Vert ? |
|---|---|---|---|---|---|
| 1 | `RH_PAIE` | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER` | | | |
| 2 | `RESP_DEPOT_QUEENS` | la même | | | |
| 3 | `RESP_DEPOT_QUEENS` | `SELECT DISTINCT depot FROM NYC_TAXI.MARTS.DIM_DRIVER` | | | |
| 4 | `RESP_DEPOT_BRONX` | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY` | | | |
| 5 | `ANALYSTE` | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER` | | | |
| 6 | `GOUVERNANCE` | la même | | | |
| 7 | `ACCOUNTADMIN` | la même | | | |
| 8 | `RH_PAIE` | `SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS` | | | |
| 9 | `ANALYSTE` | `SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS` | | | |
| 9 bis | `ACCOUNTADMIN` | `SELECT first_name, email FROM NYC_TAXI.RAW.DRIVERS LIMIT 3` | | | |

### Valeurs visibles

Pour le chauffeur `D0003`, la valeur que chaque rôle doit lire dans chaque colonne (ou « colonne absente », ou « ligne invisible »).

| Colonne | `RH_PAIE` | `RESP_DEPOT_QUEENS` | `RESP_DEPOT_BRONX` | `ANALYSTE` |
|---|---|---|---|---|
| nom et prénom | | | | |
| e-mail | | | | |
| téléphone | | | | |
| date de naissance | | | | |
| numéro de licence | | | | |
| `driver_name` dans `MART_DRIVER_MONTHLY` | | | | |

### Le pipeline fonctionne toujours

| N° | Vérification | Attendu | Obtenu | Vert ? |
|---|---|---|---|---|
| 10 | Avec le rôle des outils, après avoir relancé les fichiers SQL : nombre de lignes de `DIM_DRIVER` | | | |
| 11 | Avec `RH_PAIE` : l'e-mail de `D0003` est toujours une vraie adresse | | | |
| 12 | Les politiques sont toujours attachées après la relance (requête de la section 7 du contrat) | | | |

Ajoutez vos propres tests : un cahier qui ne contient que des tests verts dès le premier essai n'a probablement pas cherché les cas limites.
