-- =====================================================================
-- 04_verif_acces.sql — le test de 03_masquage.sql et 04_acces_depot.sql, écrit avant eux (jour 2, étapes 3, 5, 6).
-- Ce qui doit être vrai, rôle par rôle, d'après la matrice du contrat (section 4) : le nombre de lignes vues dans
-- DIM_DRIVER et MART_DRIVER_MONTHLY, les colonnes en clair et les colonnes masquées, driver_id visible des rôles
-- métier, l'année de naissance seule pour ANALYSTE, les refus (RAW, STAGING, GOUVERNANCE sur les données),
-- TRANSFORMER qui voit tout en clair (sinon il recopierait des masques), ACCOUNTADMIN et SYSADMIN qui ne voient
-- aucune ligne de MARTS et rien en clair dans RAW, et les politiques attachées là où on les attend, nulle part ailleurs.
-- Rôles : une section par rôle, chacune commence par USE SECONDARY ROLES NONE / USE ROLE / USE WAREHOUSE (réflexes 1 et 2).
-- Les refus sont attendus dans un bloc EXECUTE IMMEDIATE : sans lui, la CLI s'arrête à la première erreur. Le bloc
-- ne compte comme refus que l'erreur « does not exist or not authorized » (code 2003) : une faute de frappe ou un
-- warehouse absent donnent une autre erreur, affichée en KO plutôt que prise pour un refus.
-- Rejouable. Avant 03 et 04 : des lignes KO (valeurs en clair, tous les dépôts visibles), puis une erreur sur
-- ACCES_DEPOT qui n'existe pas encore. C'est bon quand : aucun KO dans la sortie, aucune erreur (la CLI écho le
-- texte des scripts, d'où les espaces autour de KO : ils ne comptent que les cellules de résultat) :
--   snow sql -c hudson_cab -f snowflake/verif/04_verif_acces.sql | grep -c ' KO '   → 0
-- Valeurs de contrôle, les seules constantes du script : 354 chauffeurs et 914 lignes de mart, 3 dépôts,
-- 143 chauffeurs / 365 lignes de mart pour Queens, 106 / 290 pour le Bronx, D0003 rattaché à Queens (relevé avec
-- TRANSFORMER le 2026-11-28). Elles prouvent qu'un rôle voit TOUT ce qu'il doit voir. Avant la purge R1 du jour 3
-- (snowflake/rh/purge_rh.sql, 46 chauffeurs échus, aucune ligne de mart), elles valaient 400, 161 et 122 ; la
-- prochaine échéance R1 tombe le 2028-01-11, elles tiennent jusque-là. Les contrôles de masquage, eux, sont écrits
-- en absolu (zéro valeur non conforme sur les lignes vues) et ne dépendent d'aucun volume.
-- Anomalies du fichier qui comptent ici : les e-mails sans @ (règle email_valide, jour 3) doivent sortir en *****
-- complet, le masque partiel n'ayant pas de domaine à garder ; les téléphones vides doivent sortir en ***** pour
-- qui ne voit pas la colonne en clair (un masque remplace aussi les NULL) ; driver_name est NULL dans le mart pour
-- les services sans chauffeur connu, et seulement pour eux.
-- =====================================================================

-- ===================================================================== RH_PAIE : tout le domaine RH, tous les dépôts, tout en clair
USE SECONDARY ROLES NONE;
USE ROLE RH_PAIE;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'RH_PAIE : DIM_DRIVER, tous les chauffeurs' AS verification, 354 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'RH_PAIE : MART_DRIVER_MONTHLY, toutes les lignes', 914, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'RH_PAIE : DIM_DEPOT, les 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
    UNION ALL SELECT 'RH_PAIE : le chauffeur D0003 (Queens) est visible', 1, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'RH_PAIE : aucune valeur masquée (driver_id, nom, prénom, e-mail, téléphone, licence)', 0,
              (SELECT COUNT(*) FROM d WHERE driver_id = '*****' OR first_name = '*****' OR last_name = '*****'
                                        OR email LIKE '*****%' OR phone = '*****' OR tlc_license_number = '*****')
    UNION ALL SELECT 'RH_PAIE : aucun e-mail NULL (le fichier en donne un par chauffeur, même invalide)', 0,
              (SELECT COUNT(*) FROM d WHERE email IS NULL)
    UNION ALL SELECT 'RH_PAIE : aucune date de naissance NULL', 0, (SELECT COUNT(*) FROM d WHERE birth_date IS NULL)
    -- Une date réduite à l'année donnerait autant de dates distinctes que d'années : la paie doit en voir davantage.
    UNION ALL SELECT 'RH_PAIE : dates de naissance complètes (plus de dates distinctes que d''années distinctes)', 1,
              IFF((SELECT COUNT(DISTINCT birth_date) FROM d) > (SELECT COUNT(DISTINCT YEAR(birth_date)) FROM d), 1, 0)
    -- Un masque remplace aussi les NULL : la paie voit les téléphones vides du fichier tels quels, jamais en *****.
    UNION ALL SELECT 'RH_PAIE : aucun téléphone masqué (les vides du fichier restent NULL)', 0, (SELECT COUNT(*) FROM d WHERE phone = '*****')
    UNION ALL SELECT 'RH_PAIE : driver_name en clair dans le mart, NULL seulement pour les services sans chauffeur connu', 0,
              (SELECT COUNT(*) FROM m WHERE driver_name = '*****' OR (driver_name IS NULL AND driver_id IN (SELECT driver_id FROM d)))
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- Le contrat : personne d'autre que le rôle des outils ne lit RAW ni STAGING.
EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.RAW.DRIVER_SHIFTS;
  RETURN 'KO : RH_PAIE lit RAW.DRIVER_SHIFTS (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN
    RETURN IFF(CONTAINS(SQLERRM, 'does not exist or not authorized'),
               'OK : RAW.DRIVER_SHIFTS refusé à RH_PAIE',
               'KO : erreur inattendue pour RH_PAIE sur RAW.DRIVER_SHIFTS : ' || SQLERRM);
END;
$$;

-- ===================================================================== RESP_DEPOT_QUEENS : Queens seulement ; nom, prénom, téléphone en clair
USE SECONDARY ROLES NONE;
USE ROLE RESP_DEPOT_QUEENS;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'RESP_DEPOT_QUEENS : DIM_DRIVER, les chauffeurs de Queens seulement' AS verification, 143 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : un seul dépôt visible', 1, (SELECT COUNT(DISTINCT depot) FROM d)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : et c''est Queens', 143, (SELECT COUNT(*) FROM d WHERE depot = 'Queens')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : MART_DRIVER_MONTHLY, les lignes de Queens seulement', 365, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : aucune ligne du mart hors de Queens', 0, (SELECT COUNT(*) FROM m WHERE depot IS DISTINCT FROM 'Queens')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : DIM_DEPOT sans filtre, les 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : le chauffeur D0003 (Queens) est visible', 1, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : driver_id, nom, prénom et téléphone en clair (aucun masque)', 0,
              (SELECT COUNT(*) FROM d WHERE driver_id = '*****' OR first_name = '*****' OR last_name = '*****' OR phone = '*****')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : e-mails masqués sur toutes les lignes vues (***** ou *****@<domaine>)', 0,
              (SELECT COUNT(*) FROM d WHERE email IS NULL OR email NOT LIKE '*****%')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : licences TLC masquées sur toutes les lignes vues', 0,
              (SELECT COUNT(*) FROM d WHERE tlc_license_number IS DISTINCT FROM '*****')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : dates de naissance absentes sur toutes les lignes vues', 0,
              (SELECT COUNT(*) FROM d WHERE birth_date IS NOT NULL)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : driver_name en clair dans le mart (aucun masque)', 0, (SELECT COUNT(*) FROM m WHERE driver_name = '*****')
    -- Limite connue, documentée dans docs/ACCES.md : le compte de lignes du catalogue est physique, la politique ne le filtre pas.
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : INFORMATION_SCHEMA.TABLES.row_count de DIM_DRIVER donne le total physique (limite connue)', 354,
              (SELECT row_count FROM NYC_TAXI.INFORMATION_SCHEMA.TABLES WHERE table_schema = 'MARTS' AND table_name = 'DIM_DRIVER')
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.RAW.DRIVERS;
  RETURN 'KO : RESP_DEPOT_QUEENS lit RAW.DRIVERS (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN
    RETURN IFF(CONTAINS(SQLERRM, 'does not exist or not authorized'),
               'OK : RAW.DRIVERS refusé à RESP_DEPOT_QUEENS',
               'KO : erreur inattendue pour RESP_DEPOT_QUEENS sur RAW.DRIVERS : ' || SQLERRM);
END;
$$;

-- ===================================================================== RESP_DEPOT_BRONX : Bronx seulement ; mêmes colonnes en clair
USE SECONDARY ROLES NONE;
USE ROLE RESP_DEPOT_BRONX;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'RESP_DEPOT_BRONX : DIM_DRIVER, les chauffeurs du Bronx seulement' AS verification, 106 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'RESP_DEPOT_BRONX : et c''est le Bronx', 106, (SELECT COUNT(*) FROM d WHERE depot = 'Bronx')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : MART_DRIVER_MONTHLY, les lignes du Bronx seulement', 290, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'RESP_DEPOT_BRONX : aucune ligne du mart hors du Bronx', 0, (SELECT COUNT(*) FROM m WHERE depot IS DISTINCT FROM 'Bronx')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : le chauffeur D0003 (Queens) est invisible', 0, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : driver_id, nom, prénom et téléphone en clair (aucun masque)', 0,
              (SELECT COUNT(*) FROM d WHERE driver_id = '*****' OR first_name = '*****' OR last_name = '*****' OR phone = '*****')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : e-mails masqués sur toutes les lignes vues (***** ou *****@<domaine>)', 0,
              (SELECT COUNT(*) FROM d WHERE email IS NULL OR email NOT LIKE '*****%')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : licences TLC masquées et dates de naissance absentes sur toutes les lignes vues', 0,
              (SELECT COUNT(*) FROM d WHERE tlc_license_number IS DISTINCT FROM '*****' OR birth_date IS NOT NULL)
    UNION ALL SELECT 'RESP_DEPOT_BRONX : driver_name en clair dans le mart (aucun masque)', 0, (SELECT COUNT(*) FROM m WHERE driver_name = '*****')
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.STAGING.STG_RH__DRIVERS;
  RETURN 'KO : RESP_DEPOT_BRONX lit STAGING.STG_RH__DRIVERS (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN
    RETURN IFF(CONTAINS(SQLERRM, 'does not exist or not authorized'),
               'OK : STAGING.STG_RH__DRIVERS refusé à RESP_DEPOT_BRONX',
               'KO : erreur inattendue pour RESP_DEPOT_BRONX sur STAGING.STG_RH__DRIVERS : ' || SQLERRM);
END;
$$;

-- ===================================================================== ANALYSTE : tout MARTS, tous les dépôts, personne n'est nommable, l'année de naissance seule
USE SECONDARY ROLES NONE;
USE ROLE ANALYSTE;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'ANALYSTE : DIM_DRIVER, tous les chauffeurs' AS verification, 354 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'ANALYSTE : MART_DRIVER_MONTHLY, toutes les lignes', 914, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'ANALYSTE : DIM_DEPOT, les 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
    UNION ALL SELECT 'ANALYSTE : driver_id visible, D0003 se retrouve (compter et joindre sans nommer)', 1, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'ANALYSTE : nom, prénom et licence TLC masqués sur toutes les lignes', 0,
              (SELECT COUNT(*) FROM d WHERE first_name IS DISTINCT FROM '*****' OR last_name IS DISTINCT FROM '*****'
                                        OR tlc_license_number IS DISTINCT FROM '*****')
    -- Le masque remplace aussi les NULL : l'analyste ne sait pas qui n'a pas de téléphone.
    UNION ALL SELECT 'ANALYSTE : téléphones masqués sur toutes les lignes, NULL compris', 0, (SELECT COUNT(*) FROM d WHERE phone IS DISTINCT FROM '*****')
    UNION ALL SELECT 'ANALYSTE : e-mails masqués sur toutes les lignes (***** ou *****@<domaine>, jamais la partie locale)', 0,
              (SELECT COUNT(*) FROM d WHERE email IS NULL OR email NOT LIKE '*****%')
    UNION ALL SELECT 'ANALYSTE : le domaine reste lisible (au moins une adresse en *****@<domaine>)', 1,
              IFF((SELECT COUNT(*) FROM d WHERE email LIKE '*****@_%') > 0, 1, 0)
    UNION ALL SELECT 'ANALYSTE : dates de naissance réduites au 1er janvier sur toutes les lignes, aucune NULL', 0,
              (SELECT COUNT(*) FROM d WHERE birth_date IS NULL OR DAYOFYEAR(birth_date) <> 1)
    UNION ALL SELECT 'ANALYSTE : l''année de naissance reste exploitable (plus d''une année distincte)', 1,
              IFF((SELECT COUNT(DISTINCT YEAR(birth_date)) FROM d) > 1, 1, 0)
    UNION ALL SELECT 'ANALYSTE : driver_name masqué sur toutes les lignes du mart, NULL compris', 0, (SELECT COUNT(*) FROM m WHERE driver_name IS DISTINCT FROM '*****')
    UNION ALL SELECT 'ANALYSTE : driver_id visible dans le mart (aucun masque)', 0, (SELECT COUNT(*) FROM m WHERE driver_id = '*****')
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.RAW.DRIVERS;
  RETURN 'KO : ANALYSTE lit RAW.DRIVERS (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN
    RETURN IFF(CONTAINS(SQLERRM, 'does not exist or not authorized'),
               'OK : RAW.DRIVERS refusé à ANALYSTE',
               'KO : erreur inattendue pour ANALYSTE sur RAW.DRIVERS : ' || SQLERRM);
END;
$$;

-- ===================================================================== TRANSFORMER : le rôle des outils voit tout, en clair, sinon il recopie des masques et des NULL
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'TRANSFORMER : DIM_DRIVER, tous les chauffeurs (ACCES_DEPOT le laisse passer)' AS verification, 354 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'TRANSFORMER : MART_DRIVER_MONTHLY, toutes les lignes', 914, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'TRANSFORMER : aucune valeur masquée dans DIM_DRIVER', 0,
              (SELECT COUNT(*) FROM d WHERE driver_id = '*****' OR first_name = '*****' OR last_name = '*****'
                                        OR email LIKE '*****%' OR phone = '*****' OR tlc_license_number = '*****')
    UNION ALL SELECT 'TRANSFORMER : aucune date de naissance NULL', 0, (SELECT COUNT(*) FROM d WHERE birth_date IS NULL)
    UNION ALL SELECT 'TRANSFORMER : dates de naissance complètes (plus de dates distinctes que d''années distinctes)', 1,
              IFF((SELECT COUNT(DISTINCT birth_date) FROM d) > (SELECT COUNT(DISTINCT YEAR(birth_date)) FROM d), 1, 0)
    -- Si TRANSFORMER manquait dans ACCES_DEPOT, le mart se reconstruirait avec driver_name NULL sur toutes les lignes.
    UNION ALL SELECT 'TRANSFORMER : driver_name du mart intact (NULL seulement pour les services sans chauffeur connu)', 0,
              (SELECT COUNT(*) FROM m WHERE driver_name = '*****' OR (driver_name IS NULL AND driver_id IN (SELECT driver_id FROM d)))
    UNION ALL SELECT 'TRANSFORMER : RAW.DRIVERS en clair (aucun masque, aucun e-mail NULL)', 0,
              (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS
               WHERE driver_id = '*****' OR first_name = '*****' OR email IS NULL OR email LIKE '*****%' OR birth_date IS NULL)
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- ===================================================================== ACCOUNTADMIN : hors de la matrice ; aucune ligne de MARTS, rien en clair dans RAW ; et les politiques sont bien là
USE SECONDARY ROLES NONE;
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE NYC_TAXI_WH;

SHOW MASKING POLICIES IN SCHEMA NYC_TAXI.GOUVERNANCE                    -- $2
  ->> SHOW ROW ACCESS POLICIES IN SCHEMA NYC_TAXI.GOUVERNANCE           -- $1
  ->> WITH refs AS (                                                    -- où les politiques sont attachées, pour les quatre tables RH
        SELECT 'MARTS.DIM_DRIVER' AS tbl, policy_name, policy_kind, ref_column_name, ref_arg_column_names, tag_name, policy_status
        FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.MARTS.DIM_DRIVER', REF_ENTITY_DOMAIN => 'TABLE'))
        UNION ALL
        SELECT 'MARTS.MART_DRIVER_MONTHLY', policy_name, policy_kind, ref_column_name, ref_arg_column_names, tag_name, policy_status
        FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.MARTS.MART_DRIVER_MONTHLY', REF_ENTITY_DOMAIN => 'TABLE'))
        UNION ALL
        SELECT 'RAW.DRIVERS', policy_name, policy_kind, ref_column_name, ref_arg_column_names, tag_name, policy_status
        FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.RAW.DRIVERS', REF_ENTITY_DOMAIN => 'TABLE'))
        UNION ALL
        SELECT 'RAW.DRIVER_SHIFTS', policy_name, policy_kind, ref_column_name, ref_arg_column_names, tag_name, policy_status
        FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(REF_ENTITY_NAME => 'NYC_TAXI.RAW.DRIVER_SHIFTS', REF_ENTITY_DOMAIN => 'TABLE'))
      ),
      attendu AS (
        -- Ce qu'il voit : la politique de lignes ne connaît pas ACCOUNTADMIN, le masquage non plus.
        SELECT 'ACCOUNTADMIN : DIM_DRIVER, aucune ligne (absent d''ACCES_DEPOT)' AS verification, 0 AS attendu,
               (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER) AS obtenu
        UNION ALL SELECT 'ACCOUNTADMIN : MART_DRIVER_MONTHLY, aucune ligne', 0, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY)
        UNION ALL SELECT 'ACCOUNTADMIN : DIM_DEPOT, référentiel sans filtre, 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
        -- RAW n'a pas de politique de lignes : les administrateurs voient les lignes (hiérarchie), les colonnes personnelles masquées (contrat, section 4).
        UNION ALL SELECT 'ACCOUNTADMIN : RAW.DRIVERS, 354 lignes visibles par héritage de TRANSFORMER', 354, (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS)
        UNION ALL SELECT 'ACCOUNTADMIN : RAW.DRIVERS, rien en clair (driver_id, nom, prénom, licence, téléphone masqués sur toutes les lignes)', 0,
                  (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS
                   WHERE driver_id IS DISTINCT FROM '*****' OR first_name IS DISTINCT FROM '*****' OR last_name IS DISTINCT FROM '*****'
                      OR tlc_license_number IS DISTINCT FROM '*****' OR phone IS DISTINCT FROM '*****')
        -- « Rien » (contrat) : pas même le domaine de l'e-mail, réservé aux rôles de la matrice.
        UNION ALL SELECT 'ACCOUNTADMIN : RAW.DRIVERS, e-mails entièrement masqués (*****, pas même le domaine) et dates absentes', 0,
                  (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS WHERE email IS DISTINCT FROM '*****' OR birth_date IS NOT NULL)
        -- Les politiques existent, appartiennent à GOUVERNANCE, et sont attachées là où on les attend.
        UNION ALL SELECT 'Politiques de masquage : MASK_TEXTE et MASK_DATE, propriété de GOUVERNANCE', 2,
                  (SELECT COUNT(*) FROM $2 WHERE "name" IN ('MASK_TEXTE', 'MASK_DATE') AND "owner" = 'GOUVERNANCE')
        UNION ALL SELECT 'Politique de lignes : RAP_DEPOT, propriété de GOUVERNANCE', 1,
                  (SELECT COUNT(*) FROM $1 WHERE "name" = 'RAP_DEPOT' AND "owner" = 'GOUVERNANCE')
        UNION ALL SELECT 'DIM_DRIVER : 7 colonnes masquées par le tag DONNEE_PERSONNELLE (6 MASK_TEXTE + 1 MASK_DATE), ACTIVE', 7,
                  (SELECT COUNT(*) FROM refs WHERE tbl = 'MARTS.DIM_DRIVER' AND policy_kind = 'MASKING_POLICY'
                                               AND tag_name = 'DONNEE_PERSONNELLE' AND policy_status = 'ACTIVE')
        UNION ALL SELECT 'DIM_DRIVER : birth_date protégée par MASK_DATE (une politique par type)', 1,
                  (SELECT COUNT(*) FROM refs WHERE tbl = 'MARTS.DIM_DRIVER' AND policy_name = 'MASK_DATE' AND ref_column_name = 'BIRTH_DATE')
        UNION ALL SELECT 'DIM_DRIVER : RAP_DEPOT attachée sur la colonne depot, ACTIVE', 1,
                  (SELECT COUNT(*) FROM refs WHERE tbl = 'MARTS.DIM_DRIVER' AND policy_kind = 'ROW_ACCESS_POLICY' AND policy_name = 'RAP_DEPOT'
                                               AND ref_arg_column_names LIKE '%DEPOT%' AND policy_status = 'ACTIVE')
        UNION ALL SELECT 'MART_DRIVER_MONTHLY : driver_id et driver_name masqués par le tag, ACTIVE', 2,
                  (SELECT COUNT(*) FROM refs WHERE tbl = 'MARTS.MART_DRIVER_MONTHLY' AND policy_kind = 'MASKING_POLICY'
                                               AND tag_name = 'DONNEE_PERSONNELLE' AND policy_status = 'ACTIVE')
        UNION ALL SELECT 'MART_DRIVER_MONTHLY : RAP_DEPOT attachée sur la colonne depot, ACTIVE', 1,
                  (SELECT COUNT(*) FROM refs WHERE tbl = 'MARTS.MART_DRIVER_MONTHLY' AND policy_kind = 'ROW_ACCESS_POLICY' AND policy_name = 'RAP_DEPOT'
                                               AND ref_arg_column_names LIKE '%DEPOT%' AND policy_status = 'ACTIVE')
        UNION ALL SELECT 'RAW.DRIVERS : 7 colonnes masquées par le tag, ACTIVE', 7,
                  (SELECT COUNT(*) FROM refs WHERE tbl = 'RAW.DRIVERS' AND policy_kind = 'MASKING_POLICY'
                                               AND tag_name = 'DONNEE_PERSONNELLE' AND policy_status = 'ACTIVE')
        UNION ALL SELECT 'RAW.DRIVER_SHIFTS : driver_id masqué par le tag, ACTIVE', 1,
                  (SELECT COUNT(*) FROM refs WHERE tbl = 'RAW.DRIVER_SHIFTS' AND policy_kind = 'MASKING_POLICY'
                                               AND tag_name = 'DONNEE_PERSONNELLE' AND policy_status = 'ACTIVE')
        -- Sur ces quatre tables seulement ; « nulle part ailleurs » se lit par politique, dans la section GOUVERNANCE.
        UNION ALL SELECT 'Les quatre tables RH : 17 masquages via le tag + 2 politiques de lignes = 19 références', 19,
                  (SELECT COUNT(*) FROM refs)
      )
      SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
      FROM attendu ORDER BY statut, verification;

