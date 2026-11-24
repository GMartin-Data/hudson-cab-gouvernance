-- =====================================================================
-- 04_acces_depot.sql — l'accès par ligne : qui voit quel dépôt. La règle est en DONNÉES, dans la table de
-- correspondance GOUVERNANCE.ACCES_DEPOT (role_name, depot ; contrat, section 1), et la politique RAP_DEPOT la lit
-- pour chaque ligne de DIM_DRIVER et de MART_DRIVER_MONTHLY : la ligne existe pour le lecteur si son rôle actif a
-- le dépôt de la ligne, ou '*' (tous). Un dépôt de plus, un rôle de plus : une ligne de plus, la politique ne change pas.
-- Le rôle des outils y figure avec '*' : sans lui, le pipeline relirait zéro ligne et reconstruirait le mart vide, sans erreur.
-- Un rôle absent de la table (ACCOUNTADMIN, SYSADMIN, GOUVERNANCE…) ne voit aucune ligne, sans erreur (contrat).
-- Rôle : GOUVERNANCE (propriétaire de la table et de la politique, APPLY ROW ACCESS POLICY sur le compte). La
-- sous-requête de la politique lit ACCES_DEPOT avec les droits de GOUVERNANCE : les rôles métier n'y ont aucun accès.
-- Rejouable : CREATE IF NOT EXISTS, INSERT OVERWRITE (la liste complète est ici, le fichier fait foi), corps
-- provisoire FALSE puis SET BODY, attachement seulement s'il n'est pas déjà fait (ADD échouerait au second passage).
-- C'est bon quand : la requête finale affiche 2 lignes (DIM_DRIVER, MART_DRIVER_MONTHLY), ref_arg_column_names
-- [ "DEPOT" ], policy_status ACTIVE ; puis snowflake/verif/04_verif_acces.sql sans KO.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE GOUVERNANCE;
USE WAREHOUSE NYC_TAXI_WH;

-- ===================================================================== 1. La table de correspondance
CREATE TABLE IF NOT EXISTS NYC_TAXI.GOUVERNANCE.ACCES_DEPOT (
    role_name STRING NOT NULL COMMENT 'Rôle Snowflake, comparé au rôle actif (CURRENT_ROLE()) du lecteur',
    depot     STRING NOT NULL COMMENT 'Dépôt visible, tel qu''écrit dans DIM_DRIVER.depot (Bronx, Brooklyn, Queens), ou * pour tous'
)
COMMENT = 'Quel rôle voit quel dépôt (contrat, section 1). Lue par la politique RAP_DEPOT. Ouvrir un dépôt à un rôle = une ligne de plus, sans toucher à la politique.';

-- Vide et remplit en une seule transaction : jamais de table à moitié vide pour la politique qui la lit.
INSERT OVERWRITE INTO NYC_TAXI.GOUVERNANCE.ACCES_DEPOT (role_name, depot) VALUES
    ('TRANSFORMER',       '*'),        -- le rôle des outils voit tout, sinon il écrit un mart vide
    ('RH_PAIE',           '*'),
    ('ANALYSTE',          '*'),
    ('RESP_DEPOT_QUEENS', 'Queens'),
    ('RESP_DEPOT_BRONX',  'Bronx');
    -- Brooklyn : aucun rôle ne le réclame aujourd'hui ; un responsable de plus serait une ligne de plus.

-- ===================================================================== 2. La politique : appelée pour chaque ligne lue, avec la valeur de sa colonne depot
-- Corps provisoire FALSE : entre création et SET BODY, personne ne voit rien plutôt que tout le monde voit tout.
CREATE ROW ACCESS POLICY IF NOT EXISTS NYC_TAXI.GOUVERNANCE.RAP_DEPOT
  AS (depot_ligne STRING) RETURNS BOOLEAN -> FALSE
  COMMENT = 'Une ligne est visible si ACCES_DEPOT donne au rôle actif le dépôt de la ligne, ou * (tous)';

ALTER ROW ACCESS POLICY NYC_TAXI.GOUVERNANCE.RAP_DEPOT SET BODY ->
  EXISTS (
    SELECT 1
    FROM NYC_TAXI.GOUVERNANCE.ACCES_DEPOT a
    WHERE a.role_name = CURRENT_ROLE()          -- le rôle actif, comme le masquage : ni hiérarchie, ni rôles secondaires
      AND a.depot IN (depot_ligne, '*')
  );

-- ===================================================================== 3. Attacher à DIM_DRIVER et MART_DRIVER_MONTHLY, une seule fois
-- POLICY_REFERENCES(POLICY_NAME => …) dit où la politique est déjà attachée. On n'attache que les tables qui manquent :
-- pas de DROP ALL ROW ACCESS POLICIES (fenêtre où tout le monde verrait tout, et détacherait une politique inconnue).
EXECUTE IMMEDIATE $$
DECLARE
  sur_dim  INTEGER;
  sur_mart INTEGER;
BEGIN
  SELECT COUNT(*) INTO :sur_dim
  FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.RAP_DEPOT'))
  WHERE ref_schema_name = 'MARTS' AND ref_entity_name = 'DIM_DRIVER';
  SELECT COUNT(*) INTO :sur_mart
  FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.RAP_DEPOT'))
  WHERE ref_schema_name = 'MARTS' AND ref_entity_name = 'MART_DRIVER_MONTHLY';
  IF (sur_dim = 0) THEN
    ALTER TABLE NYC_TAXI.MARTS.DIM_DRIVER ADD ROW ACCESS POLICY NYC_TAXI.GOUVERNANCE.RAP_DEPOT ON (depot);
  END IF;
  IF (sur_mart = 0) THEN
    ALTER TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY ADD ROW ACCESS POLICY NYC_TAXI.GOUVERNANCE.RAP_DEPOT ON (depot);
  END IF;
  RETURN 'RAP_DEPOT : DIM_DRIVER ' || IFF(sur_dim = 0, 'attachée', 'déjà attachée')
      || ', MART_DRIVER_MONTHLY ' || IFF(sur_mart = 0, 'attachée', 'déjà attachée') || '.';
END;
$$;

-- ===================================================================== Vérifier : 2 lignes, colonne DEPOT, ACTIVE
SELECT policy_name, ref_schema_name, ref_entity_name, ref_arg_column_names, policy_status
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.RAP_DEPOT'))
ORDER BY ref_entity_name;
