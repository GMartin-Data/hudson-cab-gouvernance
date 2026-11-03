-- =====================================================================
-- 02_verif_catalogue.sql — le test du catalogue, écrit avant les fiches (jour 1, étape 11).
-- Ce qui doit être vrai : chaque table du domaine RH et DIM_DEPOT ont une description, un tag SENSIBILITE
-- et un tag DUREE_CONSERVATION ; aucune colonne de DIM_DEPOT, DIM_DRIVER et RAW.DRIVERS n'est sans
-- description ; le tag DONNEE_PERSONNELLE est posé sur chaque colonne personnelle de l'inventaire
-- (docs/REGISTRE.md, partie 1), et seulement sur elles.
-- Rôle : TRANSFORMER, propriétaire des tables : INFORMATION_SCHEMA ne montre que ce que le rôle a le droit de voir.
-- Rejouable. Avant les fiches : des lignes KO. C'est bon quand : toutes les lignes affichent statut = OK.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

WITH tags AS (                                                          -- tous les tags des cinq tables, niveau table et colonne
    SELECT 'RAW.DRIVERS' AS tbl, level, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.RAW.DRIVERS', 'table'))
    UNION ALL
    SELECT 'RAW.DRIVER_SHIFTS', level, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.RAW.DRIVER_SHIFTS', 'table'))
    UNION ALL
    SELECT 'MARTS.DIM_DRIVER', level, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.DIM_DRIVER', 'table'))
    UNION ALL
    SELECT 'MARTS.MART_DRIVER_MONTHLY', level, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.MART_DRIVER_MONTHLY', 'table'))
    UNION ALL
    SELECT 'MARTS.DIM_DEPOT', level, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.DIM_DEPOT', 'table'))
),
attendu AS (
    -- Descriptions de table
    SELECT 'Description de table : les cinq tables (RH + DIM_DEPOT) en ont une' AS verification, 5 AS attendu,
           (SELECT COUNT(*) FROM NYC_TAXI.INFORMATION_SCHEMA.TABLES
            WHERE (table_schema, table_name) IN (('RAW','DRIVERS'), ('RAW','DRIVER_SHIFTS'),
                                                 ('MARTS','DIM_DRIVER'), ('MARTS','MART_DRIVER_MONTHLY'), ('MARTS','DIM_DEPOT'))
              AND comment IS NOT NULL AND comment <> '') AS obtenu
    UNION ALL
    -- Descriptions de colonne (fiches complètes + modèle du kit)
    SELECT 'Colonnes sans description dans DIM_DEPOT, DIM_DRIVER et RAW.DRIVERS', 0,
           (SELECT COUNT(*) FROM NYC_TAXI.INFORMATION_SCHEMA.COLUMNS
            WHERE (table_schema, table_name) IN (('MARTS','DIM_DEPOT'), ('MARTS','DIM_DRIVER'), ('RAW','DRIVERS'))
              AND (comment IS NULL OR comment = ''))
    UNION ALL
    -- Tags de table
    SELECT 'Tag SENSIBILITE sur chacune des cinq tables', 5,
           (SELECT COUNT(DISTINCT tbl) FROM tags WHERE level = 'TABLE' AND tag_name = 'SENSIBILITE')
    UNION ALL
    SELECT 'Tag DUREE_CONSERVATION sur chacune des cinq tables', 5,
           (SELECT COUNT(DISTINCT tbl) FROM tags WHERE level = 'TABLE' AND tag_name = 'DUREE_CONSERVATION')
    UNION ALL
    SELECT 'SENSIBILITE = confidentiel sur RAW.DRIVERS, DIM_DRIVER et MART_DRIVER_MONTHLY', 3,
           (SELECT COUNT(DISTINCT tbl) FROM tags
            WHERE level = 'TABLE' AND tag_name = 'SENSIBILITE' AND tag_value = 'confidentiel'
              AND tbl IN ('RAW.DRIVERS', 'MARTS.DIM_DRIVER', 'MARTS.MART_DRIVER_MONTHLY'))
    UNION ALL
    SELECT 'SENSIBILITE = interne sur RAW.DRIVER_SHIFTS et DIM_DEPOT', 2,
           (SELECT COUNT(DISTINCT tbl) FROM tags
            WHERE level = 'TABLE' AND tag_name = 'SENSIBILITE' AND tag_value = 'interne'
              AND tbl IN ('RAW.DRIVER_SHIFTS', 'MARTS.DIM_DEPOT'))
    UNION ALL
    -- Tag DONNEE_PERSONNELLE, colonne par colonne, d'après l'inventaire du registre
    SELECT 'RAW.DRIVERS : 7 colonnes personnelles taguées (driver_id, first_name, last_name, email, phone, birth_date, tlc_license_number)', 7,
           (SELECT COUNT(*) FROM tags
            WHERE tbl = 'RAW.DRIVERS' AND level = 'COLUMN' AND tag_name = 'DONNEE_PERSONNELLE'
              AND (column_name, tag_value) IN (('DRIVER_ID','identifiant_interne'), ('FIRST_NAME','nom'), ('LAST_NAME','nom'),
                                               ('EMAIL','email'), ('PHONE','telephone'), ('BIRTH_DATE','date_naissance'),
                                               ('TLC_LICENSE_NUMBER','identifiant_officiel')))
    UNION ALL
    SELECT 'DIM_DRIVER : 7 colonnes personnelles taguées (mêmes colonnes, mêmes valeurs)', 7,
           (SELECT COUNT(*) FROM tags
            WHERE tbl = 'MARTS.DIM_DRIVER' AND level = 'COLUMN' AND tag_name = 'DONNEE_PERSONNELLE'
              AND (column_name, tag_value) IN (('DRIVER_ID','identifiant_interne'), ('FIRST_NAME','nom'), ('LAST_NAME','nom'),
                                               ('EMAIL','email'), ('PHONE','telephone'), ('BIRTH_DATE','date_naissance'),
                                               ('TLC_LICENSE_NUMBER','identifiant_officiel')))
    UNION ALL
    SELECT 'RAW.DRIVER_SHIFTS : 1 colonne personnelle taguée (driver_id = identifiant_interne)', 1,
           (SELECT COUNT(*) FROM tags
            WHERE tbl = 'RAW.DRIVER_SHIFTS' AND level = 'COLUMN' AND tag_name = 'DONNEE_PERSONNELLE'
              AND (column_name, tag_value) IN (('DRIVER_ID','identifiant_interne')))
    UNION ALL
    SELECT 'MART_DRIVER_MONTHLY : 2 colonnes personnelles taguées (driver_id = identifiant_interne, driver_name = nom)', 2,
           (SELECT COUNT(*) FROM tags
            WHERE tbl = 'MARTS.MART_DRIVER_MONTHLY' AND level = 'COLUMN' AND tag_name = 'DONNEE_PERSONNELLE'
              AND (column_name, tag_value) IN (('DRIVER_ID','identifiant_interne'), ('DRIVER_NAME','nom')))
    UNION ALL
    SELECT 'Aucun tag DONNEE_PERSONNELLE en trop (17 colonnes taguées au total, aucune sur DIM_DEPOT)', 17,
           (SELECT COUNT(*) FROM tags WHERE level = 'COLUMN' AND tag_name = 'DONNEE_PERSONNELLE')
)
SELECT verification, attendu, obtenu,
       IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu
ORDER BY statut, verification;   -- 'KO' < 'OK' : les échecs d'abord
