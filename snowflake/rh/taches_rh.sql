-- =====================================================================
-- taches_rh.sql — les trois tâches planifiées du contrat (jour 3, étape 6) : chaque jour on purge, on contrôle,
-- et on ne reconstruit MARTS que si le contrôle est passé.
--   T_PURGE   (racine, 6 h, heure de Paris) : la purge R1, les quatre DELETE de purge_rh.sql dans une transaction.
--   T_QUALITE (après T_PURGE)  : mesure les quatre règles de controles/ sur RAW, enregistre une ligne par règle dans
--                                QUALITE_RESULTATS, PUIS lève une erreur si la règle bloquante service_rattache dépasse.
--   T_TABLES  (après T_QUALITE): les trois INSERT OVERWRITE de rh/marts/. Ne part pas si T_QUALITE a échoué.
-- Une tâche ne lit pas de fichier : les instructions de purge_rh.sql, de controles/ et de rh/marts/ sont recopiées
-- ici, sans leurs USE. Toute modification là-bas se reporte ici.
-- Rôle : TRANSFORMER. Une tâche s'exécute avec les droits de son propriétaire : c'est le rôle des outils qui lit RAW
-- en clair et que ACCES_DEPOT laisse voir toutes les lignes.
-- Rejouable : la racine est suspendue d'abord (une tâche d'un graphe actif ne se modifie pas), CREATE OR ALTER TASK
-- met chaque tâche à jour sans la supprimer, puis le graphe est réactivé et lancé une fois.
-- C'est bon quand : la dernière requête affiche les trois tâches en SUCCEEDED pour l'exécution qui vient de finir,
-- et l'avant-dernière quatre lignes de QUALITE_RESULTATS ; puis snowflake/verif/08_verif_taches.sql est sans KO.
-- À la fin du brief : ALTER TASK NYC_TAXI.MARTS.T_PURGE SUSPEND; (une racine activée consomme des crédits chaque jour).
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- ===================================================================== 1. Suspendre la racine avant de modifier
ALTER TASK IF EXISTS NYC_TAXI.MARTS.T_PURGE SUSPEND;

-- ===================================================================== 2. T_PURGE : la racine
-- CONFIG : le seuil de la règle bloquante, lu par T_QUALITE. Il se surcharge pour une seule exécution, sans toucher
--   au graphe : EXECUTE TASK ... USING CONFIG (c'est ainsi que le blocage se prouve).
-- TIMEZONE : CURRENT_DATE() et l'heure des mesures sont celles de Paris, où se trouve le responsable du traitement.
-- SUSPEND_TASK_AFTER_NUM_FAILURES = 0 : par défaut, Snowflake suspend la racine après 10 exécutions du graphe en
--   échec. Une règle bloquante qui dépasse dix jours de suite arrêterait donc aussi la purge : R1 ne doit pas en dépendre.
CREATE OR ALTER TASK NYC_TAXI.MARTS.T_PURGE
  WAREHOUSE = NYC_TAXI_WH
  SCHEDULE = 'USING CRON 0 6 * * * Europe/Paris'
  CONFIG = '{"seuil_service_rattache": 50}'
  TIMEZONE = 'Europe/Paris'
  SUSPEND_TASK_AFTER_NUM_FAILURES = 0
  COMMENT = 'R1 : supprime les chauffeurs dont le contrat a pris fin il y a 5 ans ou plus, dans RAW et dans MARTS.'
AS
EXECUTE IMMEDIATE $$
BEGIN
  BEGIN TRANSACTION;
  DELETE FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY
   WHERE driver_id IN (SELECT driver_id FROM NYC_TAXI.RAW.DRIVERS
                        WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()));
  DELETE FROM NYC_TAXI.RAW.DRIVER_SHIFTS
   WHERE driver_id IN (SELECT driver_id FROM NYC_TAXI.RAW.DRIVERS
                        WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()));
  DELETE FROM NYC_TAXI.MARTS.DIM_DRIVER
   WHERE end_date <= DATEADD(year, -5, CURRENT_DATE());
  DELETE FROM NYC_TAXI.RAW.DRIVERS
   WHERE end_date <= DATEADD(year, -5, CURRENT_DATE());
  COMMIT;
EXCEPTION
  WHEN OTHER THEN
    ROLLBACK;   -- tout ou rien, puis l'erreur remonte : la tâche échoue et la suite ne part pas
    RAISE;
END;
$$;

-- ===================================================================== 3. T_QUALITE : mesurer, enregistrer, puis bloquer
-- L'ordre compte : la mesure est enregistrée AVANT l'erreur, sinon un blocage ne laisserait aucune trace.
-- Un seuil absent de la configuration arrête la tâche : comparé à NULL, un dépassement passerait sans bruit.
CREATE OR ALTER TASK NYC_TAXI.MARTS.T_QUALITE
  WAREHOUSE = NYC_TAXI_WH
  TIMEZONE = 'Europe/Paris'
  COMMENT = 'Mesure les règles de qualité sur RAW, les enregistre dans QUALITE_RESULTATS, échoue si service_rattache dépasse son seuil.'
  AFTER NYC_TAXI.MARTS.T_PURGE
AS
EXECUTE IMMEDIATE $$
DECLARE
  instant         TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ;
  seuil_rattache  NUMBER(18,2)  DEFAULT SYSTEM$GET_TASK_GRAPH_CONFIG('seuil_service_rattache')::NUMBER(18,2);
  nb_rattache     INTEGER;
  sans_seuil      EXCEPTION (-20002, 'Seuil de service_rattache absent de la configuration du graphe (CONFIG de T_PURGE).');
  bloquee         EXCEPTION (-20001, 'Règle bloquante service_rattache en dépassement : MARTS n''est pas reconstruit.');
