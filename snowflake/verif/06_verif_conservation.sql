-- =====================================================================
-- 06_verif_conservation.sql — le test des règles R2 et R3, écrit avant conservation_rh.sql (jour 3, étapes 2 et 3).
-- Ce qui doit être vrai :
--   R2 : sur chaque table qui contient des données de chauffeurs, la rétention Time Travel vaut 1 jour ET elle est
--        posée sur la table elle-même (level = TABLE). Une valeur seulement héritée du compte ou de la base changerait
--        le jour où quelqu'un modifie le défaut, sans toucher à nos scripts. Le compte n'impose pas de minimum
--        supérieur (MIN_DATA_RETENTION_TIME_IN_DAYS l'emporterait sur la valeur de la table).
--   R2, dans les faits : relire une table telle qu'elle était il y a 2 jours est refusé.
--   R3 : aucun fichier sur le stage RH_STAGE.
-- DIM_DEPOT n'est pas concernée : référentiel sans donnée personnelle. Les vues de STAGING n'ont pas de rétention.
-- Rôle : TRANSFORMER, propriétaire des tables et du stage.
-- Rejouable. Avant conservation_rh.sql : 4 lignes KO (rétention à 1 jour, mais héritée : level vide).
-- C'est bon quand : aucun KO dans la sortie, aucune erreur :
--   snow sql -c hudson_cab -f snowflake/verif/06_verif_conservation.sql | grep -c ' KO '   → 0
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- Le pipe ->> enchaîne les commandes ; $1 est le résultat de la précédente, $2 celui d'avant, etc.
SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.RAW.DRIVERS                    -- $6
  ->> SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.RAW.DRIVER_SHIFTS        -- $5
  ->> SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.MARTS.DIM_DRIVER         -- $4
  ->> SHOW PARAMETERS LIKE 'DATA_RETENTION_TIME_IN_DAYS' IN TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY -- $3
  ->> SHOW PARAMETERS LIKE 'MIN_DATA_RETENTION_TIME_IN_DAYS' IN ACCOUNT                             -- $2
  ->> LIST @NYC_TAXI.RAW.RH_STAGE                                                                   -- $1
  ->> WITH attendu AS (
        SELECT 'R2 : RAW.DRIVERS, rétention de 1 jour posée sur la table' AS verification, 1 AS attendu,
               (SELECT COUNT(*) FROM $6 WHERE "value" = '1' AND "level" = 'TABLE') AS obtenu
        UNION ALL
        SELECT 'R2 : RAW.DRIVER_SHIFTS, rétention de 1 jour posée sur la table', 1,
               (SELECT COUNT(*) FROM $5 WHERE "value" = '1' AND "level" = 'TABLE')
        UNION ALL
        SELECT 'R2 : MARTS.DIM_DRIVER, rétention de 1 jour posée sur la table', 1,
               (SELECT COUNT(*) FROM $4 WHERE "value" = '1' AND "level" = 'TABLE')
        UNION ALL
        SELECT 'R2 : MARTS.MART_DRIVER_MONTHLY, rétention de 1 jour posée sur la table', 1,
               (SELECT COUNT(*) FROM $3 WHERE "value" = '1' AND "level" = 'TABLE')
        UNION ALL
        SELECT 'R2 : le compte n''impose pas une rétention minimale de plus de 1 jour', 0,
               (SELECT COUNT(*) FROM $2 WHERE "value"::INTEGER > 1)
        UNION ALL
        SELECT 'R3 : aucun fichier sur le stage RH_STAGE', 0,
               (SELECT COUNT(*) FROM $1)
      )
      SELECT verification, attendu, obtenu,
             IFF(obtenu = attendu, 'OK', 'KO') AS statut
      FROM attendu
      ORDER BY statut, verification;   -- 'KO' < 'OK' : les échecs d'abord

-- R2 dans les faits : la lecture à 2 jours (172 800 secondes) doit être refusée, table par table. Le bloc attrape
-- l'erreur attendue, sans quoi la CLI s'arrêterait à la première ; toute autre erreur sort en KO. Les littéraux
-- s'écrivent sans espace devant KO : la CLI écho le texte du script, et le critère grep -c ' KO ' ne doit compter
-- que les cellules de résultat.
EXECUTE IMMEDIATE $$
DECLARE
  tables ARRAY DEFAULT ['NYC_TAXI.RAW.DRIVERS', 'NYC_TAXI.RAW.DRIVER_SHIFTS',
                        'NYC_TAXI.MARTS.DIM_DRIVER', 'NYC_TAXI.MARTS.MART_DRIVER_MONTHLY'];
  tbl    STRING;
  bilan  STRING DEFAULT '';
BEGIN
  FOR i IN 0 TO ARRAY_SIZE(tables) - 1 DO
    tbl := tables[i]::STRING;
    BEGIN
      EXECUTE IMMEDIATE 'SELECT COUNT(*) FROM ' || tbl || ' AT(OFFSET => -172800)';
      bilan := bilan || 'KO : ' || tbl || ' se relit encore à 2 jours. ';
    EXCEPTION
      WHEN STATEMENT_ERROR THEN
        bilan := bilan || IFF(CONTAINS(SQLERRM, 'Time travel data is not available'),
                              'OK : ' || tbl || ' illisible à 2 jours. ',
                              'KO : erreur inattendue sur ' || tbl || ' : ' || SQLERRM || ' ');
    END;
  END FOR;
  RETURN TRIM(bilan);
END;
$$;
