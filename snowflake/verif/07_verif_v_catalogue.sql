-- =====================================================================
-- 07_verif_v_catalogue.sql — le test de la vue GOUVERNANCE.V_CATALOGUE, écrit avant elle (jour 3, étape 5).
-- Ce qui doit être vrai : la vue rend une ligne par colonne des trois tables de MARTS que les rôles métier lisent
-- (DIM_DRIVER, MART_DRIVER_MONTHLY, DIM_DEPOT), avec sa description, son type et ses tags ; et chaque rôle métier
-- y lit la même chose que le rôle des outils. Ce dernier point n'est pas acquis : la vue s'appuie sur
-- INFORMATION_SCHEMA, qui ne montre que ce que le rôle qui interroge a le droit de voir.
-- Rôles : une section par rôle (le rôle des outils, puis les quatre rôles métier).
-- Les DROITS sur la vue (SELECT nommé, aucune autre vue ouverte) sont testés dans 03_verif_roles.sql.
-- Rejouable. Avant v_catalogue.sql : erreur « Object 'NYC_TAXI.GOUVERNANCE.V_CATALOGUE' does not exist or not
-- authorized » dès la première section (test rouge).
-- C'est bon quand : aucun KO dans la sortie, aucune erreur :
--   snow sql -c hudson_cab -f snowflake/verif/07_verif_v_catalogue.sql | grep -c ' KO '   → 0
-- Constantes : 24 colonnes (12 + 8 + 4) et 9 colonnes personnelles, relevées avec TRANSFORMER le 2026-11-28 ; elles
-- changent si une colonne est ajoutée à une table de MARTS, pas avec les données.
-- =====================================================================

-- ===================================================================== TRANSFORMER : le propriétaire de la vue et des tables, la référence
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

