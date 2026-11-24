-- =====================================================================
-- 04_verif_acces.sql — le test de 03_masquage.sql et 04_acces_depot.sql, écrit avant eux (jour 2, étapes 3, 5, 6).
-- Ce qui doit être vrai, rôle par rôle, d'après la matrice du contrat (section 4) : le nombre de lignes vues dans
-- DIM_DRIVER et MART_DRIVER_MONTHLY, les colonnes en clair et les colonnes masquées, driver_id visible des rôles
-- métier, l'année de naissance seule pour ANALYSTE, les refus (RAW, STAGING, GOUVERNANCE sur les données),
-- TRANSFORMER qui voit tout en clair (sinon il recopierait des masques), ACCOUNTADMIN qui ne voit aucune ligne
-- de MARTS et des colonnes masquées dans RAW, et les politiques attachées là où on les attend.
-- Rôles : une section par rôle, chacune commence par USE SECONDARY ROLES NONE / USE ROLE / USE WAREHOUSE (réflexes 1 et 2).
-- Les refus sont attendus dans un bloc EXECUTE IMMEDIATE : sans lui, la CLI s'arrête à la première erreur.
-- Rejouable. Avant 03 et 04 : des lignes KO (valeurs en clair, tous les dépôts visibles), puis une erreur sur
-- ACCES_DEPOT qui n'existe pas encore. C'est bon quand : aucun KO dans la sortie, aucune erreur :
--   snow sql -c hudson_cab -f snowflake/verif/04_verif_acces.sql | grep -c KO   → 0
-- Les valeurs de contrôle (400, 914, 3, 161/365 Queens, 122/290 Bronx, 12 téléphones vides, 25 services sans
-- chauffeur connu, 398 dates de naissance hors 1er janvier, 50 années, 393 e-mails avec @ sur 400) ont été relevées
-- avec TRANSFORMER le 2026-11-24. Les 7 e-mails sans @ sont une anomalie du fichier (règle email_valide, jour 3) :
-- un masque partiel « garder le domaine » n'a pas de domaine à garder, ils doivent sortir en ***** complet.
-- =====================================================================

-- ===================================================================== RH_PAIE : tout le domaine RH, tous les dépôts, tout en clair
USE SECONDARY ROLES NONE;
USE ROLE RH_PAIE;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'RH_PAIE : DIM_DRIVER, tous les chauffeurs' AS verification, 400 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'RH_PAIE : MART_DRIVER_MONTHLY, toutes les lignes', 914, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'RH_PAIE : DIM_DEPOT, les 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
    UNION ALL SELECT 'RH_PAIE : le chauffeur D0003 (Queens) est visible', 1, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'RH_PAIE : aucune valeur masquée (nom, prénom, e-mail, téléphone, licence)', 0,
              (SELECT COUNT(*) FROM d WHERE first_name = '*****' OR last_name = '*****' OR email LIKE '*****%'
                                        OR phone = '*****' OR tlc_license_number = '*****')
    UNION ALL SELECT 'RH_PAIE : e-mails réels (393 contiennent @, 7 non : anomalie du fichier ; aucun ne commence par *****)', 393,
              (SELECT COUNT(*) FROM d WHERE email LIKE '%@%' AND email NOT LIKE '*****%')
    UNION ALL SELECT 'RH_PAIE : dates de naissance complètes (398 ne tombent pas un 1er janvier)', 398,
              (SELECT COUNT(*) FROM d WHERE DAYOFYEAR(birth_date) <> 1)
    -- Un masque remplace aussi les NULL : si la paie voyait 0 NULL, c'est qu'elle lirait des masques.
    UNION ALL SELECT 'RH_PAIE : téléphones en clair (les 12 vides du fichier restent NULL)', 12,
              (SELECT COUNT(*) FROM d WHERE phone IS NULL)
    UNION ALL SELECT 'RH_PAIE : driver_name en clair dans le mart (25 NULL = services sans chauffeur connu)', 25,
              (SELECT COUNT(*) FROM m WHERE driver_name IS NULL)
    UNION ALL SELECT 'RH_PAIE : aucun driver_name masqué dans le mart', 0, (SELECT COUNT(*) FROM m WHERE driver_name = '*****')
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
  WHEN STATEMENT_ERROR THEN RETURN 'OK : RAW.DRIVER_SHIFTS refusé à RH_PAIE';
END;
$$;

