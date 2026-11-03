-- =====================================================================
-- 01_gouvernance.sql — ce qui porte les règles : le rôle GOUVERNANCE, son schéma, les trois tags du contrat,
-- la table QUALITE_RESULTATS, et les droits dont le rôle des outils (TRANSFORMER) aura besoin aux jours 2 et 3.
-- Deux rôles se succèdent : ACCOUNTADMIN pour ce qui touche au compte (créer le rôle, donner les droits
-- « sur le compte », céder la propriété du schéma), puis GOUVERNANCE pour tout le reste.
-- GOUVERNANCE écrit les règles sans lire les données : aucun SELECT sur RAW, STAGING ou MARTS.
-- Rejouable (IF NOT EXISTS, GRANT idempotents).
-- C'est bon quand : SHOW TAGS IN SCHEMA NYC_TAXI.GOUVERNANCE affiche 3 lignes,
-- et snowflake/verif/01_verif_gouvernance.sql affiche OK sur toutes ses lignes.
-- =====================================================================

-- ===================================================================== 1. Avec ACCOUNTADMIN : le rôle et les droits sur le compte
USE SECONDARY ROLES NONE;
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE NYC_TAXI_WH;
SET moi = CURRENT_USER();

CREATE ROLE IF NOT EXISTS GOUVERNANCE
  COMMENT = 'Écrit les règles de gouvernance (tags, politiques, qualité) sans lire les données';
GRANT ROLE GOUVERNANCE TO ROLE SYSADMIN;
GRANT ROLE GOUVERNANCE TO USER IDENTIFIER($moi);

-- Voir la base, le warehouse et les schémas des données : pour trouver les tables auxquelles attacher
-- les politiques, sans pouvoir les lire (USAGE sur un schéma ne donne aucun SELECT).
GRANT USAGE ON DATABASE  NYC_TAXI        TO ROLE GOUVERNANCE;
GRANT USAGE ON WAREHOUSE NYC_TAXI_WH     TO ROLE GOUVERNANCE;
GRANT USAGE ON SCHEMA    NYC_TAXI.RAW    TO ROLE GOUVERNANCE;
GRANT USAGE ON SCHEMA    NYC_TAXI.MARTS  TO ROLE GOUVERNANCE;

-- Le schéma des règles : créé par ACCOUNTADMIN, puis cédé à GOUVERNANCE, qui en devient propriétaire.
CREATE SCHEMA IF NOT EXISTS NYC_TAXI.GOUVERNANCE
  COMMENT = 'Tags, politiques de masquage et d''accès, résultats de qualité, catalogue';
GRANT OWNERSHIP ON SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE GOUVERNANCE COPY CURRENT GRANTS;

-- Attacher une politique à une table qu'on ne possède pas : un droit qui ne peut venir que du compte.
GRANT APPLY MASKING POLICY    ON ACCOUNT TO ROLE GOUVERNANCE;
GRANT APPLY ROW ACCESS POLICY ON ACCOUNT TO ROLE GOUVERNANCE;

-- ===================================================================== 2. Avec GOUVERNANCE : les tags du contrat (section 3)
USE ROLE GOUVERNANCE;
USE WAREHOUSE NYC_TAXI_WH;

CREATE TAG IF NOT EXISTS NYC_TAXI.GOUVERNANCE.SENSIBILITE
  ALLOWED_VALUES 'public', 'interne', 'confidentiel'
  COMMENT = 'Niveau de sensibilité d''une table cataloguée';

CREATE TAG IF NOT EXISTS NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE
  ALLOWED_VALUES 'nom', 'email', 'telephone', 'date_naissance', 'identifiant_officiel', 'identifiant_interne'
  COMMENT = 'Nature de la donnée personnelle portée par une colonne. Déclenche le masquage (jour 2).';

CREATE TAG IF NOT EXISTS NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION
  COMMENT = 'Durée de conservation d''une table cataloguée, en texte libre (ex. : 5 ans après la fin du contrat)';

-- ===================================================================== 3. Avec GOUVERNANCE : la table des résultats de qualité (section 1)
CREATE TABLE IF NOT EXISTS NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS (
    regle        STRING        COMMENT 'Nom de la règle de qualité (contrat, section 6)',
    mesure_le    TIMESTAMP_NTZ COMMENT 'Date et heure de la mesure',
    nb_anomalies NUMBER        COMMENT 'Nombre de lignes en anomalie',
    seuil        NUMBER(18,2)  COMMENT 'Seuil toléré par le contrat',
    statut       STRING        COMMENT 'OK ou ALERTE'
)
COMMENT = 'Une ligne par exécution d''une règle de qualité (jour 3)';

-- ===================================================================== 4. Avec GOUVERNANCE : ce que le rôle des outils devra pouvoir faire
GRANT USAGE       ON SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE TRANSFORMER;   -- voir le schéma
GRANT CREATE VIEW ON SCHEMA NYC_TAXI.GOUVERNANCE TO ROLE TRANSFORMER;   -- la vue du catalogue (jour 3)
GRANT APPLY ON TAG NYC_TAXI.GOUVERNANCE.SENSIBILITE        TO ROLE TRANSFORMER;   -- poser les tags sur ses tables (étape 11)
GRANT APPLY ON TAG NYC_TAXI.GOUVERNANCE.DONNEE_PERSONNELLE TO ROLE TRANSFORMER;
GRANT APPLY ON TAG NYC_TAXI.GOUVERNANCE.DUREE_CONSERVATION TO ROLE TRANSFORMER;
GRANT INSERT, SELECT ON TABLE NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS TO ROLE TRANSFORMER;   -- les tâches de qualité (jour 3)

-- ===================================================================== Vérifier : 3 tags
SHOW TAGS IN SCHEMA NYC_TAXI.GOUVERNANCE;
