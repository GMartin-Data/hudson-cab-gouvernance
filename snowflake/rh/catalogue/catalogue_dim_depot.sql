-- =====================================================================
-- catalogue_dim_depot.sql — fiche de catalogue complète de MARTS.DIM_DEPOT : description de la table, de chaque
-- colonne, tags SENSIBILITE et DUREE_CONSERVATION. Aucune donnée personnelle : pas de tag DONNEE_PERSONNELLE.
-- Fichier fourni par le kit (modele_catalogue_dim_depot.sql), déplacé ici pour que le dossier catalogue/ contienne
-- une fiche par table ; il a servi de gabarit aux quatre autres.
-- Rôle : TRANSFORMER, propriétaire de la table. Rejouable : COMMENT et SET TAG remplacent la valeur précédente.
-- À savoir : une table recréée (CREATE OR REPLACE TABLE) perd ses descriptions et ses tags ; c'est pourquoi le
-- catalogue s'écrit dans des fichiers SQL rejouables, et non à la main dans l'interface.
-- C'est bon quand : la première requête finale affiche 4 colonnes, toutes avec une description ;
-- la seconde affiche, pour chaque colonne, les 2 tags de table dont elle hérite (level = TABLE).
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- 1. La table : ce qu'elle contient, d'où elle vient, à quel rythme elle change
COMMENT ON TABLE NYC_TAXI.MARTS.DIM_DEPOT IS
  'Référentiel des dépôts de Hudson Cab Partners : 1 ligne = 1 dépôt (3 lignes). Source : fichier dim_depot.sql, tenu par l''équipe data. Change seulement à l''ouverture ou à la fermeture d''un dépôt. Responsable : équipe data.';

-- 2. Chaque colonne : sa signification, pas son nom répété
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DEPOT.depot     IS 'Nom du dépôt, tel qu''il doit être écrit partout : Bronx, Brooklyn ou Queens. Clé de la table.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DEPOT.quartier  IS 'Quartier où se trouve le garage.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DEPOT.ouvert_en IS 'Année d''ouverture du dépôt.';
COMMENT ON COLUMN NYC_TAXI.MARTS.DIM_DEPOT.nb_places IS 'Nombre de taxis que le garage peut accueillir.';

-- 3. Les tags : la sensibilité et la durée de conservation se posent sur la table (les colonnes en héritent)
ALTER TABLE NYC_TAXI.MARTS.DIM_DEPOT SET TAG
  NYC_TAXI.GOUVERNANCE.SENSIBILITE        = 'interne',
  NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION = 'sans limite : référentiel de l''entreprise';

-- Aucune colonne de cette table ne décrit une personne : le tag DONNEE_PERSONNELLE n'est pas posé.
-- Sur une colonne qui en contient, il se pose ainsi :
--   ALTER TABLE <table> MODIFY COLUMN <colonne> SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'email';

-- 4. Vérifier
SELECT column_name, comment FROM NYC_TAXI.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'MARTS' AND table_name = 'DIM_DEPOT' ORDER BY ordinal_position;

SELECT level, column_name, tag_name, tag_value
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.MARTS.DIM_DEPOT', 'table'));
