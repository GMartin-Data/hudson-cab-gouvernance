-- =====================================================================
-- 01_verif_gouvernance.sql — le test de 01_gouvernance.sql, écrit avant lui (jour 1, étape 10).
-- Ce qui doit être vrai : le rôle GOUVERNANCE existe et possède le schéma GOUVERNANCE ; il a les droits
-- pour écrire des règles (APPLY ... POLICY sur le compte, USAGE sur RAW et MARTS) mais aucun SELECT sur
-- les données ; les trois tags du contrat existent avec leurs valeurs permises ; QUALITE_RESULTATS a les
-- colonnes du contrat ; le rôle des outils (TRANSFORMER) a reçu ce dont il aura besoin aux jours 2 et 3.
-- Rôle : ACCOUNTADMIN, parce qu'il s'agit de lire des DROITS (SHOW GRANTS), pas des données.
-- Rejouable. Avant 01_gouvernance.sql : erreur « role GOUVERNANCE does not exist » (test rouge).
-- C'est bon quand : toutes les lignes affichent statut = OK.
-- Le pipe ->> enchaîne les SHOW et passe leurs résultats à la requête finale : $1 est le résultat juste
-- avant, $2 celui d'avant, etc. Les colonnes d'un SHOW se lisent en minuscules entre guillemets doubles.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE NYC_TAXI_WH;

