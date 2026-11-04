-- =====================================================================
-- catalogue_raw_drivers.sql — fiche de catalogue complète de RAW.DRIVERS : description de la table,
-- de chaque colonne, et les trois tags du contrat (SENSIBILITE et DUREE_CONSERVATION sur la table,
-- DONNEE_PERSONNELLE sur chaque colonne personnelle de l'inventaire, docs/REGISTRE.md partie 1).
-- Rôle : TRANSFORMER, propriétaire de la table. Rejouable : COMMENT et SET TAG remplacent la valeur précédente.
-- C'est bon quand : la première requête finale n'affiche aucune colonne sans description ; la seconde affiche
-- 7 lignes level = COLUMN (DONNEE_PERSONNELLE), puis les 2 tags de table hérités par chacune des 12 colonnes (level = TABLE).
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- 1. La table
COMMENT ON TABLE NYC_TAXI.RAW.DRIVERS IS
  'Fichier du personnel chauffeur de Hudson Cab Partners, copié tel quel : 1 ligne = 1 chauffeur (400 lignes), en poste ou parti. Source : data/drivers.csv, fourni par la RH de New York, chargé par COPY INTO sans aucune transformation (casse, espaces et vides d''origine conservés). Rechargé à chaque nouveau fichier RH. Données personnelles directes : à ne lire qu''avec un rôle habilité. Responsable : équipe data de Hudson Cab Europe.';

-- 2. Les colonnes
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.driver_id          IS 'Identifiant interne du chauffeur attribué par la RH (lettre D puis quatre chiffres). Clé de la table et clé de jointure avec les services. Permet de retrouver la personne dans tout l''entrepôt.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.first_name         IS 'Prénom du chauffeur, tel que saisi par la RH.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.last_name          IS 'Nom de famille du chauffeur, tel que saisi par la RH.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.email              IS 'Adresse e-mail professionnelle du chauffeur, non normalisée (casse et espaces d''origine). Peut être absente ou mal formée : contrôlée par la règle email_valide.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.phone              IS 'Numéro de téléphone du chauffeur, au format saisi par la RH. Peut être vide : contrôlé par la règle telephone_renseigne.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.birth_date         IS 'Date de naissance du chauffeur. Seule l''année est utile à l''analyse ; le jour et le mois ne servent qu''à la paie.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.tlc_license_number IS 'Numéro de licence de chauffeur délivré par la Taxi and Limousine Commission de New York. Identifiant officiel : public à New York, mais désigne une personne sans ambiguïté. Unique par chauffeur (règle licence_unique).';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.depot              IS 'Dépôt de rattachement du chauffeur (Bronx, Brooklyn ou Queens), orthographe d''origine, à normaliser en staging. Sert au filtrage par ligne des responsables de dépôt. Donnée personnelle indirecte, hors du vocabulaire du tag.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.hire_date          IS 'Date d''embauche. Donnée personnelle indirecte, hors du vocabulaire du tag ; avec end_date, détermine l''ancienneté.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS.end_date           IS 'Date de fin de contrat ; vide = chauffeur en poste. Point de départ du délai de conservation de 5 ans (règle R1). Donnée personnelle indirecte, hors du vocabulaire du tag.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS._source_file       IS 'Colonne technique : nom du fichier chargé (METADATA$FILENAME). Trace de provenance, pas une donnée personnelle.';
COMMENT ON COLUMN NYC_TAXI.RAW.DRIVERS._loaded_at         IS 'Colonne technique : date et heure du chargement (METADATA$START_SCAN_TIME), dans le fuseau de la session de chargement. Pas une donnée personnelle.';

-- 3. Les tags de table (les colonnes en héritent)
ALTER TABLE NYC_TAXI.RAW.DRIVERS SET TAG
  NYC_TAXI.GOUVERNANCE.SENSIBILITE        = 'confidentiel',
  NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION = '5 ans après la fin du contrat du chauffeur (R1)';

-- 4. Le tag DONNEE_PERSONNELLE, colonne par colonne : c'est lui qui déclenchera le masquage (jour 2)
ALTER TABLE NYC_TAXI.RAW.DRIVERS MODIFY COLUMN driver_id          SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'identifiant_interne';
ALTER TABLE NYC_TAXI.RAW.DRIVERS MODIFY COLUMN first_name         SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'nom';
ALTER TABLE NYC_TAXI.RAW.DRIVERS MODIFY COLUMN last_name          SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'nom';
ALTER TABLE NYC_TAXI.RAW.DRIVERS MODIFY COLUMN email              SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'email';
ALTER TABLE NYC_TAXI.RAW.DRIVERS MODIFY COLUMN phone              SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'telephone';
ALTER TABLE NYC_TAXI.RAW.DRIVERS MODIFY COLUMN birth_date         SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'date_naissance';
ALTER TABLE NYC_TAXI.RAW.DRIVERS MODIFY COLUMN tlc_license_number SET TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE = 'identifiant_officiel';
-- depot, hire_date, end_date : personnelles indirectes selon l'inventaire, mais aucune valeur du tag ne les décrit.
-- Elles ne sont pas taguées ; la table est confidentielle et l'accès par ligne (jour 2) les protège.

-- 5. Vérifier : aucune colonne sans description
SELECT column_name, comment
FROM NYC_TAXI.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'RAW' AND table_name = 'DRIVERS' AND (comment IS NULL OR comment = '')
ORDER BY ordinal_position;

-- Vérifier : 7 lignes level = COLUMN (le tag posé sur la colonne), puis, pour chaque colonne, les 2 tags de table
-- dont elle hérite (level = TABLE, apply_method = INHERITED)
SELECT level, apply_method, column_name, tag_name, tag_value
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('NYC_TAXI.RAW.DRIVERS', 'table'))
ORDER BY level, column_name, tag_name;
