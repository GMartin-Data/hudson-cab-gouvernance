-- =====================================================================
-- 08_verif_taches.sql — le test de taches_rh.sql, écrit avant lui (jour 3, étapes 6 et 7).
-- Ce qui doit être vrai :
--   le graphe du contrat existe dans MARTS : T_PURGE (racine, quotidienne), puis T_QUALITE, puis T_TABLES, propriété
--   du rôle des outils (une tâche s'exécute avec les droits de son propriétaire) ; les deux tâches filles sont activées ;
--   le seuil de la règle bloquante (50) est dans la configuration du graphe ;
--   la dernière exécution a enregistré une ligne par règle dans QUALITE_RESULTATS, avec la mesure, le seuil et le
--   statut attendus ; chaque exécution enregistre ses quatre lignes, statut OK ou ALERTE, rien d'autre ;
--   le blocage a été prouvé et il en reste une trace : une mesure de service_rattache enregistrée en ALERTE sous
--   un seuil abaissé (snowflake/verif/09_preuve_blocage.sql), donc écrite AVANT que la tâche n'échoue.
-- L'état de la racine (activée ou suspendue) n'est pas testé : elle est suspendue en fin de brief pour ne pas
-- consommer de crédits, et se lance à la main (EXECUTE TASK fonctionne sur une racine suspendue).
-- Que les règles tiennent après les tâches (politiques, tags, volumes) : verif/02, 04, 05 et 07, rejoués ensuite.
-- Rôle : TRANSFORMER, propriétaire des tâches.
-- Rejouable. Avant taches_rh.sql : 10 lignes KO (aucune tâche, aucune mesure). Entre taches_rh.sql et
-- 09_preuve_blocage.sql : 1 ligne KO, la preuve du blocage.
-- C'est bon quand : aucun KO dans la sortie, aucune erreur :
--   snow sql -c hudson_cab --filename snowflake/verif/08_verif_taches.sql | grep -c ' KO '   → 0
-- Constantes : les mesures du 2026-11-28 (4 licences en trop, 25 services sans chauffeur, 18 services en double,
-- 7 e-mails sans @) ; elles changent si le fichier RH est rechargé, pas avec les tâches.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

SHOW TASKS IN SCHEMA NYC_TAXI.MARTS
  ->> WITH t AS (
        SELECT "name" AS name, "owner" AS owner, "warehouse" AS warehouse, "schedule" AS schedule,
               "predecessors"::STRING AS predecessors, "state" AS state, "config"::STRING AS config
        FROM $1
      ),
      derniere AS (                                                    -- les lignes de la dernière exécution
        SELECT * FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS
        WHERE mesure_le = (SELECT MAX(mesure_le) FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS)
      ),
      attendu AS (
        SELECT 'Tâches : T_PURGE, T_QUALITE et T_TABLES existent, propriété de TRANSFORMER, sur NYC_TAXI_WH' AS verification, 3 AS attendu,
               (SELECT COUNT(*) FROM t WHERE name IN ('T_PURGE', 'T_QUALITE', 'T_TABLES')
                                         AND owner = 'TRANSFORMER' AND warehouse = 'NYC_TAXI_WH') AS obtenu
        UNION ALL
        SELECT 'Tâches : T_PURGE est la racine, planifiée chaque jour, sans prédécesseur', 1,
               (SELECT COUNT(*) FROM t WHERE name = 'T_PURGE' AND schedule LIKE 'USING CRON 0 6 * * * %'
                                         AND predecessors NOT LIKE '%T_%')
        UNION ALL
        SELECT 'Tâches : T_QUALITE part après T_PURGE, et elle seule', 1,
               (SELECT COUNT(*) FROM t WHERE name = 'T_QUALITE' AND predecessors LIKE '%NYC_TAXI.MARTS.T_PURGE%'
                                         AND predecessors NOT LIKE '%,%')
        UNION ALL
        SELECT 'Tâches : T_TABLES part après T_QUALITE, et elle seule (on ne reconstruit que si le contrôle est passé)', 1,
               (SELECT COUNT(*) FROM t WHERE name = 'T_TABLES' AND predecessors LIKE '%NYC_TAXI.MARTS.T_QUALITE%'
                                         AND predecessors NOT LIKE '%,%')
        UNION ALL
        SELECT 'Tâches : T_QUALITE et T_TABLES sont activées (une fille suspendue serait sautée)', 2,
               (SELECT COUNT(*) FROM t WHERE name IN ('T_QUALITE', 'T_TABLES') AND state = 'started')
        UNION ALL
        SELECT 'Tâches : le seuil bloquant de service_rattache vaut 50 dans la configuration du graphe', 1,
               (SELECT COUNT(*) FROM t WHERE name = 'T_PURGE' AND TRY_PARSE_JSON(config):seuil_service_rattache = 50)
        UNION ALL
        SELECT 'QUALITE_RESULTATS : la dernière exécution a enregistré les 4 règles avec leur mesure (4, 25, 18, 7)', 4,
               (SELECT COUNT(*) FROM derniere
                WHERE (regle, nb_anomalies) IN (('licence_unique', 4), ('service_rattache', 25),
                                                ('service_unique', 18), ('email_valide', 7)))
        UNION ALL
        SELECT 'QUALITE_RESULTATS : dernière exécution, seuils du contrat (0, 50, 0, 0)', 4,
               (SELECT COUNT(*) FROM derniere
                WHERE (regle, seuil) IN (('licence_unique', 0), ('service_rattache', 50),
                                         ('service_unique', 0), ('email_valide', 0)))
        UNION ALL
        SELECT 'QUALITE_RESULTATS : dernière exécution, service_rattache OK, les trois avertissements en ALERTE', 4,
               (SELECT COUNT(*) FROM derniere
                WHERE (regle, statut) IN (('licence_unique', 'ALERTE'), ('service_rattache', 'OK'),
                                          ('service_unique', 'ALERTE'), ('email_valide', 'ALERTE')))
        UNION ALL
        SELECT 'QUALITE_RESULTATS : le blocage est tracé (service_rattache en ALERTE sous un seuil abaissé, mesure écrite avant l''erreur)', 1,
               (SELECT IFF(COUNT(*) >= 1, 1, 0) FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS
                WHERE regle = 'service_rattache' AND statut = 'ALERTE' AND seuil < 50 AND nb_anomalies > seuil)
        UNION ALL
        SELECT 'QUALITE_RESULTATS : chaque exécution a enregistré exactement une ligne par règle', 0,
               (SELECT COUNT(*) FROM (SELECT mesure_le FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS
                                      GROUP BY mesure_le HAVING COUNT(*) <> 4 OR COUNT(DISTINCT regle) <> 4))
        UNION ALL
        SELECT 'QUALITE_RESULTATS : statut OK ou ALERTE, calculé à partir de la mesure et du seuil', 0,
               (SELECT COUNT(*) FROM NYC_TAXI.GOUVERNANCE.QUALITE_RESULTATS
                WHERE statut IS DISTINCT FROM IFF(nb_anomalies <= seuil, 'OK', 'ALERTE'))
      )
      SELECT verification, attendu, obtenu,
             IFF(obtenu = attendu, 'OK', 'KO') AS statut
      FROM attendu
      ORDER BY statut, verification;   -- 'KO' < 'OK' : les échecs d'abord

-- Pour information, sans OK ni KO : les exécutions des 7 derniers jours (TASK_HISTORY ne garde pas plus).
-- Une tâche dont le prédécesseur a échoué n'est pas planifiée : elle n'a pas de ligne pour cette exécution.
SELECT name, state, scheduled_time, completed_time, LEFT(error_message, 90) AS erreur
FROM TABLE(NYC_TAXI.INFORMATION_SCHEMA.TASK_HISTORY(
       SCHEDULED_TIME_RANGE_START => DATEADD(day, -7, CURRENT_TIMESTAMP()), RESULT_LIMIT => 100))
WHERE name IN ('T_PURGE', 'T_QUALITE', 'T_TABLES') AND state <> 'SCHEDULED'
ORDER BY scheduled_time DESC, completed_time DESC
LIMIT 12;
