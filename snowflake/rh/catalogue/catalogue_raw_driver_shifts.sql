-- =====================================================================
-- catalogue_raw_driver_shifts.sql — fiche de catalogue courte de RAW.DRIVER_SHIFTS : description de la table,
-- tags SENSIBILITE et DUREE_CONSERVATION sur la table, DONNEE_PERSONNELLE sur sa seule colonne personnelle (driver_id).
-- Rôle : TRANSFORMER, propriétaire de la table. Rejouable.
-- C'est bon quand : la requête finale affiche 1 ligne level = COLUMN (driver_id, DONNEE_PERSONNELLE),
-- puis les 2 tags de table hérités par chacune des 10 colonnes (level = TABLE).
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- 1. La table
COMMENT ON TABLE NYC_TAXI.RAW.DRIVER_SHIFTS IS
  'Services (prises de poste) des chauffeurs, copiés tels quels : 1 ligne = 1 service déclaré (25 951 lignes de janvier à mars 2025, dont des doublons d''identifiant). Source : data/driver_shifts.csv, chargé par COPY INTO sans transformation. Ne désigne un chauffeur que par son identifiant interne (driver_id) : pseudonymisé, mais l''activité d''une personne, soumise à la règle R1. Responsable : équipe data de Hudson Cab Europe.';

-- 2. Les tags de table
ALTER TABLE NYC_TAXI.RAW.DRIVER_SHIFTS SET TAG
  NYC_TAXI.GOUVERNANCE.SENSIBILITE        = 'interne',
  NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION = '5 ans après la fin du contrat du chauffeur (R1)';

-- 3. Le tag DONNEE_PERSONNELLE sur la seule colonne qui renvoie à une personne
ALTER TABLE NYC_TAXI.RAW.DRIVER_SHIFTS MODIFY COLUMN driver_id SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'identifiant_interne';
-- depot : personnelle indirecte selon l'inventaire, hors du vocabulaire du tag ; sert au filtrage par ligne (jour 2).

-- 4. Vérifier : 1 ligne level = COLUMN (le tag posé sur driver_id), puis, pour chaque colonne, les 2 tags de table
-- dont elle hérite (level = TABLE, apply_method = INHERITED)
SELECT level, apply_method, column_name, tag_name, tag_value
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.RAW.DRIVER_SHIFTS', 'table'))
ORDER BY level, column_name, tag_name;
