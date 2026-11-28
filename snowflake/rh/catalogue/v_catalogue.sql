-- =====================================================================
-- v_catalogue.sql — la vue GOUVERNANCE.V_CATALOGUE du contrat : une ligne par colonne cataloguée (jour 3, étape 5).
-- Elle porte sur les trois tables de MARTS que les rôles métier lisent : DIM_DRIVER, MART_DRIVER_MONTHLY, DIM_DEPOT.
-- RAW n'y est pas : la vue s'appuie sur INFORMATION_SCHEMA, qui ne montre que ce que le rôle qui interroge a le
-- droit de voir, et les rôles métier n'ont aucun droit sur RAW (la vue leur reviendrait incomplète).
-- Rôle : TRANSFORMER. GOUVERNANCE possède le schéma mais ne voit pas les tables ; le rôle des outils y a reçu
-- CREATE VIEW (01_gouvernance.sql). Propriétaire de la vue, c'est lui qui en accorde la lecture.
-- Rejouable : CREATE OR REPLACE ... COPY GRANTS remplace le corps de la vue en gardant les droits déjà accordés,
-- et les GRANT qui suivent les rétablissent de toute façon.
-- C'est bon quand : la dernière requête affiche 3 lignes (12, 8 et 4 colonnes) ; puis
-- snowflake/verif/07_verif_v_catalogue.sql est sans KO (ANALYSTE y trouve les trois tables) et
-- snowflake/verif/03_verif_roles.sql affiche 15 OK.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- ===================================================================== 1. La vue
-- TAG_REFERENCES_ALL_COLUMNS s'appelle pour UNE table à la fois : un bloc par table, réunis par UNION ALL.
-- Pour chaque colonne, elle rend le tag posé sur la colonne (DONNEE_PERSONNELLE) et les tags hérités de la table
-- (SENSIBILITE, DUREE_CONSERVATION) : le MAX(IFF(...)) les range en trois colonnes, une ligne par colonne de table.
CREATE OR REPLACE VIEW NYC_TAXI.GOUVERNANCE.V_CATALOGUE
  COPY GRANTS
  COMMENT = 'Catalogue des tables de MARTS lues par les rôles métier : une ligne par colonne, avec sa description, son type et ses tags (donnée personnelle, sensibilité, durée de conservation). Alimentée par les fiches de snowflake/rh/catalogue/.'
AS
WITH tags AS (
    SELECT object_schema, object_name, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.DIM_DRIVER', 'table'))
    UNION ALL
    SELECT object_schema, object_name, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.MART_DRIVER_MONTHLY', 'table'))
    UNION ALL
    SELECT object_schema, object_name, column_name, tag_name, tag_value
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.DIM_DEPOT', 'table'))
)
SELECT
    c.table_name,
    c.ordinal_position                                                  AS position,
    c.column_name,
    c.data_type,
    c.comment                                                           AS description,
    MAX(IFF(g.tag_name = 'DONNEE_PERSONNELLE', g.tag_value, NULL))      AS donnee_personnelle,
    MAX(IFF(g.tag_name = 'SENSIBILITE',        g.tag_value, NULL))      AS sensibilite,
    MAX(IFF(g.tag_name = 'DUREE_CONSERVATION', g.tag_value, NULL))      AS duree_conservation
FROM NYC_TAXI.INFORMATION_SCHEMA.COLUMNS c
LEFT JOIN tags g
  ON g.object_schema = c.table_schema AND g.object_name = c.table_name AND g.column_name = c.column_name
WHERE c.table_schema = 'MARTS' AND c.table_name IN ('DIM_DRIVER', 'MART_DRIVER_MONTHLY', 'DIM_DEPOT')
GROUP BY 1, 2, 3, 4, 5;

-- ===================================================================== 2. La lecture, pour les quatre rôles métier
-- Un GRANT nommé sur cette vue, pas un droit sur les vues futures du schéma : celui-ci ouvrirait aussi toute vue
-- d'audit ou de qualité créée dans GOUVERNANCE demain. Les rôles ont déjà USAGE sur le schéma (02_roles_metier.sql).
GRANT SELECT ON VIEW NYC_TAXI.GOUVERNANCE.V_CATALOGUE TO ROLE RH_PAIE;
GRANT SELECT ON VIEW NYC_TAXI.GOUVERNANCE.V_CATALOGUE TO ROLE RESP_DEPOT_QUEENS;
GRANT SELECT ON VIEW NYC_TAXI.GOUVERNANCE.V_CATALOGUE TO ROLE RESP_DEPOT_BRONX;
GRANT SELECT ON VIEW NYC_TAXI.GOUVERNANCE.V_CATALOGUE TO ROLE ANALYSTE;

-- ===================================================================== 3. Vérifier : 3 lignes, 12 / 8 / 4 colonnes
SELECT table_name,
       COUNT(*)                       AS colonnes,
       COUNT(NULLIF(description, '')) AS decrites,
       COUNT(donnee_personnelle)      AS personnelles,
       MIN(sensibilite)               AS sensibilite,
       MIN(duree_conservation)        AS duree_conservation
FROM NYC_TAXI.GOUVERNANCE.V_CATALOGUE
GROUP BY table_name
ORDER BY table_name;
