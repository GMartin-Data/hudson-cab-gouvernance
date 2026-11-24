-- =====================================================================
-- 02_roles_metier.sql — les quatre rôles métier du contrat (section 4) et leurs droits de LECTURE sur MARTS.
-- Ce script dit qui a le droit d'ouvrir quelles tables ; ce que chacun y voit (lignes, valeurs) est l'affaire
-- des politiques de 03_masquage.sql et 04_acces_depot.sql. Sans politique, un rôle qui lit DIM_DRIVER voit tout :
-- ne pas donner ces rôles à d'autres utilisateurs avant la fin du jour 2.
-- Rôle : ACCOUNTADMIN, seul à pouvoir donner des droits sur les objets FUTURS (et à distribuer les droits sur des
-- tables qu'il ne possède pas). Rejouable (IF NOT EXISTS, GRANT idempotents). Aucune instruction destructive.
-- C'est bon quand : SHOW GRANTS TO ROLE ANALYSTE affiche 3 USAGE, 3 SELECT sur MARTS et 1 USAGE sur GOUVERNANCE,
-- et snowflake/verif/03_verif_roles.sql affiche OK sur toutes ses lignes.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE NYC_TAXI_WH;
SET moi = CURRENT_USER();

-- ===================================================================== 1. Les rôles (noms imposés par le contrat)
CREATE ROLE IF NOT EXISTS RH_PAIE
  COMMENT = 'Service paie : le domaine RH dans MARTS, tous les dépôts, tout en clair';
CREATE ROLE IF NOT EXISTS RESP_DEPOT_QUEENS
  COMMENT = 'Responsable du dépôt de Queens : ses chauffeurs seulement ; nom, prénom et téléphone en clair';
CREATE ROLE IF NOT EXISTS RESP_DEPOT_BRONX
  COMMENT = 'Responsable du dépôt du Bronx : ses chauffeurs seulement ; nom, prénom et téléphone en clair';
CREATE ROLE IF NOT EXISTS ANALYSTE
  COMMENT = 'Analyste : tout MARTS, tous les dépôts, aucune donnée identifiante en clair, année de naissance seulement';

-- ===================================================================== 2. Hiérarchie : à SYSADMIN (administrables), à l'utilisateur courant (testables par USE ROLE)
-- Les politiques du jour 2 lisent CURRENT_ROLE() : SYSADMIN hérite des DROITS de lecture, pas de la vision en clair.
GRANT ROLE RH_PAIE           TO ROLE SYSADMIN;
GRANT ROLE RESP_DEPOT_QUEENS TO ROLE SYSADMIN;
GRANT ROLE RESP_DEPOT_BRONX  TO ROLE SYSADMIN;
GRANT ROLE ANALYSTE          TO ROLE SYSADMIN;

GRANT ROLE RH_PAIE           TO USER IDENTIFIER($moi);
GRANT ROLE RESP_DEPOT_QUEENS TO USER IDENTIFIER($moi);
GRANT ROLE RESP_DEPOT_BRONX  TO USER IDENTIFIER($moi);
GRANT ROLE ANALYSTE          TO USER IDENTIFIER($moi);

-- ===================================================================== 3. Le chemin jusqu'aux tables : warehouse, base, schéma MARTS
-- Sans USAGE sur le warehouse, un rôle échoue avec « no active warehouse », pas « not authorized » : un test de refus serait un faux vert.
GRANT USAGE ON WAREHOUSE NYC_TAXI_WH TO ROLE RH_PAIE;
GRANT USAGE ON WAREHOUSE NYC_TAXI_WH TO ROLE RESP_DEPOT_QUEENS;
GRANT USAGE ON WAREHOUSE NYC_TAXI_WH TO ROLE RESP_DEPOT_BRONX;
GRANT USAGE ON WAREHOUSE NYC_TAXI_WH TO ROLE ANALYSTE;

GRANT USAGE ON DATABASE NYC_TAXI TO ROLE RH_PAIE;
GRANT USAGE ON DATABASE NYC_TAXI TO ROLE RESP_DEPOT_QUEENS;
GRANT USAGE ON DATABASE NYC_TAXI TO ROLE RESP_DEPOT_BRONX;
GRANT USAGE ON DATABASE NYC_TAXI TO ROLE ANALYSTE;

GRANT USAGE ON SCHEMA NYC_TAXI.MARTS TO ROLE RH_PAIE;
GRANT USAGE ON SCHEMA NYC_TAXI.MARTS TO ROLE RESP_DEPOT_QUEENS;
GRANT USAGE ON SCHEMA NYC_TAXI.MARTS TO ROLE RESP_DEPOT_BRONX;
GRANT USAGE ON SCHEMA NYC_TAXI.MARTS TO ROLE ANALYSTE;

-- ===================================================================== 4. La lecture : les deux tables RH et le référentiel des dépôts
GRANT SELECT ON TABLE NYC_TAXI.MARTS.DIM_DRIVER          TO ROLE RH_PAIE;
GRANT SELECT ON TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY TO ROLE RH_PAIE;
GRANT SELECT ON TABLE NYC_TAXI.MARTS.DIM_DEPOT           TO ROLE RH_PAIE;

GRANT SELECT ON TABLE NYC_TAXI.MARTS.DIM_DRIVER          TO ROLE RESP_DEPOT_QUEENS;
GRANT SELECT ON TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY TO ROLE RESP_DEPOT_QUEENS;
GRANT SELECT ON TABLE NYC_TAXI.MARTS.DIM_DEPOT           TO ROLE RESP_DEPOT_QUEENS;

GRANT SELECT ON TABLE NYC_TAXI.MARTS.DIM_DRIVER          TO ROLE RESP_DEPOT_BRONX;
GRANT SELECT ON TABLE NYC_TAXI.MARTS.MART_DRIVER_MONTHLY TO ROLE RESP_DEPOT_BRONX;
GRANT SELECT ON TABLE NYC_TAXI.MARTS.DIM_DEPOT           TO ROLE RESP_DEPOT_BRONX;

-- L'analyste lit tout MARTS, y compris les tables de demain : sans le droit futur, elle perdrait toute table
-- que le pipeline recréerait (ON FUTURE ne couvre pas les tables existantes, d'où les deux instructions).
GRANT SELECT ON ALL    TABLES IN SCHEMA NYC_TAXI.MARTS TO ROLE ANALYSTE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA NYC_TAXI.MARTS TO ROLE ANALYSTE;

-- ===================================================================== 5. Le catalogue du jour 3 : voir le schéma GOUVERNANCE et lire ses vues futures (V_CATALOGUE)
-- Vues futures seulement : les tables de GOUVERNANCE (ACCES_DEPOT, QUALITE_RESULTATS) restent fermées aux rôles métier.
GRANT USAGE ON SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE RH_PAIE;
GRANT USAGE ON SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE RESP_DEPOT_QUEENS;
GRANT USAGE ON SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE RESP_DEPOT_BRONX;
GRANT USAGE ON SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE ANALYSTE;

GRANT SELECT ON FUTURE VIEWS IN SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE RH_PAIE;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE RESP_DEPOT_QUEENS;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE RESP_DEPOT_BRONX;
GRANT SELECT ON FUTURE VIEWS IN SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE ANALYSTE;

-- ===================================================================== Vérifier : 3 USAGE (warehouse, base, MARTS), 3 SELECT sur MARTS, 1 USAGE sur GOUVERNANCE
SHOW GRANTS TO ROLE ANALYSTE;