-- ===================================================================== RESP_DEPOT_QUEENS : Queens seulement ; nom, prénom, téléphone en clair
USE SECONDARY ROLES NONE;
USE ROLE RESP_DEPOT_QUEENS;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'RESP_DEPOT_QUEENS : DIM_DRIVER, les chauffeurs de Queens seulement' AS verification, 161 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : un seul dépôt visible', 1, (SELECT COUNT(DISTINCT depot) FROM d)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : et c''est Queens', 161, (SELECT COUNT(*) FROM d WHERE depot = 'Queens')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : MART_DRIVER_MONTHLY, les lignes de Queens seulement', 365, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : DIM_DEPOT sans filtre, les 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : le chauffeur D0003 (Queens) est visible', 1, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : nom, prénom et téléphone en clair (aucun masque)', 0,
              (SELECT COUNT(*) FROM d WHERE first_name = '*****' OR last_name = '*****' OR phone = '*****')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : driver_id visible (aucun masque)', 0, (SELECT COUNT(*) FROM d WHERE driver_id = '*****')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : e-mails masqués (*****@domaine, ou ***** sans @)', 161, (SELECT COUNT(*) FROM d WHERE email LIKE '*****%')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : licences TLC masquées', 161, (SELECT COUNT(*) FROM d WHERE tlc_license_number = '*****')
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : dates de naissance absentes (NULL)', 161, (SELECT COUNT(*) FROM d WHERE birth_date IS NULL)
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : driver_name en clair dans le mart (aucun masque)', 0, (SELECT COUNT(*) FROM m WHERE driver_name = '*****')
    -- Limite connue, documentée dans docs/ACCES.md : le compte de lignes du catalogue est physique, la politique ne le filtre pas.
    UNION ALL SELECT 'RESP_DEPOT_QUEENS : INFORMATION_SCHEMA.TABLES.row_count de DIM_DRIVER donne le total physique (limite connue)', 400,
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
  WHEN STATEMENT_ERROR THEN RETURN 'OK : RAW.DRIVERS refusé à RESP_DEPOT_QUEENS';
END;
$$;

-- ===================================================================== RESP_DEPOT_BRONX : Bronx seulement ; mêmes colonnes en clair
USE SECONDARY ROLES NONE;
USE ROLE RESP_DEPOT_BRONX;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'RESP_DEPOT_BRONX : DIM_DRIVER, les chauffeurs du Bronx seulement' AS verification, 122 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'RESP_DEPOT_BRONX : et c''est le Bronx', 122, (SELECT COUNT(*) FROM d WHERE depot = 'Bronx')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : MART_DRIVER_MONTHLY, les lignes du Bronx seulement', 290, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'RESP_DEPOT_BRONX : le chauffeur D0003 (Queens) est invisible', 0, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : nom, prénom et téléphone en clair (aucun masque)', 0,
              (SELECT COUNT(*) FROM d WHERE first_name = '*****' OR last_name = '*****' OR phone = '*****')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : e-mails masqués (*****@domaine, ou ***** sans @)', 122, (SELECT COUNT(*) FROM d WHERE email LIKE '*****%')
    UNION ALL SELECT 'RESP_DEPOT_BRONX : licences TLC masquées et dates de naissance absentes', 122,
              (SELECT COUNT(*) FROM d WHERE tlc_license_number = '*****' AND birth_date IS NULL)
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
  WHEN STATEMENT_ERROR THEN RETURN 'OK : STAGING.STG_RH__DRIVERS refusé à RESP_DEPOT_BRONX';
END;
$$;

-- ===================================================================== ANALYSTE : tout MARTS, tous les dépôts, personne n'est nommable, l'année de naissance seule
USE SECONDARY ROLES NONE;
USE ROLE ANALYSTE;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'ANALYSTE : DIM_DRIVER, tous les chauffeurs' AS verification, 400 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'ANALYSTE : MART_DRIVER_MONTHLY, toutes les lignes', 914, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'ANALYSTE : DIM_DEPOT, les 3 dépôts', 3, (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DEPOT)
    UNION ALL SELECT 'ANALYSTE : driver_id visible, D0003 se retrouve (compter et joindre sans nommer)', 1, (SELECT COUNT(*) FROM d WHERE driver_id = 'D0003')
    UNION ALL SELECT 'ANALYSTE : nom, prénom et licence TLC masqués sur les 400 lignes', 400,
              (SELECT COUNT(*) FROM d WHERE first_name = '*****' AND last_name = '*****' AND tlc_license_number = '*****')
    -- Le masque remplace aussi les 12 NULL : l'analyste ne sait pas qui n'a pas de téléphone.
    UNION ALL SELECT 'ANALYSTE : téléphones masqués sur les 400 lignes, NULL compris', 400, (SELECT COUNT(*) FROM d WHERE phone = '*****')
    UNION ALL SELECT 'ANALYSTE : e-mails masqués (*****@domaine, ou ***** sans @)', 400, (SELECT COUNT(*) FROM d WHERE email LIKE '*****%')
    UNION ALL SELECT 'ANALYSTE : le domaine reste lisible sur les 393 adresses valides', 393, (SELECT COUNT(*) FROM d WHERE email LIKE '*****@_%')
    UNION ALL SELECT 'ANALYSTE : dates de naissance réduites au 1er janvier de l''année', 400, (SELECT COUNT(*) FROM d WHERE DAYOFYEAR(birth_date) = 1)
    UNION ALL SELECT 'ANALYSTE : aucune date de naissance NULL (l''année reste exploitable)', 0, (SELECT COUNT(*) FROM d WHERE birth_date IS NULL)
    UNION ALL SELECT 'ANALYSTE : les 50 années de naissance distinctes du fichier sont conservées', 50, (SELECT COUNT(DISTINCT YEAR(birth_date)) FROM d)
    UNION ALL SELECT 'ANALYSTE : driver_name masqué sur les 914 lignes du mart (NULL compris)', 914, (SELECT COUNT(*) FROM m WHERE driver_name = '*****')
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
  WHEN STATEMENT_ERROR THEN RETURN 'OK : RAW.DRIVERS refusé à ANALYSTE';