-- ===================================================================== SYSADMIN : nommé par le contrat avec ACCOUNTADMIN ; hérite des droits de lecture, pas de la vision en clair
USE SECONDARY ROLES NONE;
USE ROLE SYSADMIN;
USE WAREHOUSE NYC_TAXI_WH;

WITH attendu AS (
    -- Il hérite de TRANSFORMER et de RH_PAIE (02_roles_metier.sql), mais les politiques lisent le rôle ACTIF : SYSADMIN n'est ni dans ACCES_DEPOT ni dans les politiques.
    SELECT 'SYSADMIN : DIM_DRIVER, aucune ligne (hérite de RH_PAIE et de TRANSFORMER, mais absent d''ACCES_DEPOT)' AS verification, 0 AS attendu,
           (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER) AS obtenu
    UNION ALL SELECT 'SYSADMIN : MART_DRIVER_MONTHLY, aucune ligne', 0, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY)
    UNION ALL SELECT 'SYSADMIN : DIM_DEPOT, référentiel sans filtre, 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
    UNION ALL SELECT 'SYSADMIN : RAW.DRIVERS, 354 lignes visibles par héritage de TRANSFORMER', 354, (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS)
    UNION ALL SELECT 'SYSADMIN : RAW.DRIVERS, rien en clair (identifiants, nom, prénom, licence, téléphone, e-mail masqués, dates absentes)', 0,
              (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS
               WHERE driver_id IS DISTINCT FROM '*****' OR first_name IS DISTINCT FROM '*****' OR last_name IS DISTINCT FROM '*****'
                  OR tlc_license_number IS DISTINCT FROM '*****' OR phone IS DISTINCT FROM '*****'
                  OR email IS DISTINCT FROM '*****' OR birth_date IS NOT NULL)
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- ===================================================================== GOUVERNANCE : écrit les règles, ne lit aucune donnée ; lit sa table de correspondance et recense ses politiques
USE SECONDARY ROLES NONE;
USE ROLE GOUVERNANCE;
USE WAREHOUSE NYC_TAXI_WH;

EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.MARTS.DIM_DRIVER;
  RETURN 'KO : GOUVERNANCE lit MARTS.DIM_DRIVER (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN
    RETURN IFF(CONTAINS(SQLERRM, 'does not exist or not authorized'),
               'OK : MARTS.DIM_DRIVER refusé à GOUVERNANCE',
               'KO : erreur inattendue pour GOUVERNANCE sur MARTS.DIM_DRIVER : ' || SQLERRM);
END;
$$;

EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.RAW.DRIVERS;
  RETURN 'KO : GOUVERNANCE lit RAW.DRIVERS (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN
    RETURN IFF(CONTAINS(SQLERRM, 'does not exist or not authorized'),
               'OK : RAW.DRIVERS refusé à GOUVERNANCE',
               'KO : erreur inattendue pour GOUVERNANCE sur RAW.DRIVERS : ' || SQLERRM);
END;
$$;

-- La table de correspondance : la règle « qui voit quel dépôt » est en données, pas dans la politique.
-- Et le recensement par politique (POLICY_NAME =>, réservé au propriétaire) : chacune est attachée là où on l'attend, et nulle part ailleurs.
WITH refs AS (
    SELECT 'MASK_TEXTE' AS politique, ref_entity_domain, ref_schema_name, ref_entity_name
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.MASK_TEXTE'))
    UNION ALL
    SELECT 'MASK_DATE', ref_entity_domain, ref_schema_name, ref_entity_name
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.MASK_DATE'))
    UNION ALL
    SELECT 'RAP_DEPOT', ref_entity_domain, ref_schema_name, ref_entity_name
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.POLICY_REFERENCES(POLICY_NAME => 'NYC_TAXI.GOUVERNANCE.RAP_DEPOT'))
),
attendu AS (
    SELECT 'ACCES_DEPOT : 5 lignes (TRANSFORMER, RH_PAIE, ANALYSTE = tous ; QUEENS = Queens ; BRONX = Bronx)' AS verification, 5 AS attendu,
           (SELECT COUNT(*) FROM NYC_TAXI.GOUVERNANCE.ACCES_DEPOT) AS obtenu
    UNION ALL SELECT 'ACCES_DEPOT : TRANSFORMER voit tous les dépôts (*), sinon le mart se reconstruit vide', 1,
              (SELECT COUNT(*) FROM NYC_TAXI.GOUVERNANCE.ACCES_DEPOT WHERE role_name = 'TRANSFORMER' AND depot = '*')
    UNION ALL SELECT 'ACCES_DEPOT : RH_PAIE et ANALYSTE voient tous les dépôts (*)', 2,
              (SELECT COUNT(*) FROM NYC_TAXI.GOUVERNANCE.ACCES_DEPOT WHERE role_name IN ('RH_PAIE', 'ANALYSTE') AND depot = '*')
    UNION ALL SELECT 'ACCES_DEPOT : chaque responsable voit son seul dépôt', 2,
              (SELECT COUNT(*) FROM NYC_TAXI.GOUVERNANCE.ACCES_DEPOT
               WHERE (role_name, depot) IN (('RESP_DEPOT_QUEENS', 'Queens'), ('RESP_DEPOT_BRONX', 'Bronx')))
    UNION ALL SELECT 'ACCES_DEPOT : aucune ligne pour un rôle hors de la matrice (ACCOUNTADMIN, SYSADMIN, GOUVERNANCE, PUBLIC)', 0,
              (SELECT COUNT(*) FROM NYC_TAXI.GOUVERNANCE.ACCES_DEPOT
               WHERE role_name NOT IN ('TRANSFORMER', 'RH_PAIE', 'ANALYSTE', 'RESP_DEPOT_QUEENS', 'RESP_DEPOT_BRONX'))
    -- Une politique attachée au tag ne référence que le tag ; une colonne attachée en direct apparaîtrait ici en domaine TABLE.
    UNION ALL SELECT 'MASK_TEXTE et MASK_DATE : attachées au tag DONNEE_PERSONNELLE (une référence TAG chacune)', 2,
              (SELECT COUNT(*) FROM refs WHERE politique IN ('MASK_TEXTE', 'MASK_DATE')
                                           AND ref_entity_domain = 'TAG' AND ref_entity_name = 'DONNEE_PERSONNELLE')
    UNION ALL SELECT 'MASK_TEXTE et MASK_DATE : aucune référence hors du tag (pas de colonne attachée en direct, nulle part)', 0,
              (SELECT COUNT(*) FROM refs WHERE politique IN ('MASK_TEXTE', 'MASK_DATE')
                                           AND NOT (ref_entity_domain = 'TAG' AND ref_entity_name = 'DONNEE_PERSONNELLE'))
    UNION ALL SELECT 'RAP_DEPOT : attachée à MARTS.DIM_DRIVER et MARTS.MART_DRIVER_MONTHLY', 2,
              (SELECT COUNT(*) FROM refs WHERE politique = 'RAP_DEPOT'
                                           AND ref_schema_name = 'MARTS' AND ref_entity_name IN ('DIM_DRIVER', 'MART_DRIVER_MONTHLY'))
    UNION ALL SELECT 'RAP_DEPOT : nulle part ailleurs (ni DIM_DEPOT, ni RAW, ni STAGING)', 0,
              (SELECT COUNT(*) FROM refs WHERE politique = 'RAP_DEPOT'
                                           AND NOT (ref_schema_name = 'MARTS' AND ref_entity_name IN ('DIM_DRIVER', 'MART_DRIVER_MONTHLY')))
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;
