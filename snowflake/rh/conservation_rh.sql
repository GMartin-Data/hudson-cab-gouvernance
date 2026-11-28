-- =====================================================================
-- conservation_rh.sql — règle R2 du contrat : une donnée personnelle supprimée ne doit plus pouvoir être restaurée
-- par Time Travel au-delà de 1 jour (jour 3, étape 2).
-- Pose la rétention sur chacune des quatre tables qui contiennent des données de chauffeurs. La valeur était déjà
-- de 1 jour, mais héritée du défaut du compte : écrite sur la table, elle ne suit plus un changement de ce défaut.
-- DIM_DEPOT n'est pas concernée (référentiel sans donnée personnelle).
-- Rôle : TRANSFORMER. Seul le propriétaire d'une table change sa rétention : GOUVERNANCE serait refusé.
-- Rejouable. C'est bon quand : la dernière requête affiche 4 lignes, value = 1 et level = TABLE ;
-- puis snowflake/verif/06_verif_conservation.sql est sans KO.
-- Après ce délai de 1 jour, Snowflake garde encore les données 7 jours en Fail-safe : ni lisibles ni réglables
-- sur une table permanente (voir docs/REGISTRE.md).
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

ALTER TABLE NYC_TAXI.RAW.DRIVERS               SET DATA_RETENTION_TIME_IN_DAYS = 1;
ALTER TABLE NYC_TAXI.RAW.DRIVER_SHIFTS         SET DATA_RETENTION_TIME_IN_DAYS = 1;
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER          SET DATA_RETENTION_TIME_IN_DAYS = 1;
ALTER TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY SET DATA_RETENTION_TIME_IN_DAYS = 1;

-- Vérifier : le pipe ->> enchaîne les SHOW ; $1 est le résultat du dernier, $4 celui du premier.
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.RAW.DRIVERS
  ->> SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.RAW.DRIVER_SHIFTS
  ->> SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.MARTS.DIM_DRIVER
  ->> SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY
  ->> SELECT 'RAW.DRIVERS' AS tbl, "value", "level" FROM $4
      UNION ALL SELECT 'RAW.DRIVER_SHIFTS', "value", "level" FROM $3
      UNION ALL SELECT 'MARTS.DIM_DRIVER', "value", "level" FROM $2
      UNION ALL SELECT 'MARTS.MART_DRIVER_MONTHLY', "value", "level" FROM $1;
