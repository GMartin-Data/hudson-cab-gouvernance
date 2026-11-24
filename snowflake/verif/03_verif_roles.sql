-- =====================================================================
-- 03_verif_roles.sql — le test de 02_roles_metier.sql, écrit avant lui (jour 2, étape 2).
-- Ce qui doit être vrai : les quatre rôles métier du contrat existent et sont donnés à un utilisateur ; chacun
-- a le chemin jusqu'aux tables (USAGE sur le warehouse, la base, le schéma MARTS) ; RH_PAIE et les deux
-- responsables de dépôt lisent DIM_DRIVER, MART_DRIVER_MONTHLY et DIM_DEPOT ; ANALYSTE lit tout MARTS, tables
-- futures comprises ; tous lisent les vues futures de GOUVERNANCE (V_CATALOGUE, jour 3) ; et rien d'autre :
-- aucun droit sur RAW ni STAGING, aucune écriture, aucun rôle hérité, aucun droit sur le compte.
-- Rôle : ACCOUNTADMIN, parce qu'il s'agit de lire des DROITS (SHOW GRANTS), pas des données.
-- Rejouable. Avant 02_roles_metier.sql : erreur « Role 'RH_PAIE' does not exist » (test rouge).
-- C'est bon quand : toutes les lignes affichent statut = OK.
-- Ce que chaque rôle VOIT (lignes, valeurs masquées) est testé à part, dans 04_verif_acces.sql.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE NYC_TAXI_WH;

