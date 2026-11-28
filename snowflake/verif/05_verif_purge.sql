-- =====================================================================
-- 05_verif_purge.sql — le test de la règle R1, écrit avant la purge (jour 3, étape 1).
-- Ce qui doit être vrai : plus aucun chauffeur dont le contrat a pris fin il y a 5 ans ou plus, ni dans la
-- source (RAW.DRIVERS) ni dans sa copie (MARTS.DIM_DRIVER) ; la purge emporte les services du chauffeur avec
-- lui (elle ne fabrique pas de service sans chauffeur) ; elle ne supprime rien d'autre.
-- Rôle : TRANSFORMER, le seul qui lit RAW et voit toutes les lignes de MARTS en clair.
-- Rejouable. Avant la purge : 4 lignes KO. C'est bon quand : toutes les lignes affichent statut = OK.
--
-- Constantes relevées le 2026-11-28 avec ce rôle : 46 chauffeurs échus sur 400, donc 354 restants ; aucun de
-- leurs services dans le fichier (les services vont de janvier à mars 2025), donc 25 951 services et 914 lignes
-- de mart inchangés ; 25 services sans chauffeur connu dès le chargement. Prochaine échéance R1 : 2028-01-11,
-- les constantes tiennent jusque-là.
-- =====================================================================
USE SECONDARY ROLES NONE;
USE ROLE TRANSFORMER;
USE WAREHOUSE NYC_TAXI_WH;

WITH attendu AS (
    -- R1 : plus de chauffeur échu, dans la source et dans sa copie
    SELECT 'RAW.DRIVERS : aucun chauffeur parti depuis 5 ans ou plus' AS verification, 0 AS attendu,
           (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS
            WHERE end_date <= DATEADD(year, -5, CURRENT_DATE())) AS obtenu
    UNION ALL
    SELECT 'MARTS.DIM_DRIVER : aucun chauffeur parti depuis 5 ans ou plus', 0,
           (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER
            WHERE end_date <= DATEADD(year, -5, CURRENT_DATE()))
    UNION ALL
    SELECT 'RAW.DRIVERS : 354 chauffeurs restants (400 moins les 46 échus)', 354,
           (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS)
    UNION ALL
    SELECT 'MARTS.DIM_DRIVER : 354 chauffeurs restants', 354,
           (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER)
    UNION ALL
    -- R1 partout : les copies ne gardent pas un chauffeur que la source n'a plus
    SELECT 'MARTS.DIM_DRIVER : aucun chauffeur absent de RAW.DRIVERS', 0,
           (SELECT COUNT(*) FROM NYC_TAXI.MARTS.DIM_DRIVER d
            WHERE NOT EXISTS (SELECT 1 FROM NYC_TAXI.RAW.DRIVERS r WHERE r.driver_id = d.driver_id))
    UNION ALL
    -- Si la purge laissait les services d'un chauffeur supprimé, ces deux comptes monteraient
    SELECT 'RAW.DRIVER_SHIFTS : 25 services sans chauffeur connu, ceux du fichier, pas un de plus', 25,
           (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS s
            WHERE NOT EXISTS (SELECT 1 FROM NYC_TAXI.RAW.DRIVERS r WHERE r.driver_id = s.driver_id))
    UNION ALL
    SELECT 'MARTS.MART_DRIVER_MONTHLY : 25 lignes sans chauffeur connu, pas une de plus', 25,
           (SELECT COUNT(*) FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY m
            WHERE NOT EXISTS (SELECT 1 FROM NYC_TAXI.RAW.DRIVERS r WHERE r.driver_id = m.driver_id))
    UNION ALL
    -- La purge ne supprime rien d'autre : aucun chauffeur échu n'a de service dans le fichier
    SELECT 'RAW.DRIVER_SHIFTS : 25 951 services, volume inchangé', 25951,
           (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVER_SHIFTS)
    UNION ALL
    SELECT 'MARTS.MART_DRIVER_MONTHLY : 914 lignes, volume inchangé', 914,
           (SELECT COUNT(*) FROM NYC_TAXI.MARTS.MART_DRIVER_MONTHLY)
    UNION ALL
    SELECT 'RAW.DRIVERS : aucun chauffeur en poste (end_date vide) supprimé, 290 comme au chargement', 290,
           (SELECT COUNT(*) FROM NYC_TAXI.RAW.DRIVERS WHERE end_date IS NULL)
)
SELECT verification, attendu, obtenu,
       IFF(obtenu = attendu, 'OK', 'KO') AS statut
FROM attendu
ORDER BY statut, verification;   -- 'KO' < 'OK' : les échecs d'abord
