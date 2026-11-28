-- Règle de qualité service_rattache (contrat, section 6) : chaque service appartient à un chauffeur connu.
-- Une ligne, une colonne : le nombre de services dont le driver_id est vide ou absent de RAW.DRIVERS.
-- Seuil : 50 services. Dépassement : BLOQUANT (la mesure est enregistrée, puis T_TABLES ne reconstruit pas MARTS).
-- Sans chauffeur, le service arrive dans MART_DRIVER_MONTHLY avec un driver_name vide, sans erreur.
-- NOT EXISTS plutôt que NOT IN : NOT IN ne renvoie rien dès qu'un driver_id est NULL d'un côté.
SELECT COUNT(*) AS nb_anomalies
FROM NYC_TAXI.RAW.DRIVER_SHIFTS s
WHERE NOT EXISTS (SELECT 1 FROM NYC_TAXI.RAW.DRIVERS d WHERE d.driver_id = s.driver_id);
