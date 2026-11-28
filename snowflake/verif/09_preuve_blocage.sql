-- =====================================================================
-- 09_preuve_blocage.sql — la preuve que la règle bloquante arrête la chaîne (jour 3, étape 6).
-- ATTENTION, ce script ÉCRIT, contrairement aux autres fichiers de verif/ : il lance deux fois le graphe de tâches,
-- donc deux purges (sans effet si rien n'est échu), une reconstruction de MARTS, et 8 lignes de plus dans
-- QUALITE_RESULTATS.
--   1. Une exécution avec le seuil de service_rattache abaissé de 50 à 10, pour cette exécution seulement
--      (EXECUTE TASK ... USING CONFIG : le graphe n'est pas modifié, il n'y a pas de seuil à remettre).
--      Attendu, avec 25 services sans chauffeur : T_PURGE réussit, T_QUALITE enregistre ses quatre lignes puis échoue,
--      T_TABLES ne part pas et MARTS n'est pas reconstruit.
--   2. Une exécution normale : le seuil est de nouveau 50, les trois tâches réussissent.
-- Rôle : TRANSFORMER, propriétaire des tâches. Rejouable (chaque passage ajoute ses 8 lignes).
-- C'est bon quand : aucun KO dans la sortie, aucune erreur ; puis snowflake/verif/08_verif_taches.sql est sans KO.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

-- ===================================================================== 1. Une exécution avec le seuil abaissé
-- AWAIT attend la fin du graphe et renvoie une erreur s'il échoue. Le bloc attrape cette erreur attendue, sans quoi
-- la CLI s'arrêterait ici ; un graphe qui réussirait sortirait en KO.
EXECUTE IMMEDIATE $$
BEGIN
  EXECUTE TASK NYC_TAXI.MARTS.T_PURGE USING CONFIG = '{"seuil_service_rattache": 10}' AWAIT;
  RETURN 'KO : le graphe a réussi alors que le seuil était abaissé à 10.';
EXCEPTION
  WHEN OTHER THEN
    RETURN 'OK : le graphe a échoué, comme attendu. ' || SQLERRM;
END;
$$;

-- Ce que cette exécution a laissé. Une tâche dont le prédécesseur a échoué n'est pas planifiée : T_TABLES n'a
-- aucune ligne dans l'historique pour cette exécution, et c'est cette absence qui prouve le blocage.
WITH histo AS (
    SELECT name, state, error_message
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TASK_HISTORY(
           SCHEDULED_TIME_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP()), RESULT_LIMIT => 100))
    WHERE name IN ('T_PURGE', 'T_QUALITE', 'T_TABLES') AND state <> 'SCHEDULED'
    QUALIFY graph_run_group_id = FIRST_VALUE(graph_run_group_id) OVER (ORDER BY scheduled_time DESC)
),
derniere AS (
    SELECT * FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS
    WHERE mesure_le = (SELECT MAX(mesure_le) FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS)
),
attendu AS (
    SELECT 'Blocage : T_PURGE a réussi (la purge ne dépend pas de la qualité)' AS verification, 1 AS attendu,
           (SELECT COUNT(*) FROM histo WHERE name = 'T_PURGE' AND state = 'SUCCEEDED') AS obtenu
    UNION ALL
    SELECT 'Blocage : T_QUALITE a échoué avec le message de la règle bloquante', 1,
           (SELECT COUNT(*) FROM histo WHERE name = 'T_QUALITE' AND state = 'FAILED'
                                         AND error_message LIKE '%service_rattache en dépassement%')
    UNION ALL
    SELECT 'Blocage : T_TABLES n''est pas partie (aucune ligne dans l''historique de cette exécution)', 0,
           (SELECT COUNT(*) FROM histo WHERE name = 'T_TABLES')
    UNION ALL
    SELECT 'Blocage : la mesure a été enregistrée avant l''erreur (service_rattache : 25 anomalies, seuil 10, ALERTE)', 1,
           (SELECT COUNT(*) FROM derniere
            WHERE regle = 'service_rattache' AND nb_anomalies = 25 AND seuil = 10 AND statut = 'ALERTE')
    UNION ALL
    SELECT 'Blocage : les quatre règles ont leur ligne pour cette exécution', 4,
           (SELECT COUNT(DISTINCT regle) FROM derniere)
)
SELECT verification, attendu, obtenu,
       IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu
ORDER BY statut, verification;

-- ===================================================================== 2. Une exécution normale : le seuil est de nouveau 50
EXECUTE TASK NYC_TAXI.MARTS.T_PURGE AWAIT;

WITH histo AS (
    SELECT name, state
    FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TASK_HISTORY(
           SCHEDULED_TIME_RANGE_START => DATEADD(hour, -1, CURRENT_TIMESTAMP()), RESULT_LIMIT => 100))
    WHERE name IN ('T_PURGE', 'T_QUALITE', 'T_TABLES') AND state <> 'SCHEDULED'
    QUALIFY graph_run_group_id = FIRST_VALUE(graph_run_group_id) OVER (ORDER BY scheduled_time DESC)
),
derniere AS (
    SELECT * FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS
    WHERE mesure_le = (SELECT MAX(mesure_le) FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS)
),
attendu AS (
    SELECT 'Reprise : les trois tâches ont réussi' AS verification, 3 AS attendu,
           (SELECT COUNT(*) FROM histo WHERE state = 'SUCCEEDED') AS obtenu
    UNION ALL
    SELECT 'Reprise : service_rattache de nouveau mesurée contre le seuil du contrat (25 anomalies, seuil 50, statut OK)', 1,
           (SELECT COUNT(*) FROM derniere
            WHERE regle = 'service_rattache' AND nb_anomalies = 25 AND seuil = 50 AND statut = 'OK')
)
SELECT verification, attendu, obtenu,
       IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu
ORDER BY statut, verification;
