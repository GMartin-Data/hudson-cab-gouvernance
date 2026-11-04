-- =====================================================================
-- catalogue_dim_driver.sql — fiche de catalogue complète de MARTS.DIM_DRIVER : description de la table,
-- de chaque colonne, et les trois tags du contrat (SENSIBILITE et DUREE_CONSERVATION sur la table,
-- DONNEE_PERSONNELLE sur chaque colonne personnelle de l'inventaire, docs/REGISTRE.md partie 1).
-- Rôle : TRANSFORMER, propriétaire de la table. Rejouable : COMMENT et SET TAG remplacent la valeur précédente.
-- Les tags survivent au pipeline parce que dim_driver.sql remplit la table par INSERT OVERWRITE sans la recréer.
-- C'est bon quand : la première requête finale n'affiche aucune colonne sans description ; la seconde affiche
-- 7 lignes level = COLUMN (DONNEE_PERSONNELLE), puis les 2 tags de table hérités par chacune des 12 colonnes (level = TABLE).
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- 1. La table
COMMENT ON TABLE NYC_TAXI.MARTS.DIM_DRIVER IS
  'Dimension chauffeur : 1 ligne = 1 chauffeur (400 lignes avant purge), en poste ou parti, avec ses coordonnées normalisées et deux colonnes calculées (en poste ou non, ancienneté). Source : STAGING.STG_RH__DRIVERS, elle-même lue de RAW.DRIVERS. Reconstruite à chaque exécution de dim_driver.sql (INSERT OVERWRITE). Données personnelles directes : lue par les rôles métier selon la matrice des accès du contrat. Responsable : équipe data de Hudson Cab Europe.';

-- 2. Les colonnes
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.driver_id          IS 'Identifiant interne du chauffeur (lettre D puis quatre chiffres). Clé de la dimension et clé de jointure avec MART_DRIVER_MONTHLY.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.first_name         IS 'Prénom du chauffeur.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.last_name          IS 'Nom de famille du chauffeur.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.email              IS 'Adresse e-mail professionnelle, normalisée en minuscules et sans espaces (LOWER(TRIM(email))). Même donnée que RAW.DRIVERS.email.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.phone              IS 'Numéro de téléphone du chauffeur ; une valeur vide dans le fichier devient NULL ici (NULLIF(TRIM(phone), '''')). Seul moyen de contact direct pour les responsables de dépôt.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.birth_date         IS 'Date de naissance complète. L''analyse n''a besoin que de l''année : le masquage du jour 2 réduira la donnée pour ce rôle.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.tlc_license_number IS 'Numéro de licence TLC (Taxi and Limousine Commission de New York). Identifiant officiel, unique par chauffeur, qui désigne une personne sans ambiguïté.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.depot              IS 'Dépôt de rattachement, normalisé (Bronx, Brooklyn ou Queens, INITCAP(TRIM(depot))). Colonne de filtrage de l''accès par ligne : un responsable de dépôt ne voit que ses chauffeurs. Donnée personnelle indirecte, hors du vocabulaire du tag.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.hire_date          IS 'Date d''embauche. Donnée personnelle indirecte, hors du vocabulaire du tag.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.end_date           IS 'Date de fin de contrat ; NULL = chauffeur en poste. Point de départ du délai de conservation de 5 ans (règle R1). Donnée personnelle indirecte, hors du vocabulaire du tag.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.is_active          IS 'Vrai si le chauffeur est en poste (end_date IS NULL). Colonne calculée, dérivée d''une donnée personnelle.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DRIVER.tenure_years       IS 'Ancienneté en années, arrondie au dixième, de l''embauche à la fin de contrat ou à aujourd''hui (DATEDIFF / 365.25). Colonne calculée : change chaque jour pour les chauffeurs en poste. Dérivée de données personnelles.';

-- 3. Les tags de table (les colonnes en héritent)
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER SET TAG
  NYC_TAXI.GOUVERNANCE.SENSIBILITE        = 'confidentiel',
  NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION = '5 ans après la fin du contrat du chauffeur (R1)';

-- 4. Le tag DONNEE_PERSONNELLE, colonne par colonne : c'est lui qui déclenchera le masquage (jour 2)
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER MODIFY COLUMN driver_id          SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'identifiant_interne';
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER MODIFY COLUMN first_name         SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'nom';
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER MODIFY COLUMN last_name          SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'nom';
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER MODIFY COLUMN email              SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'email';
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER MODIFY COLUMN phone              SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'telephone';
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER MODIFY COLUMN birth_date         SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'date_naissance';
ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER MODIFY COLUMN tlc_license_number SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'identifiant_officiel';
-- depot, hire_date, end_date, is_active, tenure_years : personnelles indirectes ou dérivées selon l'inventaire,
-- mais aucune valeur du tag ne les décrit. Non taguées ; la table est confidentielle et l'accès par ligne (jour 2) les protège.

-- 5. Vérifier : aucune colonne sans description
SELECT column_name, comment
FROM NYC_TAXI.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'MARTS' AND table_name = 'DIM_DRIVER' AND (comment IS NULL OR comment = '')
ORDER BY ordinal_position;

-- Vérifier : 7 lignes level = COLUMN (le tag posé sur la colonne), puis, pour chaque colonne, les 2 tags de table
-- dont elle hérite (level = TABLE, apply_method = INHERITED)
SELECT level, apply_method, column_name, tag_name, tag_value
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.DIM_DRIVER', 'table'))
ORDER BY level, column_name, tag_name;
