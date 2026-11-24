-- =====================================================================
-- 03_masquage.sql — les politiques de masquage, attachées au tag DONNEE_PERSONNELLE : toute colonne qui porte
-- le tag, aujourd'hui ou demain, est protégée d'un coup, dans RAW comme dans MARTS. Une politique par type de
-- colonne taguée : MASK_TEXTE (six colonnes texte) et MASK_DATE (birth_date). Sans MASK_DATE, la date de
-- naissance sortirait en clair, sans erreur : un tag n'applique que la politique dont le type correspond.
-- Ce que chaque rôle voit (contrat, section 4), lu dans la politique par CURRENT_ROLE() et par la valeur du tag :
--   TRANSFORMER, RH_PAIE : tout en clair ;  RESP_DEPOT_* : nom, prénom, téléphone, driver_id ;
--   ANALYSTE : driver_id et l'année de naissance ;  tout autre rôle (ACCOUNTADMIN, SYSADMIN…) : rien.
-- Rôle : GOUVERNANCE (propriétaire du schéma et du tag, APPLY MASKING POLICY sur le compte). Rejouable :
-- CREATE IF NOT EXISTS avec un corps provisoire qui masque tout, puis ALTER … SET BODY (fonctionne même attachée) ;
-- attachement au tag seulement s'il n'est pas déjà fait (ALTER TAG … SET MASKING POLICY n'a pas de IF NOT EXISTS).
-- C'est bon quand : la requête finale affiche 17 lignes ACTIVE, toutes via le tag DONNEE_PERSONNELLE : 15 MASK_TEXTE
-- et 2 MASK_DATE (birth_date de RAW.DRIVERS et de DIM_DRIVER), sur les quatre tables RH (RAW.DRIVERS 7,
-- RAW.DRIVER_SHIFTS 1, DIM_DRIVER 7, MART_DRIVER_MONTHLY 2) ; puis snowflake/verif/04_verif_acces.sql sans KO
-- (une fois 04_acces_depot.sql passé aussi : la requête liste alors en plus ses 2 lignes RAP_DEPOT, 19 au total).
-- Au second passage, le bloc 3 répond « déjà attachée » deux fois.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE GOUVERNANCE;
USE WAREHOUSE NYC_TAXI_WH;

-- ===================================================================== 1. MASK_TEXTE : les six colonnes texte taguées
-- Corps provisoire : tout masqué. Entre la création et SET BODY, personne ne voit rien plutôt que tout le monde voit tout.
CREATE MASKING POLICY IF NOT EXISTS NYC_TAXI.GOUVERNANCE.MASK_TEXTE
  AS (val STRING) RETURNS STRING -> '*****'
  COMMENT = 'Colonnes texte taguées DONNEE_PERSONNELLE : qui voit quoi selon le rôle actif et la valeur du tag (contrat, section 4)';

ALTER MASKING POLICY NYC_TAXI.GOUVERNANCE.MASK_TEXTE SET BODY ->
  CASE
    -- Le rôle des outils lit pour écrire : s'il lisait un masque, il le recopierait dans MARTS. La paie voit tout.
    WHEN CURRENT_ROLE() IN ('TRANSFORMER', 'RH_PAIE')
      THEN val
    -- driver_id reste visible des rôles métier (contrat) : compter et joindre sans nommer. Pas des administrateurs.
    WHEN CURRENT_ROLE() IN ('ANALYSTE', 'RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX')
         AND SYSTEM$GET_TAG_ON_CURRENT_COLUMN('NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE') = 'identifiant_interne'
      THEN val
    -- Les responsables de dépôt appellent leurs chauffeurs : nom, prénom et téléphone en clair.
    WHEN CURRENT_ROLE() IN ('RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX')
         AND SYSTEM$GET_TAG_ON_CURRENT_COLUMN('NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE') IN ('nom', 'telephone')
      THEN val
    -- E-mail, pour les rôles de la matrice seulement : la partie locale disparaît, le domaine reste (il ne désigne
    -- personne). Sans @ (des adresses du fichier sont invalides, règle email_valide du jour 3), il n'y a pas de
    -- domaine à garder : masque complet. Motif .*@ et non .+@ : une partie locale vide (« @domaine ») sortirait sinon telle quelle.
    WHEN CURRENT_ROLE() IN ('ANALYSTE', 'RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX')
         AND SYSTEM$GET_TAG_ON_CURRENT_COLUMN('NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE') = 'email' AND val LIKE '%@%'
      THEN REGEXP_REPLACE(val, '.*@', '*****@')
    -- Tout le reste, pour tout autre rôle (ACCOUNTADMIN, SYSADMIN… : « rien », pas même un domaine) : un masque
    -- constant, qui remplace aussi les NULL.
    ELSE '*****'
  END;

-- ===================================================================== 2. MASK_DATE : birth_date, la seule colonne DATE taguée
-- Une politique renvoie le type qu'elle reçoit : pas d'étoiles pour une date. Corps provisoire : absente.
CREATE MASKING POLICY IF NOT EXISTS NYC_TAXI.GOUVERNANCE.MASK_DATE
  AS (val DATE) RETURNS DATE -> CAST(NULL AS DATE)
  COMMENT = 'Dates taguées DONNEE_PERSONNELLE : complète pour les outils et la paie, année seule pour l''analyste, absente sinon';

ALTER MASKING POLICY NYC_TAXI.GOUVERNANCE.MASK_DATE SET BODY ->
  CASE
    WHEN CURRENT_ROLE() IN ('TRANSFORMER', 'RH_PAIE')
      THEN val
    -- L'analyse n'a besoin que de l'année (fiche de catalogue, jour 1) : le 1er janvier de l'année de naissance.
    WHEN CURRENT_ROLE() = 'ANALYSTE'
      THEN DATE_TRUNC('YEAR', val)
    -- Personne d'autre n'a d'usage de cette date : absente, plutôt qu'une fausse date qui entrerait dans un calcul d'âge.
    ELSE NULL
  END;

-- ===================================================================== 3. Attacher les deux politiques au tag, une seule fois
-- POLICY_REFERENCES(POLICY_NAME => …) décrit une politique attachée à un tag par UNE ligne de domaine TAG (pas une
-- par colonne protégée : celles-là se lisent par table, requête finale). Si cette ligne existe, l'attachement
-- est fait et le rejouer échouerait (ALTER TAG … SET MASKING POLICY n'a pas de IF NOT EXISTS).
EXECUTE IMMEDIATE $$
DECLARE
  texte_attachee INTEGER;
  date_attachee  INTEGER;
BEGIN
  SELECT COUNT(*) INTO :texte_attachee
  FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.MASK_TEXTE'))
  WHERE ref_entity_domain = 'TAG' AND ref_entity_name = 'DONNEE_PERSONNELLE';
  SELECT COUNT(*) INTO :date_attachee
  FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.MASK_DATE'))
  WHERE ref_entity_domain = 'TAG' AND ref_entity_name = 'DONNEE_PERSONNELLE';
  IF (texte_attachee = 0) THEN
    ALTER TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE SET MASKING POLICY NYC_TAXI.GOUVERNANCE.MASK_TEXTE;
  END IF;
  IF (date_attachee = 0) THEN
    ALTER TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE SET MASKING POLICY NYC_TAXI.GOUVERNANCE.MASK_DATE;
  END IF;
  RETURN 'MASK_TEXTE ' || IFF(texte_attachee = 0, 'attachée', 'déjà attachée')
      || ', MASK_DATE ' || IFF(date_attachee = 0, 'attachée', 'déjà attachée') || ' au tag DONNEE_PERSONNELLE.';
END;
$$;

-- ===================================================================== Vérifier : 17 colonnes protégées via le tag sur les quatre tables RH (15 MASK_TEXTE + 2 MASK_DATE), toutes ACTIVE
-- Lecture par table (requête de la section 7 du contrat) : c'est elle qui montre les colonnes, le tag et le statut.
SELECT 'RAW.DRIVERS' AS tbl, policy_name, ref_column_name, tag_name, policy_status
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.RAW.DRIVERS', REF_ENTITY_DOMAIN => 'TABLE'))
UNION ALL
SELECT 'RAW.DRIVER_SHIFTS', policy_name, ref_column_name, tag_name, policy_status
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.RAW.DRIVER_SHIFTS', REF_ENTITY_DOMAIN => 'TABLE'))
UNION ALL
SELECT 'MARTS.DIM_DRIVER', policy_name, ref_column_name, tag_name, policy_status
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.MARTS.DIM_DRIVER', REF_ENTITY_DOMAIN => 'TABLE'))
UNION ALL
SELECT 'MARTS.MART_DRIVER_MONTHLY', policy_name, ref_column_name, tag_name, policy_status
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.MARTS.MART_DRIVER_MONTHLY', REF_ENTITY_DOMAIN => 'TABLE'))
ORDER BY tbl, policy_name, ref_column_name;