END;
$$;

-- ===================================================================== TRANSFORMER : le rôle des outils voit tout, en clair, sinon il recopie des masques et des NULL
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

WITH d AS (SELECT * FROM NYC_TAXI.MARTS.DIM_DRIVER),
     m AS (SELECT * FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY),
attendu AS (
    SELECT 'TRANSFORMER : DIM_DRIVER, tous les chauffeurs (ACCES_DEPOT le laisse passer)' AS verification, 400 AS attendu, (SELECT COUNT(*) FROM d) AS obtenu
    UNION ALL SELECT 'TRANSFORMER : MART_DRIVER_MONTHLY, toutes les lignes', 914, (SELECT COUNT(*) FROM m)
    UNION ALL SELECT 'TRANSFORMER : aucune valeur masquée dans DIM_DRIVER', 0,
              (SELECT COUNT(*) FROM d WHERE first_name = '*****' OR last_name = '*****' OR email LIKE '*****%'
                                        OR phone = '*****' OR tlc_license_number = '*****' OR driver_id = '*****')
    UNION ALL SELECT 'TRANSFORMER : dates de naissance complètes (398 hors 1er janvier)', 398, (SELECT COUNT(*) FROM d WHERE DAYOFYEAR(birth_date) <> 1)
    UNION ALL SELECT 'TRANSFORMER : téléphones en clair (12 NULL)', 12, (SELECT COUNT(*) FROM d WHERE phone IS NULL)
    -- 25 et pas plus : si TRANSFORMER manquait dans ACCES_DEPOT, le mart se reconstruirait avec driver_name NULL partout.
    UNION ALL SELECT 'TRANSFORMER : driver_name du mart intact (25 NULL, pas un de plus)', 25, (SELECT COUNT(*) FROM m WHERE driver_name IS NULL)
    UNION ALL SELECT 'TRANSFORMER : aucun driver_name masqué dans le mart', 0, (SELECT COUNT(*) FROM m WHERE driver_name = '*****')
    UNION ALL SELECT 'TRANSFORMER : RAW.DRIVERS en clair (393 e-mails avec @, aucun masque)', 393,
              (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS WHERE email LIKE '%@%' AND email NOT LIKE '*****%')
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;

-- ===================================================================== ACCOUNTADMIN : hors de la matrice ; aucune ligne de MARTS, colonnes masquées dans RAW ; et les politiques sont bien là
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
        UNION ALL SELECT 'ACCOUNTADMIN : RAW.DRIVERS, 400 lignes visibles par héritage de TRANSFORMER', 400, (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS)
        UNION ALL SELECT 'ACCOUNTADMIN : RAW.DRIVERS, rien en clair (nom, prénom, licence, téléphone et driver_id masqués)', 400,
                  (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS
                   WHERE first_name = '*****' AND last_name = '*****' AND tlc_license_number = '*****' AND phone = '*****' AND driver_id = '*****')
        UNION ALL SELECT 'ACCOUNTADMIN : RAW.DRIVERS, e-mails masqués et dates de naissance absentes', 400,
                  (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS WHERE email LIKE '*****%' AND birth_date IS NULL)
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
        UNION ALL SELECT 'Aucune politique attachée ailleurs que via le tag ou sur depot (17 masquages + 2 lignes = 19 références)', 19,
                  (SELECT COUNT(*) FROM refs)
      )
      SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
      FROM attendu ORDER BY statut, verification;

-- ===================================================================== GOUVERNANCE : écrit les règles, ne lit aucune donnée ; lit sa table de correspondance
USE SECONDARY ROLES NONE;
USE ROLE GOUVERNANCE;
USE WAREHOUSE NYC_TAXI_WH;

EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.MARTS.DIM_DRIVER;
  RETURN 'KO : GOUVERNANCE lit MARTS.DIM_DRIVER (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN RETURN 'OK : MARTS.DIM_DRIVER refusé à GOUVERNANCE';
END;
$$;

EXECUTE IMMEDIATE $$
DECLARE n INTEGER;
BEGIN
  SELECT COUNT(*) INTO :n FROM NYC_TAXI.RAW.DRIVERS;
  RETURN 'KO : GOUVERNANCE lit RAW.DRIVERS (' || n || ' lignes)';
EXCEPTION
  WHEN STATEMENT_ERROR THEN RETURN 'OK : RAW.DRIVERS refusé à GOUVERNANCE';
END;
$$;

-- La table de correspondance : la règle « qui voit quel dépôt » est en données, pas dans la politique.
WITH attendu AS (
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
)
SELECT verification, attendu, obtenu, IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu ORDER BY statut, verification;