BEGIN
  IF (seuil_rattache IS NULL) THEN
    RAISE sans_seuil;
  END IF;

  SELECT COUNT(*) INTO :nb_rattache
  FROM NYC_TAXI.RAW.DRIVER_SHIFTS s
  WHERE NOT EXISTS (SELECT 1 FROM NYC_TAXI.RAW.DRIVERS d WHERE d.driver_id = s.driver_id);

  INSERT INTO NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS (regle, mesure_le, nb_anomalies, seuil, statut)
  SELECT regle, :instant, nb_anomalies, seuil, IFF(nb_anomalies <= seuil, 'OK', 'ALERTE')
  FROM (
    SELECT 'licence_unique' AS regle,
           (SELECT COUNT(*) - COUNT(DISTINCT tlc_license_number) FROM NYC_TAXI.RAW.DRIVERS) AS nb_anomalies,
           0 AS seuil
    UNION ALL
    SELECT 'service_rattache', :nb_rattache, :seuil_rattache
    UNION ALL
    SELECT 'service_unique',
           (SELECT COUNT(*) - COUNT(DISTINCT shift_id) FROM NYC_TAXI.RAW.DRIVER_SHIFTS),
           0
    UNION ALL
    SELECT 'email_valide',
           (SELECT COUNT(*) - COUNT_IF(email LIKE '%@%') FROM NYC_TAXI.RAW.DRIVERS),
           0
  );

  IF (nb_rattache > seuil_rattache) THEN
    RAISE bloquee;
  END IF;
  RETURN 'Qualité mesurée, chaîne non bloquée.';
END;
$$;

-- ===================================================================== 4. T_TABLES : reconstruire MARTS
-- INSERT OVERWRITE vide et remplit sans recréer : descriptions, tags et politiques restent en place.
CREATE OR ALTER TASK NYC_TAXI.MARTS.T_TABLES
  WAREHOUSE = NYC_TAXI_WH
  TIMEZONE = 'Europe/Paris'
  COMMENT = 'Reconstruit DIM_DEPOT, DIM_DRIVER et MART_DRIVER_MONTHLY, seulement si T_QUALITE a réussi.'
  AFTER NYC_TAXI.MARTS.T_QUALITE
AS
EXECUTE IMMEDIATE $$
BEGIN
  INSERT OVERWRITE INTO NYC_TAXI.MARTS.DIM_DEPOT (depot, quartier, ouvert_en, nb_places) VALUES
      ('Bronx',    'Hunts Point',       2009, 140),
      ('Brooklyn', 'East New York',     2011, 120),
      ('Queens',   'Long Island City',  2008, 180);

  INSERT OVERWRITE INTO NYC_TAXI.MARTS.DIM_DRIVER
  SELECT
      driver_id,
      first_name,
      last_name,
      email,
      phone,
      birth_date,
      tlc_license_number,
      depot,
      hire_date,
      end_date,
      end_date IS NULL                                                          AS is_active,
      ROUND(DATEDIFF(day, hire_date, COALESCE(end_date, CURRENT_DATE())) / 365.25, 1) AS tenure_years
  FROM NYC_TAXI.STAGING.STG_RH__DRIVERS;

  INSERT OVERWRITE INTO NYC_TAXI.MARTS.MART_DRIVER_MONTHLY
  SELECT
      DATE_TRUNC('month', s.shift_date)::date     AS activity_month,
      s.driver_id,
      d.first_name || ' ' || d.last_name          AS driver_name,
      s.depot,
      COUNT(*)                                    AS nb_shifts,
      ROUND(SUM(s.hours_worked), 1)               AS hours_worked,
      SUM(s.trips_count)                          AS trips_count,
      ROUND(SUM(s.revenue_usd), 2)                AS revenue_usd
  FROM NYC_TAXI.STAGING.STG_RH__DRIVER_SHIFTS s
  LEFT JOIN NYC_TAXI.MARTS.DIM_DRIVER d ON d.driver_id = s.driver_id
  GROUP BY 1, 2, 3, 4;
END;
$$;

-- ===================================================================== 5. Activer le graphe et le lancer une fois
-- Une tâche se crée suspendue. SYSTEM$TASK_DEPENDENTS_ENABLE active la racine et toutes celles qui en dépendent.
SELECT SYSTEM$TASK_DEPENDENTS_ENABLE('NYC_TAXI.MARTS.T_PURGE');

-- AWAIT attend la fin des trois tâches ; si l'une échoue, la commande renvoie l'erreur et le script s'arrête ici.
EXECUTE TASK NYC_TAXI.MARTS.T_PURGE AWAIT;

-- ===================================================================== 6. Vérifier
-- Les quatre lignes que cette exécution vient d'enregistrer
SELECT regle, mesure_le, nb_anomalies, seuil, statut
FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS
WHERE mesure_le = (SELECT MAX(mesure_le) FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS)
ORDER BY regle;

-- Les trois tâches de l'exécution qui vient de finir : SUCCEEDED, dans l'ordre du contrat
SELECT name, state, scheduled_time, completed_time, error_message
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TASK_HISTORY(
       SCHEDULED_TIME_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP()), RESULT_LIMIT => 100))
WHERE name IN ('T_PURGE', 'T_QUALITE', 'T_TABLES') AND state <> 'SCHEDULED'
QUALIFY graph_run_group_id = FIRST_VALUE(graph_run_group_id) OVER (ORDER BY scheduled_time DESC)
ORDER BY completed_time;