WITH v AS (SELECT * FROM NYC_TAXI.GOUVERNANCE.V_CATALOGUE),
attendu AS (
    SELECT 'TRANSFORMER : V_CATALOGUE, 24 colonnes cataloguées' AS verification, 24 AS attendu, (SELECT COUNT(*) FROM v) AS obtenu
    UNION ALL SELECT 'TRANSFORMER : les 3 tables de MARTS y sont', 3, (SELECT COUNT(DISTINCT table_name) FROM v)
    UNION ALL SELECT 'TRANSFORMER : DIM_DRIVER 12 colonnes, MART_DRIVER_MONTHLY 8, DIM_DEPOT 4', 3,
              (SELECT COUNT(*) FROM (SELECT table_name, COUNT(*) AS n FROM v GROUP BY table_name)
               WHERE (table_name, n) IN (('DIM_DRIVER', 12), ('MART_DRIVER_MONTHLY', 8), ('DIM_DEPOT', 4)))
    UNION ALL SELECT 'TRANSFORMER : le tag DONNEE_PERSONNELLE se lit sur 9 colonnes (7 de DIM_DRIVER, 2 du mart)', 9,
              (SELECT COUNT(donnee_personnelle) FROM v)
    UNION ALL SELECT 'TRANSFORMER : SENSIBILITE et DUREE_CONSERVATION se lisent sur les 24 colonnes', 24,
              (SELECT COUNT(*) FROM v WHERE sensibilite IS NOT NULL AND duree_conservation IS NOT NULL)
    -- Ce que la vue doit au catalogue du jour 1 : une ligne par colonne, pas de doublon, pas de colonne oubliée
    UNION ALL SELECT 'TRANSFORMER : une seule ligne par colonne (aucun doublon)', 24,
              (SELECT COUNT(DISTINCT table_name, column_name) FROM v)
    UNION ALL SELECT 'TRANSFORMER : autant de lignes que de colonnes dans INFORMATION_SCHEMA pour ces 3 tables', (SELECT COUNT(*) FROM v),
              (SELECT COUNT(*) FROM NYC_TAXI.INFORMATION_SCHEMA.COLUMNS
               WHERE table_schema = 'MARTS' AND table_name IN ('DIM_DRIVER', 'MART_DRIVER_MONTHLY', 'DIM_DEPOT'))
    UNION ALL SELECT 'TRANSFORMER : les 16 colonnes de DIM_DRIVER et DIM_DEPOT ont leur description (fiches complètes)', 16,
              (SELECT COUNT(*) FROM v WHERE table_name IN ('DIM_DRIVER', 'DIM_DEPOT') AND description <> '')
    UNION ALL SELECT 'TRANSFORMER : valeurs des tags de table (confidentiel sur 20 colonnes, interne sur les 4 de DIM_DEPOT)', 24,
              (SELECT COUNT(*) FROM v WHERE (table_name IN ('DIM_DRIVER', 'MART_DRIVER_MONTHLY') AND sensibilite = 'confidentiel')
                                         OR (table_name = 'DIM_DEPOT' AND sensibilite = 'interne'))
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- ===================================================================== ANALYSTE : le « c'est fini quand » du guide
USE SECONDARY ROLES NONE;
USE ROLE ANALYSTE;
USE WAREHOUSE NYC_TAXI_WH;

WITH v AS (SELECT * FROM NYC_TAXI.GOUVERNANCE.V_CATALOGUE),
attendu AS (
    SELECT 'ANALYSTE : V_CATALOGUE, 24 colonnes cataloguées' AS verification, 24 AS attendu, (SELECT COUNT(*) FROM v) AS obtenu
    UNION ALL SELECT 'ANALYSTE : les 3 tables de MARTS y sont', 3, (SELECT COUNT(DISTINCT table_name) FROM v)
    UNION ALL SELECT 'ANALYSTE : DIM_DRIVER 12 colonnes, MART_DRIVER_MONTHLY 8, DIM_DEPOT 4', 3,
              (SELECT COUNT(*) FROM (SELECT table_name, COUNT(*) AS n FROM v GROUP BY table_name)
               WHERE (table_name, n) IN (('DIM_DRIVER', 12), ('MART_DRIVER_MONTHLY', 8), ('DIM_DEPOT', 4)))
    UNION ALL SELECT 'ANALYSTE : le tag DONNEE_PERSONNELLE se lit sur 9 colonnes (7 de DIM_DRIVER, 2 du mart)', 9,
              (SELECT COUNT(donnee_personnelle) FROM v)
    UNION ALL SELECT 'ANALYSTE : SENSIBILITE et DUREE_CONSERVATION se lisent sur les 24 colonnes', 24,
              (SELECT COUNT(*) FROM v WHERE sensibilite IS NOT NULL AND duree_conservation IS NOT NULL)
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- ===================================================================== RH_PAIE
USE SECONDARY ROLES NONE;
USE ROLE RH_PAIE;
USE WAREHOUSE NYC_TAXI_WH;

WITH v AS (SELECT * FROM NYC_TAXI.GOUVERNANCE.V_CATALOGUE),
attendu AS (
    SELECT 'RH_PAIE : V_CATALOGUE, 24 colonnes cataloguées' AS verification, 24 AS attendu, (SELECT COUNT(*) FROM v) AS obtenu
    UNION ALL SELECT 'RH_PAIE : les 3 tables de MARTS y sont', 3, (SELECT COUNT(DISTINCT table_name) FROM v)
    UNION ALL SELECT 'RH_PAIE : DIM_DRIVER 12 colonnes, MART_DRIVER_MONTHLY 8, DIM_DEPOT 4', 3,
              (SELECT COUNT(*) FROM (SELECT table_name, COUNT(*) AS n FROM v GROUP BY table_name)
               WHERE (table_name, n) IN (('DIM_DRIVER', 12), ('MART_DRIVER_MONTHLY', 8), ('DIM_DEPOT', 4)))
    UNION ALL SELECT 'RH_PAIE : le tag DONNEE_PERSONNELLE se lit sur 9 colonnes (7 de DIM_DRIVER, 2 du mart)', 9,
              (SELECT COUNT(donnee_personnelle) FROM v)
    UNION ALL SELECT 'RH_PAIE : SENSIBILITE et DUREE_CONSERVATION se lisent sur les 24 colonnes', 24,
              (SELECT COUNT(*) FROM v WHERE sensibilite IS NOT NULL AND duree_conservation IS NOT NULL)
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- ===================================================================== RESP_DEPOT_QUEENS
USE SECONDARY ROLES NONE;
USE ROLE RESP_DEPOT_QUEENS;
USE WAREHOUSE NYC_TAXI_WH;

WITH v AS (SELECT * FROM NYC_TAXI.GOUVERNANCE.V_CATALOGUE),
attendu AS (
    SELECT 'RESP_DEPOT_QUEENS : V_CATALOGUE, 24 colonnes cataloguées' AS verification, 24 AS attendu, (SELECT COUNT(*) FROM v) AS obtenu
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : les 3 tables de MARTS y sont', 3, (SELECT COUNT(DISTINCT table_name) FROM v)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : DIM_DRIVER 12 colonnes, MART_DRIVER_MONTHLY 8, DIM_DEPOT 4', 3,
              (SELECT COUNT(*) FROM (SELECT table_name, COUNT(*) AS n FROM v GROUP BY table_name)
               WHERE (table_name, n) IN (('DIM_DRIVER', 12), ('MART_DRIVER_MONTHLY', 8), ('DIM_DEPOT', 4)))
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : le tag DONNEE_PERSONNELLE se lit sur 9 colonnes (7 de DIM_DRIVER, 2 du mart)', 9,
              (SELECT COUNT(donnee_personnelle) FROM v)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : SENSIBILITE et DUREE_CONSERVATION se lisent sur les 24 colonnes', 24,
              (SELECT COUNT(*) FROM v WHERE sensibilite IS NOT NULL AND duree_conservation IS NOT NULL)
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- ===================================================================== RESP_DEPOT_BRONX
USE SECONDARY ROLES NONE;
USE ROLE RESP_DEPOT_BRONX;
USE WAREHOUSE NYC_TAXI_WH;

WITH v AS (SELECT * FROM NYC_TAXI.GOUVERNANCE.V_CATALOGUE),
attendu AS (
    SELECT 'RESP_DEPOT_BRONX : V_CATALOGUE, 24 colonnes cataloguées' AS verification, 24 AS attendu, (SELECT COUNT(*) FROM v) AS obtenu
    UNION ALL SELECT 'RESP_DEPOT_BRONX : les 3 tables de MARTS y sont', 3, (SELECT COUNT(DISTINCT table_name) FROM v)
    UNION ALL SELECT 'RESP_DEPOT_BRONX : DIM_DRIVER 12 colonnes, MART_DRIVER_MONTHLY 8, DIM_DEPOT 4', 3,
              (SELECT COUNT(*) FROM (SELECT table_name, COUNT(*) AS n FROM v GROUP BY table_name)
               WHERE (table_name, n) IN (('DIM_DRIVER', 12), ('MART_DRIVER_MONTHLY', 8), ('DIM_DEPOT', 4)))
    UNION ALL SELECT 'RESP_DEPOT_BRONX : le tag DONNEE_PERSONNELLE se lit sur 9 colonnes (7 de DIM_DRIVER, 2 du mart)', 9,
              (SELECT COUNT(donnee_personnelle) FROM v)
    UNION ALL SELECT 'RESP_DEPOT_BRONX : SENSIBILITE et DUREE_CONSERVATION se lisent sur les 24 colonnes', 24,
              (SELECT COUNT(*) FROM v WHERE sensibilite IS NOT NULL AND duree_conservation IS NOT NULL)
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;
