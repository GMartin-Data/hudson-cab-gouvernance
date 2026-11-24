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
| Politiques de masquage `MASK_TEXTE`, `MASK_DATE` | `GOUVERNANCE` (créées par lui dans son schéma, `03_masquage.sql`, attachées au tag `DONNEE_PERSONNELLE`) |
| Politique d'accès par ligne `RAP_DEPOT` | `GOUVERNANCE` (`04_acces_depot.sql`, attachée à `DIM_DRIVER` et `MART_DRIVER_MONTHLY` sur `depot`) |
| Table `ACCES_DEPOT` | `GOUVERNANCE` (`04_acces_depot.sql`) ; aucun rôle métier ne la lit : la politique la consulte avec les droits de son propriétaire |
| Table `QUALITE_RESULTATS` | `GOUVERNANCE` (créée par lui dans son schéma) |
| Vue `V_CATALOGUE` | jour 3 |

### Qui fait quoi, avec quel droit

| Action | Rôle qui la fait | Privilège nécessaire | Accordé par |
|---|---|---|---|
| Créer un tag | `GOUVERNANCE` | propriétaire du schéma `GOUVERNANCE` (la propriété vaut tous les droits sur le schéma, `CREATE TAG` compris) | `ACCOUNTADMIN` (cession de propriété) |
| Voir les schémas où attacher des règles, sans lire les données | `GOUVERNANCE` | `USAGE` sur la base `NYC_TAXI` et sur les schémas `RAW` et `MARTS` (aucun `SELECT`) | `ACCOUNTADMIN` |
| Poser un tag sur une colonne de `DIM_DRIVER` | `TRANSFORMER` | propriétaire de la table + `USAGE` sur le schéma `GOUVERNANCE` + `APPLY` sur le tag | `GOUVERNANCE` (propriétaire du tag) |
| Créer une politique de masquage ou d'accès par ligne, la modifier (`SET BODY`) | `GOUVERNANCE` | propriétaire du schéma `GOUVERNANCE` | `ACCOUNTADMIN` (cession de propriété, `01_gouvernance.sql`) |
| Attacher une politique de masquage à un tag | `GOUVERNANCE` | `APPLY MASKING POLICY` sur le compte (la politique s'applique à des colonnes de tables qu'il ne possède pas) | `ACCOUNTADMIN` (`01_gouvernance.sql`) — fait dans `03_masquage.sql` |
| Ajouter une politique d'accès par ligne à une table qu'il ne possède pas | `GOUVERNANCE` | `APPLY ROW ACCESS POLICY` sur le compte | `ACCOUNTADMIN` (`01_gouvernance.sql`) — fait dans `04_acces_depot.sql` |
| Voir où une politique est attachée (`POLICY_REFERENCES`) | `GOUVERNANCE` | propriétaire de la politique (`POLICY_NAME =>`) ou `APPLY … POLICY` sur le compte (`REF_ENTITY_NAME =>` sur une table qu'il ne possède pas, vérifié) | `ACCOUNTADMIN` (`01_gouvernance.sql`) |
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

La colonne « attendu » a été écrite **avant** les politiques (2026-11-24, à partir de la matrice du contrat et des volumes relevés avec le rôle des outils) ; la colonne « obtenu » après, en exécutant la requête avec le rôle indiqué (`USE SECONDARY ROLES NONE; USE ROLE …; USE WAREHOUSE NYC_TAXI_WH;`). La version automatisée et rejouable de ce cahier est `snowflake/verif/04_verif_acces.sql` : une section par rôle, un refus attendu est attrapé dans un bloc `EXECUTE IMMEDIATE`.

Un test est vert quand « obtenu » est identique à « attendu ». Un accès refusé (`Object does not exist or not authorized`) est un résultat comme un autre : écrivez-le.

#### À quoi ressemble une valeur masquée

| Type | Rôle qui ne doit pas voir en clair | Valeur lue | Pourquoi cette forme |
|---|---|---|---|
| texte (nom, prénom, téléphone, licence, `driver_name`) | selon la matrice | `*****` | une constante, qui remplace aussi les `NULL` : on ne sait pas qui n'a pas de téléphone |
| e-mail | selon la matrice | `*****@<domaine>` ; `*****` si la valeur ne contient pas de `@` | la partie locale identifie, le domaine non ; le domaine reste utile (adresse pro ou perso). Sept adresses du fichier n'ont pas de `@` (règle `email_valide`, jour 3) : sans ce cas, « garder le domaine » les aurait laissées en clair |
| date (`birth_date`) | `ANALYSTE` | le 1er janvier de l'année réelle (`DATE_TRUNC('YEAR')`) | l'analyse n'a besoin que de l'année ; une date masquée reste une date |
| date (`birth_date`) | tout autre rôle | `NULL` | personne d'autre n'en a l'usage ; une fausse date entrerait dans un calcul d'âge sans erreur |
| `driver_id` (`identifiant_interne`) | aucun rôle métier : le contrat le veut visible ; masqué (`*****`) pour les rôles hors de la matrice | en clair pour `RH_PAIE`, `RESP_DEPOT_*`, `ANALYSTE`, `TRANSFORMER` | compter et joindre sans nommer ; `ACCOUNTADMIN` ne voit rien, pas même l'identifiant |

Les politiques lisent le **rôle actif** (`CURRENT_ROLE()`), pas la hiérarchie ni les rôles secondaires (`IS_ROLE_IN_SESSION` aurait ouvert tout en clair à `SYSADMIN`, qui hérite de `RH_PAIE`). Même choix pour la politique de lignes.

### Lignes visibles

| N° | Rôle | Requête | Attendu | Obtenu | Vert ? |
|---|---|---|---|---|---|
| 1 | `RH_PAIE` | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER` | 400 | 400 | oui |
| 2 | `RESP_DEPOT_QUEENS` | la même | 161 | 161 | oui |
| 3 | `RESP_DEPOT_QUEENS` | `SELECT DISTINCT depot FROM NYC_TAXI.MARTS.DIM_DRIVER` | une seule ligne : `Queens` | 1 dépôt distinct, 161 lignes `Queens` | oui |
| 4 | `RESP_DEPOT_BRONX` | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY` | 290 | 290 | oui |
| 4 bis | `RESP_DEPOT_BRONX` | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER` | 122 | 122 | oui |
| 5 | `ANALYSTE` | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER` | 400 | 400 | oui |
| 6 | `GOUVERNANCE` | la même | refusé (`USAGE` sur le schéma, aucun `SELECT`) | `Object 'NYC_TAXI.MARTS.DIM_DRIVER' does not exist or not authorized` | oui |
| 7 | `ACCOUNTADMIN` | la même | 0 ligne, sans erreur : il hérite du droit de lire, mais la politique de lignes ne le connaît pas | 0, sans erreur | oui |
| 7 bis | tout rôle métier | `SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT` | 3 (référentiel sans filtre) | 3 pour chaque rôle, `ACCOUNTADMIN` compris | oui |
| 8 | `RH_PAIE` | `SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS` | refusé | refusé | oui |
| 9 | `ANALYSTE` | `SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS` | refusé | refusé (idem `RESP_DEPOT_QUEENS` sur `RAW.DRIVERS`, `RESP_DEPOT_BRONX` sur `STAGING`, `GOUVERNANCE` sur `RAW`) | oui |
| 9 bis | `ACCOUNTADMIN` | `SELECT first_name, email FROM NYC_TAXI.RAW.DRIVERS LIMIT 3` | 3 lignes (pas de politique de lignes sur `RAW`), `*****` et `*****@<domaine>` | mesuré sur les 400 lignes : nom, prénom, licence, téléphone et `driver_id` tous `*****`, e-mails `*****…`, dates `NULL` | oui |
| 9 ter | `RESP_DEPOT_QUEENS` | `SELECT row_count FROM NYC_TAXI.INFORMATION_SCHEMA.TABLES WHERE table_name = 'DIM_DRIVER'` | 400 : le compte du catalogue est physique, la politique de lignes ne le filtre pas (limite connue, sans donnée personnelle) | 400, politique active ; limite confirmée | oui |

Obtenu le 2026-11-24 par `snowflake/verif/04_verif_acces.sql` : 79 contrôles OK, 0 KO, après `03_masquage.sql` et `04_acces_depot.sql`, puis à nouveau après leur second passage.

### Valeurs visibles

Pour le chauffeur `D0003` (dépôt de Queens), la **forme** de la valeur que chaque rôle doit lire dans chaque colonne. Les valeurs réelles du fichier ne sont pas recopiées ici : le dépôt est public.

| Colonne | `RH_PAIE` | `RESP_DEPOT_QUEENS` | `RESP_DEPOT_BRONX` | `ANALYSTE` |
|---|---|---|---|---|
| `driver_id` | `D0003` | `D0003` | ligne invisible | `D0003` |
| nom et prénom | en clair | en clair | ligne invisible | `*****` |
| e-mail | en clair | `*****@<domaine>` | ligne invisible | `*****@<domaine>` |
| téléphone | en clair | en clair | ligne invisible | `*****` |
| date de naissance | en clair | `NULL` | ligne invisible | 1er janvier de l'année réelle |
| numéro de licence | en clair | `*****` | ligne invisible | `*****` |
| `driver_name` dans `MART_DRIVER_MONTHLY` | en clair | en clair | ligne invisible | `*****` |

Pour `TRANSFORMER` : tout en clair, toutes les lignes, dans `RAW` comme dans `MARTS` ; c'est lui qui reconstruit `MARTS` et il recopierait ce qu'il voit. Pour `ACCOUNTADMIN` et `SYSADMIN` : aucune ligne de `DIM_DRIVER` ni de `MART_DRIVER_MONTHLY` ; dans `RAW.DRIVERS`, toutes les lignes mais rien en clair, `driver_id` compris.

Obtenu (2026-11-24, `verif/04`) : conforme pour les quatre rôles métier, `TRANSFORMER` et `ACCOUNTADMIN`. Mesuré sur toute la table plutôt que sur `D0003` seul : `RH_PAIE` lit 393 e-mails avec `@` et 12 téléphones `NULL` (les valeurs du fichier) ; `RESP_DEPOT_QUEENS` lit `D0003`, nom, prénom et téléphone en clair, 161 e-mails `*****…`, 161 licences `*****`, 161 dates `NULL` ; `RESP_DEPOT_BRONX` ne voit pas `D0003` ; `ANALYSTE` lit `D0003`, 400 `*****` sur nom, prénom, licence et téléphone, 400 e-mails `*****…` dont 393 avec leur domaine, 400 dates au 1er janvier sur 50 années distinctes, 914 `driver_name` `*****` dans le mart.

### Le pipeline fonctionne toujours

| N° | Vérification | Attendu | Obtenu | Vert ? |
|---|---|---|---|---|
| 10 | Avec le rôle des outils, après avoir relancé les fichiers SQL : nombre de lignes de `DIM_DRIVER` et de `MART_DRIVER_MONTHLY` | 400 et 914 ; `driver_name` `NULL` sur 25 lignes seulement (les services sans chauffeur connu, comme avant) | 400 et 914 ; 25 `NULL`, aucun `*****` | oui |
| 11 | Avec `RH_PAIE` : l'e-mail de `D0003` est toujours une vraie adresse | en clair, contient `@`, ne commence pas par `*****` | 393 e-mails avec `@`, aucun masque (D0003 compris) | oui |
| 12 | Les politiques sont toujours attachées après la relance (requête de la section 7 du contrat) | `DIM_DRIVER` : 7 masquages via le tag + `RAP_DEPOT` sur `depot` ; `MART_DRIVER_MONTHLY` : 2 + 1 | 7 + 1 et 2 + 1, `ACTIVE` ; 19 références au total sur les quatre tables RH | oui |
| 13 | `snowflake/verif/02_verif_catalogue.sql` et `04_verif_acces.sql` après la relance | aucun KO | 11 OK et 79 OK, 0 KO (2026-11-24, relance de `marts/dim_depot.sql`, `dim_driver.sql`, `mart_driver_monthly.sql` avec `TRANSFORMER`) | oui |

Ajoutez vos propres tests : un cahier qui ne contient que des tests verts dès le premier essai n'a probablement pas cherché les cas limites.