SHOW GRANTS TO ROLE SYSADMIN                                        -- $8
  ->> SHOW ROLES                                                    -- $7
  ->> SHOW GRANTS TO ROLE RH_PAIE                                   -- $6
  ->> SHOW GRANTS TO ROLE RESP_DEPOT_QUEENS                         -- $5
  ->> SHOW GRANTS TO ROLE RESP_DEPOT_BRONX                          -- $4
  ->> SHOW GRANTS TO ROLE ANALYSTE                                  -- $3
  ->> SHOW FUTURE GRANTS IN SCHEMA NYC_TAXI.MARTS                   -- $2
  ->> SHOW FUTURE GRANTS IN SCHEMA NYC_TAXI.GOUVERNANCE             -- $1
  ->> WITH droits AS (                                              -- les droits directs des quatre rôles, en une seule table
        SELECT "grantee_name" AS role_name, "privilege" AS privilege, "granted_on" AS granted_on, "name" AS name FROM $6
        UNION ALL
        SELECT "grantee_name", "privilege", "granted_on", "name" FROM $5
        UNION ALL
        SELECT "grantee_name", "privilege", "granted_on", "name" FROM $4
        UNION ALL
        SELECT "grantee_name", "privilege", "granted_on", "name" FROM $3
      ),
      attendu AS (
        SELECT 'Rôles métier : les 4 existent et chacun est donné à au moins un utilisateur' AS verification, 4 AS attendu,
               (SELECT COUNT(*) FROM $7
                WHERE "name" IN ('RH_PAIE', 'RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX', 'ANALYSTE')
                  AND "assigned_to_users" >= 1) AS obtenu
        UNION ALL
        -- Hiérarchie standard, comme TRANSFORMER et GOUVERNANCE : l'administration peut gérer ces rôles.
        -- Les politiques lisent CURRENT_ROLE() : SYSADMIN n'en voit pas plus pour autant (docs/ACCES.md).
        SELECT 'Rôles métier : chacun est donné à SYSADMIN (hiérarchie standard)', 4,
               (SELECT COUNT(*) FROM $8
                WHERE "granted_on" = 'ROLE' AND "privilege" = 'USAGE'
                  AND "name" IN ('RH_PAIE', 'RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX', 'ANALYSTE'))
        UNION ALL
        SELECT 'Chaque rôle métier : USAGE sur le warehouse, la base et le schéma MARTS (12 droits)', 12,
               (SELECT COUNT(*) FROM droits
                WHERE privilege = 'USAGE'
                  AND ((granted_on = 'WAREHOUSE' AND name = 'NYC_TAXI_WH')
                    OR (granted_on = 'DATABASE'  AND name = 'NYC_TAXI')
                    OR (granted_on = 'SCHEMA'    AND name = 'NYC_TAXI.MARTS')))
        UNION ALL
        SELECT 'RH_PAIE, RESP_DEPOT_QUEENS, RESP_DEPOT_BRONX : SELECT sur DIM_DRIVER, MART_DRIVER_MONTHLY, DIM_DEPOT (9 droits)', 9,
               (SELECT COUNT(*) FROM droits
                WHERE role_name IN ('RH_PAIE', 'RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX')
                  AND privilege = 'SELECT' AND granted_on = 'TABLE'
                  AND name IN ('NYC_TAXI.MARTS.DIM_DRIVER', 'NYC_TAXI.MARTS.MART_DRIVER_MONTHLY', 'NYC_TAXI.MARTS.DIM_DEPOT'))
        UNION ALL
        SELECT 'ANALYSTE : SELECT sur les 3 tables actuelles de MARTS', 3,
               (SELECT COUNT(*) FROM droits
                WHERE role_name = 'ANALYSTE' AND privilege = 'SELECT' AND granted_on = 'TABLE'
                  AND name LIKE 'NYC_TAXI.MARTS.%')
        UNION ALL
        -- Sans ce droit, l'analyste perdrait toute table que le pipeline recréerait.
        SELECT 'ANALYSTE : SELECT sur les tables futures de MARTS', 1,
               (SELECT COUNT(*) FROM $2
                WHERE "grantee_name" = 'ANALYSTE' AND "privilege" = 'SELECT' AND "grant_on" = 'TABLE')
        UNION ALL
        SELECT 'Chaque rôle métier : USAGE sur le schéma GOUVERNANCE (4 droits)', 4,
               (SELECT COUNT(*) FROM droits
                WHERE privilege = 'USAGE' AND granted_on = 'SCHEMA' AND name = 'NYC_TAXI.GOUVERNANCE')
        UNION ALL
        SELECT 'Chaque rôle métier : SELECT sur les vues futures de GOUVERNANCE, pour V_CATALOGUE au jour 3 (4 droits)', 4,
               (SELECT COUNT(*) FROM $1
                WHERE "grantee_name" IN ('RH_PAIE', 'RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX', 'ANALYSTE')
                  AND "privilege" = 'SELECT' AND "grant_on" = 'VIEW')
        UNION ALL
        -- Le contrat : « Personne d'autre que le rôle des outils ne lit RAW ni STAGING. »
        SELECT 'Rôles métier : aucun droit sur RAW ni STAGING', 0,
               (SELECT COUNT(*) FROM droits
                WHERE name LIKE 'NYC_TAXI.RAW%' OR name LIKE 'NYC_TAXI.STAGING%')
        UNION ALL
        -- ACCES_DEPOT et QUALITE_RESULTATS restent fermées aux rôles métier (les vues de GOUVERNANCE, elles, sont permises).
        SELECT 'Rôles métier : aucun SELECT sur une table hors de MARTS', 0,
               (SELECT COUNT(*) FROM droits
                WHERE granted_on = 'TABLE' AND name NOT LIKE 'NYC_TAXI.MARTS.%')
        UNION ALL
        SELECT 'Rôles métier : lecture seule (aucune écriture, création, propriété ni APPLY)', 0,
               (SELECT COUNT(*) FROM droits
                WHERE privilege IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'OWNERSHIP')
                   OR privilege LIKE 'CREATE%' OR privilege LIKE 'APPLY%')
        UNION ALL
        -- Un rôle hérité ouvrirait tout sans qu'aucun SELECT direct n'apparaisse (même contrôle que GOUVERNANCE, verif/01).
        SELECT 'Rôles métier : n''héritent d''aucun rôle (TRANSFORMER et GOUVERNANCE hors de portée)', 0,
               (SELECT COUNT(*) FROM droits WHERE granted_on = 'ROLE')
        UNION ALL
        SELECT 'Rôles métier : aucun droit sur le compte', 0,
               (SELECT COUNT(*) FROM droits WHERE granted_on = 'ACCOUNT')
      )
      SELECT verification, attendu, obtenu,
             IFF(obtenu = attendu, 'OK', 'KO') AS statut
      FROM attendu
      ORDER BY statut, verification;   -- 'KO' < 'OK' : les échecs d'abord
