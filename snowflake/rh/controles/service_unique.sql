-- Règle de qualité service_unique (contrat, section 6) : un identifiant de service n'apparaît qu'une fois.
-- Une ligne, une colonne : le nombre de lignes en trop (un service chargé trois fois compte pour 2).
-- Seuil : 0. Dépassement : avertissement (ligne ALERTE, les tâches continuent).
-- Mesurée dans RAW, pas dans la vue STG_RH__DRIVER_SHIFTS : la vue ne garde déjà qu'une ligne par shift_id,
-- la règle y vaudrait toujours 0.
SELECT COUNT(*) - COUNT(DISTINCT shift_id) AS nb_anomalies
FROM NYC_TAXI.RAW.DRIVER_SHIFTS;
