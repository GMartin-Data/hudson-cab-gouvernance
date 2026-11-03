-- =====================================================================
-- catalogue_mart_driver_monthly.sql — fiche de catalogue courte de MARTS.MART_DRIVER_MONTHLY : description de la table,
-- tags SENSIBILITE et DUREE_CONSERVATION sur la table, DONNEE_PERSONNELLE sur ses deux colonnes personnelles
-- (driver_id, et driver_name, nom complet calculé à partir de DIM_DRIVER).
-- Rôle : TRANSFORMER, propriétaire de la table. Rejouable.
-- Les tags survivent au pipeline parce que mart_driver_monthly.sql remplit la table par INSERT OVERWRITE sans la recréer.
-- C'est bon quand : la requête finale affiche 2 lignes level = COLUMN (driver_id, driver_name : DONNEE_PERSONNELLE),
-- puis les 2 tags de table hérités par chacune des 8 colonnes (level = TABLE).
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- 1. La table
COMMENT ON TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY IS
  'Activité mensuelle de chaque chauffeur : 1 ligne = 1 chauffeur x 1 mois x 1 dépôt (914 lignes), avec le nombre de services, les heures, les courses et la recette. Source : STAGING.STG_RH__DRIVER_SHIFTS agrégée, jointe à DIM_DRIVER pour le nom complet. Reconstruite à chaque exécution de mart_driver_monthly.sql (INSERT OVERWRITE). Contient un nom en clair (driver_name) : si DIM_DRIVER est masquée pour le rôle qui reconstruit, cette colonne se remplit de valeurs masquées sans erreur. Responsable : équipe data de Hudson Cab Europe.';

-- 2. Les tags de table
ALTER TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY SET TAG
  NYC_TAXI.GOUVERNANCE.SENSIBILITE        = 'confidentiel',
  NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION = '5 ans après la fin du contrat du chauffeur (R1)';

-- 3. Le tag DONNEE_PERSONNELLE sur les colonnes qui renvoient à une personne
ALTER TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY MODIFY COLUMN driver_id   SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'identifiant_interne';
ALTER TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY MODIFY COLUMN driver_name SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'nom';
-- depot : personnelle indirecte selon l'inventaire, hors du vocabulaire du tag ; sert au filtrage par ligne (jour 2).
-- nb_shifts, hours_worked, trips_count, revenue_usd : l'activité d'une personne identifiée par driver_id, protégée par la table.

-- 4. Vérifier : 2 lignes level = COLUMN (les tags posés sur driver_id et driver_name), puis, pour chaque colonne,
-- les 2 tags de table dont elle hérite (level = TABLE, apply_method = INHERITED)
SELECT level, apply_method, column_name, tag_name, tag_value
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.MART_DRIVER_MONTHLY', 'table'))
ORDER BY level, column_name, tag_name;
