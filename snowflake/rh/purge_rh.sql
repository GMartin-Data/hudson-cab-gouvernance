-- =====================================================================
-- purge_rh.sql — règle R1 du contrat : les données d'un chauffeur sont supprimées 5 ans après la fin de son
-- contrat, partout où elles ont été copiées (jour 3, étape 1).
-- Quatre tables : RAW.DRIVERS (la source), RAW.DRIVER_SHIFTS (ses services portent son driver_id),
-- MARTS.DIM_DRIVER et MARTS.MART_DRIVER_MONTHLY (les copies, purgées ici sans attendre leur reconstruction :
-- R1 ne doit pas dépendre d'un contrôle de qualité qui empêcherait T_TABLES de partir).
-- Échéance : fin de contrat + 5 ans atteinte aujourd'hui. Un chauffeur en poste (end_date vide) n'est jamais purgé.
-- Rôle : TRANSFORMER, propriétaire des tables. Rejouable : au second passage, il n'y a plus rien à supprimer.
-- C'est bon quand : la dernière requête affiche 0 chauffeur échu dans RAW et dans MARTS, et autant de services
-- sans chauffeur qu'avant la purge ; puis snowflake/verif/05_verif_purge.sql est entièrement OK.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- ===================================================================== 1. Compter avant de supprimer
SELECT
    (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS
      WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()))                              AS chauffeurs_a_purger,
    (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS
      WHERE driver_id IN (SELECT driver_id FROM NYC_TAXI.RAW.DRIVERS
                           WHERE end_date <= DATEADD(year, -5, CURRENT_DATE())))        AS services_a_purger,
    (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER
      WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()))                              AS dim_driver_a_purger,
    (SELECT COUNT(*) FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY
      WHERE driver_id IN (SELECT driver_id FROM NYC_TAXI.RAW.DRIVERS
                           WHERE end_date <= DATEADD(year, -5, CURRENT_DATE())))        AS lignes_mart_a_purger,
    (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS s
      WHERE NOT EXISTS (SELECT 1 FROM NYC_TAXI.RAW.DRIVERS r
                         WHERE r.driver_id = s.driver_id))                              AS services_sans_chauffeur;

-- ===================================================================== 2. Purger, tout ou rien
-- Une transaction : si une suppression échoue, aucune n'est gardée. RAW.DRIVERS part en dernier, parce que
-- c'est elle qui dit quels driver_id sont échus : une fois le chauffeur supprimé, ses services et ses lignes
-- de mart ne se retrouveraient plus.
BEGIN TRANSACTION;

DELETE FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY
 WHERE driver_id IN (SELECT driver_id FROM NYC_TAXI.RAW.DRIVERS
                      WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()));

DELETE FROM NYC_TAXI.RAW.DRIVER_SHIFTS
 WHERE driver_id IN (SELECT driver_id FROM NYC_TAXI.RAW.DRIVERS
                      WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()));

DELETE FROM NYC_TAXI.MARTS.DIM_DRIVER
 WHERE end_date <= DATEADD(year, -5, CURRENT_DATE());

DELETE FROM NYC_TAXI.RAW.DRIVERS
 WHERE end_date <= DATEADD(year, -5, CURRENT_DATE());

COMMIT;

-- ===================================================================== 3. Vérifier
SELECT
    (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS
      WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()))                              AS echus_raw_drivers,
    (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER
      WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()))                              AS echus_dim_driver,
    (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS)                                         AS chauffeurs_raw,
    (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER)                                    AS chauffeurs_dim_driver,
    (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS)                                   AS services,
    (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS s
      WHERE NOT EXISTS (SELECT 1 FROM NYC_TAXI.RAW.DRIVERS r
                         WHERE r.driver_id = s.driver_id))                              AS services_sans_chauffeur;