SHOW ROLES LIKE 'GOUVERNANCE'                                        -- $5
  ->> SHOW SCHEMAS LIKE 'GOUVERNANCE' IN DATABASE NYC_TAXI           -- $4
  ->> SHOW GRANTS TO ROLE GOUVERNANCE                                -- $3
  ->> SHOW TAGS IN SCHEMA NYC_TAXI.GOUVERNANCE                       -- $2
  ->> SHOW GRANTS TO ROLE TRANSFORMER                                -- $1
  ->> WITH attendu AS (
        SELECT 'Rôle GOUVERNANCE : existe et est donné à au moins un utilisateur' AS verification, 1 AS attendu,
               (SELECT COUNT(*) FROM $5 WHERE "assigned_to_users" >= 1) AS obtenu
        UNION ALL
        SELECT 'Schéma NYC_TAXI.GOUVERNANCE : appartient au rôle GOUVERNANCE', 1,
               (SELECT COUNT(*) FROM $4 WHERE "owner" = 'GOUVERNANCE')
        UNION ALL
        SELECT 'GOUVERNANCE : USAGE sur la base, le warehouse, RAW et MARTS (4 droits)', 4,
               (SELECT COUNT(*) FROM $3
                WHERE "privilege" = 'USAGE'
                  AND (("granted_on" = 'DATABASE'  AND "name" = 'NYC_TAXI')
                    OR ("granted_on" = 'WAREHOUSE' AND "name" = 'NYC_TAXI_WH')
                    OR ("granted_on" = 'SCHEMA'    AND "name" IN ('NYC_TAXI.RAW', 'NYC_TAXI.MARTS'))))
        UNION ALL
        SELECT 'GOUVERNANCE : APPLY MASKING POLICY et APPLY ROW ACCESS POLICY sur le compte (2 droits)', 2,
               (SELECT COUNT(*) FROM $3
                WHERE "granted_on" = 'ACCOUNT'
                  AND "privilege" IN ('APPLY MASKING POLICY', 'APPLY ROW ACCESS POLICY'))
        UNION ALL
        SELECT 'GOUVERNANCE : aucun SELECT sur une table ou une vue hors de son schéma (ne lit pas les données)', 0,
               (SELECT COUNT(*) FROM $3
                WHERE "privilege" = 'SELECT'
                  AND "name" NOT LIKE 'NYC_TAXI.GOUVERNANCE.%')
        UNION ALL
        SELECT 'Tags : SENSIBILITE, DONNEE_PERSONNELLE, DUREE_CONSERVATION dans NYC_TAXI.GOUVERNANCE (3 tags)', 3,
               (SELECT COUNT(*) FROM $2
                WHERE "name" IN ('SENSIBILITE', 'DONNEE_PERSONNELLE', 'DUREE_CONSERVATION'))
        UNION ALL
        SELECT 'Tag SENSIBILITE : valeurs permises public, interne, confidentiel', 1,
               (SELECT COUNT(*) FROM $2
                WHERE "name" = 'SENSIBILITE'
                  AND "allowed_values" LIKE '%public%'
                  AND "allowed_values" LIKE '%interne%'
                  AND "allowed_values" LIKE '%confidentiel%')
        UNION ALL
        SELECT 'Tag DONNEE_PERSONNELLE : les six valeurs permises du contrat', 1,
               (SELECT COUNT(*) FROM $2
                WHERE "name" = 'DONNEE_PERSONNELLE'
                  AND "allowed_values" LIKE '%nom%'
                  AND "allowed_values" LIKE '%email%'
                  AND "allowed_values" LIKE '%telephone%'
                  AND "allowed_values" LIKE '%date_naissance%'
                  AND "allowed_values" LIKE '%identifiant_officiel%'
                  AND "allowed_values" LIKE '%identifiant_interne%')
        UNION ALL
        SELECT 'Tag DUREE_CONSERVATION : texte libre (aucune liste de valeurs)', 1,
               (SELECT COUNT(*) FROM $2
                WHERE "name" = 'DUREE_CONSERVATION' AND "allowed_values" IS NULL)
        UNION ALL
        SELECT 'Table QUALITE_RESULTATS : appartient à GOUVERNANCE', 1,
               (SELECT COUNT(*) FROM NYC_TAXI.INFORMATION_SCHEMA.TABLES
                WHERE table_schema = 'GOUVERNANCE' AND table_name = 'QUALITE_RESULTATS'
                  AND table_owner = 'GOUVERNANCE')
        UNION ALL
        SELECT 'Table QUALITE_RESULTATS : colonnes regle, mesure_le, nb_anomalies, seuil, statut (5 colonnes)', 5,
               (SELECT COUNT(*) FROM NYC_TAXI.INFORMATION_SCHEMA.COLUMNS
                WHERE table_schema = 'GOUVERNANCE' AND table_name = 'QUALITE_RESULTATS'
                  AND LOWER(column_name) IN ('regle', 'mesure_le', 'nb_anomalies', 'seuil', 'statut'))
        UNION ALL
        SELECT 'TRANSFORMER : USAGE et CREATE VIEW sur le schéma GOUVERNANCE (2 droits)', 2,
               (SELECT COUNT(*) FROM $1
                WHERE "granted_on" = 'SCHEMA' AND "name" = 'NYC_TAXI.GOUVERNANCE'
                  AND "privilege" IN ('USAGE', 'CREATE VIEW'))
        UNION ALL
        SELECT 'TRANSFORMER : APPLY sur chacun des trois tags (3 droits)', 3,
               (SELECT COUNT(*) FROM $1
                WHERE "granted_on" = 'TAG' AND "privilege" = 'APPLY'
                  AND "name" IN ('NYC_TAXI.GOUVERNANCE.SENSIBILITE',
                                 'NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE',
                                 'NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION'))
        UNION ALL
        SELECT 'TRANSFORMER : INSERT et SELECT sur QUALITE_RESULTATS (2 droits)', 2,
               (SELECT COUNT(*) FROM $1
                WHERE "granted_on" = 'TABLE' AND "name" = 'NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS'
                  AND "privilege" IN ('INSERT', 'SELECT'))
      )
      SELECT verification, attendu, obtenu,
             IFF(obtenu = attendu, 'OK', 'KO') AS statut
      FROM attendu
      ORDER BY statut, verification;   -- 'KO' < 'OK' : les échecs d'abord
